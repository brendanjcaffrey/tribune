# frozen_string_literal: true

require 'connection_pool'
require 'sinatra'
require 'sinatra/contrib'
require 'json'
require 'pg'
require_relative './config'
require_relative './jwt'

NEWSLETTERS_PATH = File.join("#{File.expand_path(__dir__)}/../", 'newsletters')

ANY_USERS_EXIST_QUERY = 'SELECT EXISTS(SELECT 1 FROM users);'
VALID_USERNAME_QUERY = 'SELECT EXISTS(SELECT 1 FROM users WHERE username = $1);'
VALID_USERNAME_AND_PASSWORD_QUERY = 'SELECT EXISTS(SELECT 1 FROM users WHERE username = $1 AND password_sha256 = $2);'

GET_NEWSLETTERS_QUERY = 'SELECT id, title, author, filename, updated_at FROM newsletters;'
GET_NEWSLETTERS_AFTER_QUERY = 'SELECT id, title, author, filename, updated_at FROM newsletters WHERE updated_at > $1;'
CREATE_NEWSLETTER_QUERY = 'INSERT INTO newsletters (title, author, filename) VALUES ($1, $2, $3);'

CONFIG = Config.load
DB_POOL = ConnectionPool.new(size: 5, timeout: 5) do
  PG.connect(
    dbname: ENV['RACK_ENV'] == 'test' ? CONFIG.test_database_name : CONFIG.database_name,
    user: CONFIG.database_username,
    password: CONFIG.database_password,
    host: CONFIG.database_host,
    port: CONFIG.database_port
  )
end

helpers do
  def query(sql, params = [])
    result = nil
    DB_POOL.with do |conn|
      result = conn.exec_params(sql, params)
    end
    result.to_a
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
set :lock, true

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

  resp = { jwt: build_jwt(username, CONFIG.secret) }
  json resp
end

put '/auth' do
  username = get_validated_username
  halt 401, 'Unauthorized' if username.nil?

  resp = { jwt: build_jwt(username, CONFIG.secret) }
  json resp
end

get '/newsletter' do
  if params[:after]
    begin
      after_time = Time.parse(params[:after])
    rescue ArgumentError => e
      halt 400, "Invalid date format: #{e.message}"
    end
    result = query(GET_NEWSLETTERS_AFTER_QUERY, [after_time])
  else
    result = query(GET_NEWSLETTERS_QUERY)
  end

  vals = result.values.to_a.map do |row|
    { id: row[0],
      title: row[1],
      author: row[2],
      filename: row[3],
      updated_at: row[4] }
  end
  json vals
end

post '/newsletter' do
  halt 400, 'Missing file' if !params[:file] || !(tempfile = params[:file][:tempfile])
  halt 400, 'Missing metadata' if !params[:metadata] || params[:metadata].empty?

  begin
    metadata = JSON.parse(params[:metadata])
  rescue JSON::ParserError => e
    halt 400, "Invalid JSON: #{e.message}"
  end

  title = metadata['title']
  author = metadata['author']
  halt 400, 'Missing title or author in metadata' if title.nil? || author.nil?

  ebook_md5 = Digest::MD5.file(tempfile).hexdigest
  FileUtils.move(tempfile.path, "#{NEWSLETTERS_PATH}/#{ebook_md5}.epub")

  query(CREATE_NEWSLETTER_QUERY, [title, author, "#{ebook_md5}.epub"])
  'Upload successful'
end
