# frozen_string_literal: true

require 'connection_pool'
require 'sinatra'
require 'json'
require 'pg'

NEWSLETTERS_PATH = "#{File.expand_path(__dir__)}/newsletters"
CREATE_QUERY = 'INSERT INTO newsletters (title, author, filename) VALUES ($1, $2, $3);'

db = PG.connect(
  dbname: 'tribune',
  user: 'Brendan',
  password: '',
  host: 'localhost',
  port: 5432
)

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
