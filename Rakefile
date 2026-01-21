require 'rake'
require 'digest'
require 'io/console'
require 'pg'
require 'rspec/core/rake_task'
require 'shellwords'
require 'webrick'
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

  desc 'Update the bundled JavaScript for the iOS app'
  task :update_bundle do
    Dir.chdir('web') do
      command.run('./node_modules/.bin/esbuild src/Epub.ts --bundle --minify --format=iife --platform=browser --global-name=Bundle --outfile=../ios/Tribune/Tribune/bundle.js')
    end
  end

  desc 'Run a web server for the iOS app to use'
  task :dev_server do
    machine_ip = `ipconfig getifaddr en0`.strip
    puts "Starting iOS dev web server at http://#{machine_ip}:5173"
    puts 'To use, in Xcode:'
    puts "  1) go to Info.plist, and under 'App Transport Security Settings', set 'Allow Arbitrary Loads' to TRUE"
    puts '  2) in TribuneSchemeHandler.swift, look for LocalFile.getContents and uncomment the code there'
    puts 'Remember to run rake ios:update_bundle if you change any typescript code.'
    puts 'You can debug the webview through Safari > Develop and use the refresh button there to reload updated code.'
    puts

    Dir.chdir('ios/Tribune/Tribune/') do
      server = WEBrick::HTTPServer.new(Port: 5173, DocumentRoot: Dir.pwd)
      trap('INT') { server.shutdown }
      server.start
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

namespace :logo do
  desc 'Update the web icons from logos/logo-web.png'
  task :web do
    command.run('magick logos/logo-web.png -resize 192x192 web/public/favicon/android-chrome-192x192.png')
    command.run('magick logos/logo-web.png -resize 512x512 web/public/favicon/android-chrome-512x512.png')
    command.run('magick logos/logo-web.png -resize 180x180 web/public/favicon/apple-touch-icon.png')
    command.run('magick logos/logo-web.png -resize 32x32 web/public/favicon/favicon-32x32.png')
    command.run('magick logos/logo-web.png -resize 16x16 web/public/favicon/favicon-16x16.png')
    command.run('magick logos/logo-web.png -resize 16x16 web/public/favicon/favicon.ico')
  end

  desc 'Update the firefox extension icons from logos/logo-firefox.png'
  task :firefox do
    command.run('magick logos/logo-firefox.png -resize 96x96 firefox/icons/icon96.png')
    command.run('magick logos/logo-firefox.png -resize 48x48 firefox/icons/icon48.png')
  end

  desc 'Update the ios app icons from logos/logo-ios.png'
  task :ios do
    command.run('magick logos/logo-ios.png -resize 1024x1024 ios/Tribune/Tribune/Assets.xcassets/AppIcon.appiconset/logo-1024.png')
  end
end
