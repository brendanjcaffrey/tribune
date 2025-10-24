# frozen_string_literal: true

require 'connection_pool'
require 'sinatra'
require 'sinatra/contrib'
require 'json'
require 'pg'
require_relative 'config'
require_relative 'jwt'

ANY_USERS_EXIST_QUERY = 'SELECT EXISTS(SELECT 1 FROM users);'
VALID_USERNAME_QUERY = 'SELECT EXISTS(SELECT 1 FROM users WHERE username = $1);'
VALID_USERNAME_AND_PASSWORD_QUERY = 'SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND password_sha256 = $2);'

# keeping swift and javascript happy with the date format
DATE_FORMAT = 'YYYY-MM-DD"T"HH24:MI:SS.US'
GET_NEWSLETTERS_QUERY_START = "SELECT id, title, author, source_mime_type, read, deleted, progress, to_char(created_at, '#{DATE_FORMAT}') || 'Z' as created_at, updated_at, epub_updated_at FROM newsletters".freeze
GET_NEWSLETTERS_QUERY_END = 'ORDER BY updated_at DESC, id DESC LIMIT 100;'
GET_NEWSLETTERS_QUERY = "#{GET_NEWSLETTERS_QUERY_START} #{GET_NEWSLETTERS_QUERY_END}".freeze
GET_NEWSLETTERS_AFTER_QUERY = "#{GET_NEWSLETTERS_QUERY_START} WHERE (updated_at, id) > ($1, $2) #{GET_NEWSLETTERS_QUERY_END}".freeze
GET_NEWSLETTERS_BEFORE_QUERY = "#{GET_NEWSLETTERS_QUERY_START} WHERE (updated_at, id) < ($1, $2) #{GET_NEWSLETTERS_QUERY_END}".freeze

CREATE_NEWSLETTER_QUERY = 'INSERT INTO newsletters (title, author, source_id, source_mime_type) VALUES ($1, $2, $3, $4) RETURNING id;'
CREATE_NEWSLETTER_AT_TIME_QUERY = 'INSERT INTO newsletters (title, author, source_id, source_mime_type, created_at) VALUES ($1, $2, $3, $4, $5) RETURNING id;'
NEWSLETTER_EXISTS_QUERY = 'SELECT EXISTS(SELECT 1 FROM newsletters WHERE id = $1 AND deleted = FALSE);'
NEWSLETTER_SOURCE_MIME_TYPE_QUERY = 'SELECT source_mime_type FROM newsletters WHERE id = $1 AND deleted = FALSE;'

MARK_NEWSLETTER_READ_QUERY = <<~SQL
  UPDATE newsletters
  SET
      read = TRUE,
      updated_at = CASE
                    WHEN read = FALSE THEN CURRENT_TIMESTAMP
                    ELSE updated_at
                   END
  WHERE id = $1 AND deleted = FALSE;
SQL
MARK_NEWSLETTER_UNREAD_QUERY = <<~SQL
  UPDATE newsletters
  SET
      read = FALSE,
      updated_at = CASE
                    WHEN read = TRUE THEN CURRENT_TIMESTAMP
                    ELSE updated_at
                   END
  WHERE id = $1 AND deleted = FALSE;
SQL
DELETE_NEWSLETTER_QUERY = 'UPDATE newsletters SET deleted = TRUE, updated_at = CURRENT_TIMESTAMP WHERE id = $1 AND deleted = FALSE;'
UPDATE_NEWSLETTER_PROGRESS_QUERY = <<~SQL
  UPDATE newsletters n
  SET
      progress   = $2,
      updated_at = CASE
                     WHEN n.progress IS DISTINCT FROM $2
                       THEN CURRENT_TIMESTAMP
                     ELSE updated_at
                   END
  WHERE id = $1
    AND deleted = FALSE;
SQL
EPUB_UPDATED_NEWSLETTER_QUERY = <<-SQL
  UPDATE newsletters
  SET
      updated_at = CURRENT_TIMESTAMP,
      epub_updated_at = CURRENT_TIMESTAMP,
      progress = ''
  WHERE source_id = $1
      AND deleted = FALSE
  RETURNING id;
SQL

EPUB_MIME_TYPE = 'application/epub+zip'
PDF_MIME_TYPE = 'application/pdf'
HTML_MIME_TYPE = 'text/html'
MIME_TYPES = { PDF_MIME_TYPE => 'pdf', HTML_MIME_TYPE => 'html' }.freeze

