require 'rake'
require 'digest'
require 'io/console'
require 'pg'
require 'rspec/core/rake_task'
require 'shellwords'
require 'tty/command'
require_relative 'server/config'
require_relative 'server/jwt'

def db_args(config)
  "-h #{config.database_host.shellescape} -p #{config.database_port.to_i} -U #{config.database_username.shellescape}"
end

namespace :db do
  task :create do
    config = Config.load
    command = TTY::Command.new
    command.run("createdb #{db_args(config)} #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    command.run("cat schema.sql | psql -d #{config.database_name.shellescape} #{db_args(config)}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  task :drop do
    config = Config.load
    command = TTY::Command.new
    command.run("dropdb #{db_args(config)} #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  task reset: %i[db:drop db:create]
end

namespace :testdb do
  task :create do
    config = Config.load
    command = TTY::Command.new
    command.run("createdb #{db_args(config)} #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    command.run("cat schema.sql | psql #{db_args(config)} -d #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  task :drop do
    config = Config.load
    command = TTY::Command.new
    command.run("dropdb #{db_args(config)} #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  task reset: %i[testdb:drop testdb:create]
end

namespace :server do
  task :install do
    command = TTY::Command.new
    command.run('bundle')
  end

  task :run do
    ruby 'server/server.rb'
  end

  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = Dir.glob('server/spec/*_spec.rb')
  end
end

namespace :ui do
  task :install do
    Dir.chdir('ui') do
      exec('npm install')
    end
  end

  task :run do
    Dir.chdir('ui') do
      exec('npx expo start')
    end
  end
end

task install: %i[server:install ui:install]

namespace :user do
  task :create do
    config = Config.load

    print 'Enter username: '
    username = STDIN.gets.strip

    print 'Enter password: '
    password = STDIN.noecho(&:gets).strip
    puts

    print 'Confirm password: '
    password_confirmation = STDIN.noecho(&:gets).strip
    puts

    if password != password_confirmation
      puts '❌ Passwords do not match.'
      exit 1
    end

    hashed_password = Digest::SHA256.hexdigest(password)

    begin
      db = PG.connect(
        dbname: config.database_name,
        user: config.database_username,
        password: config.database_password,
        host: config.database_host,
        port: config.database_port
      )

      db.exec_params(
        'INSERT INTO users (username, password_sha256) VALUES ($1, $2)',
        [username, hashed_password]
      )

      puts "✅ User created: #{username}"
    rescue PG::Error => e
      puts "❌ Error creating user: #{e.message}"
    ensure
      db.close if db
    end
  end

  task :jwt do
    config = Config.load

    print 'Enter username: '
    username = STDIN.gets.strip

    puts build_jwt(username, config.secret)
  end
end
