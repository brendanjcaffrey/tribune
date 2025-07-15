# frozen_string_literal: true

require 'connection_pool'
require 'sinatra'
require 'sinatra/contrib'
require 'json'
require 'pg'

NEWSLETTERS_PATH = "#{File.expand_path(__dir__)}/newsletters"
GET_QUERY = 'SELECT id, title, author, filename, updated_at FROM newsletters;'
GET_AFTER_QUERY = 'SELECT id, title, author, filename, updated_at FROM newsletters WHERE updated_at > $1;'
CREATE_QUERY = 'INSERT INTO newsletters (title, author, filename) VALUES ($1, $2, $3);'

db = PG.connect(
  dbname: 'tribune',
  user: 'Brendan',
  password: '',
  host: 'localhost',
  port: 5432
)

get '/newsletter' do
  if params[:after]
    begin
      after_time = Time.parse(params[:after])
    rescue ArgumentError => e
      halt 400, "Invalid date format: #{e.message}"
    end
    result = db.exec_params(GET_AFTER_QUERY, [after_time])
  else
    result = db.exec(GET_QUERY)
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
    puts "Metadata: #{metadata.inspect}"
  rescue JSON::ParserError => e
    halt 400, "Invalid JSON: #{e.message}"
  end

  title = metadata['title']
  author = metadata['author']
  halt 400, 'Missing title or author in metadata' if title.nil? || author.nil?

  ebook_md5 = Digest::MD5.file(tempfile).hexdigest
  FileUtils.move(tempfile.path, "#{NEWSLETTERS_PATH}/#{ebook_md5}.epub")

  db.exec_params(CREATE_QUERY, [title, author, "#{ebook_md5}.epub"])
  'Upload successful'
end
