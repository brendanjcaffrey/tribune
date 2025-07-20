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

GET_NEWSLETTERS_QUERY_START = 'SELECT id, title, author, read, deleted, created_at, updated_at FROM newsletters'
GET_NEWSLETTERS_QUERY_END = 'ORDER BY updated_at DESC, id DESC LIMIT 100;'
GET_NEWSLETTERS_QUERY = "#{GET_NEWSLETTERS_QUERY_START} #{GET_NEWSLETTERS_QUERY_END}".freeze
GET_NEWSLETTERS_AFTER_QUERY = "#{GET_NEWSLETTERS_QUERY_START} WHERE (updated_at, id) > ($1, $2) #{GET_NEWSLETTERS_QUERY_END}".freeze
GET_NEWSLETTERS_BEFORE_QUERY = "#{GET_NEWSLETTERS_QUERY_START} WHERE (updated_at, id) < ($1, $2) #{GET_NEWSLETTERS_QUERY_END}".freeze

CREATE_NEWSLETTER_QUERY = 'INSERT INTO newsletters (title, author) VALUES ($1, $2) RETURNING id;'
CREATE_NEWSLETTER_AT_TIME_QUERY = 'INSERT INTO newsletters (title, author, created_at) VALUES ($1, $2, $3) RETURNING id;'
NEWSLETTER_EXISTS_QUERY = 'SELECT EXISTS(SELECT 1 FROM newsletters WHERE id = $1 AND deleted = FALSE);'

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
      payload, header = decode_jwt(token, CONFIG.secret)
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
end

set :port, CONFIG.server_port

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

  json({ jwt: build_jwt(username, CONFIG.secret) })
end

put '/auth' do
  username = get_validated_username
  halt 401, 'Unauthorized' if username.nil?

  json({ jwt: build_jwt(username, CONFIG.secret) })
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

post '/newsletters' do
  halt 401, 'Unauthorized' unless authed?
  halt 400, 'Missing file' if !params[:file] || !(tempfile = params[:file][:tempfile])
  halt 400, 'Missing metadata' if !params[:metadata] || params[:metadata].empty?

  begin
    metadata = JSON.parse(params[:metadata])
  rescue JSON::ParserError => e
    halt 400, "Invalid JSON: #{e.message}"
  end

  title = metadata['title']
  author = metadata['author']
  halt 400, 'Missing title or author in metadata' if title.nil? || title.empty? || author.nil? || author.empty?

  result = if metadata['created_at']
             query(CREATE_NEWSLETTER_AT_TIME_QUERY, [title, author, metadata['created_at']])
           else
             query(CREATE_NEWSLETTER_QUERY, [title, author])
           end

  if (id = result[0]['id'])
    new_path = File.join(CONFIG.newsletters_dir, "#{id}.epub")
    FileUtils.move(tempfile.path, new_path)
    json({ id: id.to_i })
  else
    halt 500, 'Failed to create newsletter'
  end
end

get '/newsletters/:id/epub' do
  halt 401, 'Unauthorized' unless authed?
  halt 400, 'Invalid ID' if params[:id].nil? || params[:id].to_i <= 0
  exists = query(NEWSLETTER_EXISTS_QUERY, [params[:id]])[0]['exists'] == 't'
  halt 404, 'Newsletter not found' unless exists

  file_path = File.join(CONFIG.newsletters_dir, "#{params[:id]}.epub")
  if File.exist?(file_path)
    send_file file_path, filename: params[:filename], type: 'application/epub+zip'
  else
    halt 500, 'File not found'
  end
end
