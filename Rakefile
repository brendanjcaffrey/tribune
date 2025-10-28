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
  if config.database_port
    "-h #{config.database_host.shellescape} -p #{config.database_port.to_i} -U #{config.database_username.shellescape}"
  else # want to connect over UDS
    "-h #{config.database_host.shellescape} -U #{config.database_username.shellescape}"
  end
end

command = TTY::Command.new

namespace :db do
  desc 'Create the main database and apply the schema'
  task :create do
    config = Config.load
    command = TTY::Command.new
    command.run("createdb #{db_args(config)} #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    command.run("cat schema.sql | psql -d #{config.database_name.shellescape} #{db_args(config)}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Apply the schema to the database'
  task :init do
    config = Config.load
    command = TTY::Command.new
    command.run("cat schema.sql | psql #{db_args(config)} -d #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Drop the main database'
  task :drop do
    config = Config.load
    command = TTY::Command.new
    command.run("dropdb #{db_args(config)} #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Drop & recreate the main database'
  task reset: %i[db:drop db:create]
end

namespace :testdb do
  desc 'Create the test database and apply the schema'
  task :create do
    config = Config.load
    command = TTY::Command.new
    command.run("createdb #{db_args(config)} #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    command.run("cat schema.sql | psql #{db_args(config)} -d #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Apply the schema to the test database'
  task :init do
    config = Config.load
    command = TTY::Command.new
    command.run("cat schema.sql | psql #{db_args(config)} -d #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Drop the test database'
  task :drop do
    config = Config.load
    command = TTY::Command.new
    command.run("dropdb #{db_args(config)} #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Drop & recreate the test database'
  task reset: %i[testdb:drop testdb:create]
end

namespace :server do
  desc 'Install ruby dependencies for the server'
  task :install do
    command.run('bundle')
  end

  desc 'Lint the ruby code'
  task :lint do
    command.run('bundle exec rubocop Rakefile server/')
  end

  desc 'Run the ruby server'
  task :run do
    require_relative 'server/server'
    Server.run!
  end

  desc 'Run the server tests'
  RSpec::Core::RakeTask.new(:spec) do |t|
    t.pattern = Dir.glob('server/spec/*_spec.rb')
  end
end

namespace :web do
  desc 'Install node dependencies for the web app'
  task :install do
    Dir.chdir('web') do
      command.run('npm install')
    end
  end

  desc 'Build the web app for distribution'
  task build: %i[web:install] do
    command.run('cd web && npm run build')
  end

  desc 'Run the web app in development mode'
  task :vite do
    Dir.chdir('web') do
      exec('node_modules/.bin/vite')
    end
  end

  desc 'Run the web tests'
  task :vitest do
    Dir.chdir('web') do
      exec('npx vitest')
    end
  end

  desc 'Lint the ui code'
  task :lint do
    Dir.chdir('web') do
      command.run('npm run lint')
    end
  end

  desc 'Format the web code'
  task :format do
    Dir.chdir('web') do
      exec('npm run format')
    end
  end

  desc 'Check formatting in the web code'
  task :format_check do
    Dir.chdir('web') do
      command.run('npm run format:check')
    end
  end
end

namespace :ios do
  desc 'Format the ios code'
  task :format do
    Dir.chdir('web') do
      exec('npm run ios_format')
    end
  end

  desc 'Check formatting in the ios code'
  task :format_check do
    Dir.chdir('web') do
      command.run('npm run ios_format:check')
    end
  end
end

desc 'Install ruby & node dependencies'
task install: %i[server:install web:install]

desc 'Run all checks'
task checks: %i[server:lint web:lint web:format_check ios:format_check]

namespace :user do
  desc 'Create a user interactively'
  task :create do
    config = Config.load

    print 'Enter username: '
    username = $stdin.gets.strip

    print 'Enter password: '
    password = $stdin.noecho(&:gets).strip
    puts

    print 'Confirm password: '
    password_confirmation = $stdin.noecho(&:gets).strip
    puts

    if password != password_confirmation
      puts '❌ Passwords do not match.'
      exit 1
    end

    hashed_password = Digest::SHA256.hexdigest(password)

    db = nil
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
      db&.close
    end
  end

  desc 'Generate a JWT for a user interactively'
  task :jwt do
    config = Config.load

    print 'Enter username: '
    username = $stdin.gets.strip

    db = PG.connect(
      dbname: config.database_name,
      user: config.database_username,
      password: config.database_password,
      host: config.database_host,
      port: config.database_port
    )
    res = db.exec_params('SELECT EXISTS(SELECT 1 FROM users WHERE username = $1)', [username])
    if res.to_a[0]['exists'] != 't'
      puts "❌ User does not exist: #{username}"
      exit 1
    end

    puts build_jwt(username, config.server_secret)
  end
end