CONFIG = Config.load
DB_POOL = ConnectionPool.new(size: 5, timeout: 5) do
  PG.connect(
    dbname: ENV['RACK_ENV'] == 'test' ? CONFIG.test_database_name : CONFIG.database_name,
    user: CONFIG.database_username,
    password: CONFIG.database_password,
    host: CONFIG.database_host,
    port: CONFIG.database_port
  ).tap do |conn|
    conn.exec("SET TIME ZONE 'UTC'")
  end
end

class Server < Sinatra::Base
  helpers do
    def query(sql, params = [])
      result = nil
      DB_POOL.with do |conn|
        result = conn.exec_params(sql, params)
      end
      result.to_a
    end

    def update_query(sql, params = [])
      result = nil
      DB_POOL.with do |conn|
        result = conn.exec_params(sql, params)
      end
      result.cmd_tuples
    end

    def get_validated_username
      auth_header = request.env['HTTP_AUTHORIZATION']
      return nil if auth_header.nil? || !auth_header.start_with?('Bearer ')

      token = auth_header.gsub('Bearer ', '')
      begin
        payload, header = decode_jwt(token, CONFIG.server_secret)
      rescue StandardError
        return nil
      end

      exp = header['exp']
      return nil if exp.nil? || Time.now > Time.at(exp.to_i)

      username = payload['username']
      valid = query(VALID_USERNAME_QUERY, [username])[0]['exists'] == 't'
      return nil unless valid

      username
    end

    def authed?
      !get_validated_username.nil?
    end

    def source_path(id, mime_type)
      File.join(CONFIG.newsletters_dir, source_filename(id, mime_type))
    end

    def source_filename(id, mime_type)
      "#{id}.#{MIME_TYPES[mime_type]}"
    end

    def epub_path(id)
      File.join(CONFIG.newsletters_dir, epub_filename(id))
    end

    def epub_filename(id)
      "#{id}.epub"
    end
  end

  set :environment, ENV['RACK_ENV'] == 'test' ? 'test' : CONFIG.server_environment
  set :port, CONFIG.server_port if CONFIG.server_port
  set :bind, CONFIG.server_bind if CONFIG.server_bind

  get '/users' do
    result = query(ANY_USERS_EXIST_QUERY)
    json any: result[0]['exists'] == 't'
  end

  post '/auth' do
    halt 400, 'Missing username or password' if !params[:username] || !params[:password]

    username = params[:username]
    password_sha256 = Digest::SHA256.hexdigest(params[:password])
    result = query(VALID_USERNAME_AND_PASSWORD_QUERY, [username, password_sha256])
    halt 401, 'Unauthorized' if result[0]['exists'] != 't'

    json({ jwt: build_jwt(username, CONFIG.server_secret) })
  end

  put '/auth' do
    username = get_validated_username
    halt 401, 'Unauthorized' if username.nil?

    json({ jwt: build_jwt(username, CONFIG.server_secret) })
  end

  get '/newsletters' do
    halt 401, 'Unauthorized' unless authed?

    if params[:after_timestamp] || params[:after_id]
      halt 400, 'Invalid parameters' if params[:after_timestamp].nil? || params[:after_timestamp].empty? || params[:after_id].nil? || params[:after_id].empty? || params[:after_id].to_i <= 0
      result = query(GET_NEWSLETTERS_AFTER_QUERY, [params[:after_timestamp], params[:after_id]])
      meta = { after_timestamp: params[:after_timestamp], after_id: params[:after_id].to_i }
    elsif params[:before_timestamp] || params[:before_id]
      halt 400, 'Invalid parameters' if params[:before_timestamp].nil? || params[:before_timestamp].empty? || params[:before_id].nil? || params[:before_id].empty? || params[:before_id].to_i <= 0
      result = query(GET_NEWSLETTERS_BEFORE_QUERY, [params[:before_timestamp], params[:before_id]])
      meta = { before_timestamp: params[:before_timestamp], before_id: params[:before_id].to_i }
    else
      result = query(GET_NEWSLETTERS_QUERY)
      meta = {}
    end

    result.each do |row|
      row['id'] = row['id'].to_i
      row['read'] = row['read'] == 't'
      row['deleted'] = row['deleted'] == 't'
    end

    json({ meta: meta, result: result })
  end

  put '/newsletters/:id/read' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
    result = update_query(MARK_NEWSLETTER_READ_QUERY, [params[:id].to_i])
    halt 404, 'Newsletter not found' if result.zero?
    'Marked as read'
  end

  put '/newsletters/:id/unread' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
    result = update_query(MARK_NEWSLETTER_UNREAD_QUERY, [params[:id].to_i])
    halt 404, 'Newsletter not found' if result.zero?
    'Marked as unread'
  end

  delete '/newsletters/:id' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
    result = update_query(DELETE_NEWSLETTER_QUERY, [params[:id].to_i])
    halt 404, 'Newsletter not found' if result.zero?
    'Marked as deleted'
  end

  put '/newsletters/:id/progress' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
    halt 400, 'Progress not set' if params[:progress].nil?
    result = update_query(UPDATE_NEWSLETTER_PROGRESS_QUERY, [params[:id].to_i, params[:progress]])
    halt 404, 'Newsletter not found' if result.zero?
    'Updated progress'
  end

  post '/newsletters' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Missing source file' if !params[:source_file] || !(source_tempfile = params[:source_file][:tempfile])
    halt 400, 'Invalid source mime type' unless MIME_TYPES.key?(params[:source_file][:type])
    halt 400, 'Missing epub file' if !params[:epub_file] || !(epub_tempfile = params[:epub_file][:tempfile])
    halt 400, 'Invalid epub mime type' unless params[:epub_file][:type] == EPUB_MIME_TYPE
    halt 400, 'Missing metadata' if !params[:metadata] || params[:metadata].empty?
    halt 400, 'Invalid metadata mime type' unless params[:metadata][:type] == 'application/json'

    json = File.read(params[:metadata][:tempfile])
    begin
      metadata = JSON.parse(json)
    rescue JSON::ParserError => e
      halt 400, "Invalid JSON: #{e.message}"
    end

    title = metadata['title']
    author = metadata['author']
    source_id = metadata['source_id']
    halt 400, 'Missing title, author or source_id in metadata' if title.nil? || title.empty? || author.nil? || author.empty? || source_id.nil? || source_id.empty?

    source_mime_type = params[:source_file][:type]
    result = if metadata['created_at']
               query(CREATE_NEWSLETTER_AT_TIME_QUERY, [title, author, source_id, source_mime_type, metadata['created_at']])
             else
               query(CREATE_NEWSLETTER_QUERY, [title, author, source_id, source_mime_type])
             end

    if (id = result[0]['id'])
      FileUtils.move(source_tempfile.path, source_path(id, source_mime_type))
      FileUtils.move(epub_tempfile.path, epub_path(id))
      json({ id: id.to_i })
    else
      halt 500, 'Failed to create newsletter'
    end
  end

  get '/newsletters/:id/source' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
    mime_type_row = query(NEWSLETTER_SOURCE_MIME_TYPE_QUERY, [params[:id]]).first
    halt 404, 'Newsletter not found' if mime_type_row.nil?

    mime_type = mime_type_row['source_mime_type']
    halt 500, 'Invalid source mime type' unless MIME_TYPES.key?(mime_type)

    file_path = source_path(params[:id].to_i, mime_type)
    halt 500, 'File not found' unless File.exist?(file_path)

    if CONFIG.server_accel
      headers['X-Accel-Redirect'] = Rack::Utils.escape_path("/accel/newsletters/#{source_filename(params[:id], mime_type)}")
      headers['Content-Type'] = mime_type
    else
      send_file file_path, filename: params[:filename], type: EPUB_MIME_TYPE
    end
  end

  get '/newsletters/:id/epub' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
    exists = query(NEWSLETTER_EXISTS_QUERY, [params[:id]])[0]['exists'] == 't'
    halt 404, 'Newsletter not found' unless exists

    file_path = epub_path(params[:id].to_i)
    halt 500, 'File not found' unless File.exist?(file_path)

    if CONFIG.server_accel
      headers['X-Accel-Redirect'] = Rack::Utils.escape_path("/accel/newsletters/#{epub_filename(params[:id])}")
      headers['Content-Type'] = EPUB_MIME_TYPE
    else
      send_file file_path, filename: params[:filename], type: EPUB_MIME_TYPE
    end
  end

  put '/newsletters/:source_id/epub' do
    halt 401, 'Unauthorized' unless authed?
    halt 400, 'Invalid ID' if params[:source_id].nil? || params[:source_id].empty?
    halt 400, 'Missing epub file' if !params[:epub_file] || !(epub_tempfile = params[:epub_file][:tempfile])
    halt 400, 'Invalid epub mime type' unless params[:epub_file][:type] == EPUB_MIME_TYPE

    result = query(EPUB_UPDATED_NEWSLETTER_QUERY, [params[:source_id]])
    halt 404, 'Newsletter not found' if result.empty?

    FileUtils.move(epub_tempfile.path, epub_path(result.first['id']))
    'epub updated'
  end
end
