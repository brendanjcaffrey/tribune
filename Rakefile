require 'rake'
require 'digest'
require 'io/console'
require 'pg'
require 'que'
require 'rspec/core/rake_task'
require 'shellwords'
require 'webrick'
require 'pastel'
require 'tty/command'
require_relative 'server/config'
require_relative 'server/que_schedule'
require_relative 'server/db'
require_relative 'server/jwt'

def db_args(config)
  if config.database_port
    "-h #{config.database_host.shellescape} -p #{config.database_port.to_i} -U #{config.database_username.shellescape}"
  else # want to connect over UDS
    "-h #{config.database_host.shellescape} -U #{config.database_username.shellescape}"
  end
end

# que & que-scheduler both ship their schema as ruby-side migrations, so they
# stay out of schema.sql. this is idempotent: it no-ops once the db is up to
# date, and re-enqueues the scheduler job only if it isn't in the queue already
def que_migrate(config, dbname)
  Que.connection = Db.pool(config, size: 1, dbname: dbname)
  Que.migrate!(version: Que::Migrations::CURRENT_VERSION)
  puts "que schema in #{dbname} is at version #{Que.db_version}"

  # que-scheduler numbers its migrations separately from the gem version, and
  # migrating to the latest applies whichever of the earlier ones are missing
  Que::Scheduler::Migrations.migrate!(version: Que::Scheduler::Migrations::MAX_VERSION)
  Que::Scheduler::Migrations.reenqueue_scheduler_if_missing
  puts "que-scheduler schema in #{dbname} is at version #{Que::Scheduler::Migrations.db_version}"
end

# repaint logo-web.png in a flat colour, keeping the original's alpha channel as
# the shape. the parens are escaped because tty-command runs this through a shell
def recolor_logo(command, source, colour, size, dest)
  command.run("magick #{source} -alpha extract -alpha off " \
              "\\( +clone -fill '#{colour}' -colorize 100 \\) +swap " \
              "-compose copy_opacity -composite -resize #{size} PNG32:#{dest}")
end

# koreader reads KO_HOME as an override for its data directory, so we do too.
# otherwise datastorage.lua resolves it to ~/Library/Application Support/koreader on macos.
def koreader_data_dir
  home = ENV['KO_HOME'].to_s
  return home unless home.empty?

  File.join(Dir.home, 'Library', 'Application Support', 'koreader')
end

# android studio installs the platform tools outside the path, so fall back to
# the sdk's own location before giving up. ADB overrides the search entirely.
def adb_binary
  explicit = ENV['ADB'].to_s
  return File.executable?(explicit) ? explicit : nil unless explicit.empty?

  sdk_roots = [ENV['ANDROID_HOME'].to_s, ENV['ANDROID_SDK_ROOT'].to_s, File.join(Dir.home, 'Library', 'Android', 'sdk')]
  on_path = ENV['PATH'].to_s.split(File::PATH_SEPARATOR).map { |dir| File.join(dir, 'adb') }
  in_sdk = sdk_roots.compact.reject(&:empty?).map { |root| File.join(root, 'platform-tools', 'adb') }

  (on_path + in_sdk).find { |candidate| File.executable?(candidate) }
end

# `adb devices` prints a header line and then one "<serial>\t<state>" per device.
# only a device in the "device" state is usable: "unauthorized" means the rsa
# prompt hasn't been accepted yet, and "offline" means the connection went stale.
def adb_devices(command, adb)
  result = command.run!("#{adb.shellescape} devices")
  return [] unless result.success?

  result.out.lines.drop(1).filter_map do |line|
    serial, state = line.split("\t").map(&:strip)
    [serial, state] unless serial.to_s.empty? || state.to_s.empty?
  end
end

def adb_ready_device(command, adb)
  adb_devices(command, adb).find { |_serial, state| state == 'device' }&.first
end

def prompt(question)
  print question
  $stdin.gets.to_s.strip
end

command = TTY::Command.new

ROOT = __dir__
# default simulator for the ios test tasks. override with SIMULATOR=... if it
# isn't installed (`xcrun simctl list devices available` to see options).
SIMULATOR = 'iPhone 17 Pro'.freeze

namespace :db do
  desc 'Create the main database and apply the schema'
  task :create do
    config = Config.load
    command = TTY::Command.new
    command.run("createdb #{db_args(config)} #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    command.run("cat schema.sql | psql -d #{config.database_name.shellescape} #{db_args(config)}",
                env: { 'PGPASSWORD' => config.database_password })
    que_migrate(config, config.database_name)
  end

  desc 'Apply the schema to the database'
  task :init do
    config = Config.load
    command = TTY::Command.new
    command.run("cat schema.sql | psql #{db_args(config)} -d #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    que_migrate(config, config.database_name)
  end

  desc 'Drop the main database'
  task :drop do
    config = Config.load
    pastel = Pastel.new

    puts pastel.red.bold("\nWARNING: You are about to drop the main database '#{config.database_name}'.")
    puts pastel.red.bold('This action is irreversible and will destroy all data.')
    print pastel.yellow('Are you sure you want to proceed? [y/N] ')

    unless %w[y yes].include?($stdin.gets.strip.downcase)
      puts pastel.green('Database drop cancelled.')
      exit 1
    end

    command = TTY::Command.new
    command.run("dropdb #{db_args(config)} #{config.database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Apply the que job schema to the main database'
  task :que_migrate do
    config = Config.load
    que_migrate(config, config.database_name)
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
    que_migrate(config, config.test_database_name)
  end

  desc 'Apply the schema to the test database'
  task :init do
    config = Config.load
    command = TTY::Command.new
    command.run("cat schema.sql | psql #{db_args(config)} -d #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
    que_migrate(config, config.test_database_name)
  end

  desc 'Drop the test database'
  task :drop do
    config = Config.load
    command = TTY::Command.new
    command.run("dropdb #{db_args(config)} #{config.test_database_name.shellescape}",
                env: { 'PGPASSWORD' => config.database_password })
  end

  desc 'Apply the que job schema to the test database'
  task :que_migrate do
    config = Config.load
    que_migrate(config, config.test_database_name)
  end

  desc 'Drop & recreate the test database'
  task reset: %i[testdb:drop testdb:create]
end

namespace :que do
  desc 'Run the que worker against the main database'
  task :work do
    worker_count = ENV.fetch('QUE_WORKER_COUNT', '6')
    exec({ 'QUE_WORKER_COUNT' => worker_count },
         'bundle', 'exec', 'que', '--worker-count', worker_count, './server/que_setup.rb')
  end
end

namespace :server do
  desc 'Install the ruby & node dependencies for the server'
  task :install do
    command.run('bundle')
    # the article extractor runs @mozilla/readability in a node subprocess
    Dir.chdir('server/extract') do
      command.run('npm install')
    end
  end

  desc 'Lint the ruby code'
  task :lint do
    # ensure ~/.rubocop.yml exists to avoid RuboCop complaining
    FileUtils.touch(File.expand_path('~/.rubocop.yml'))
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

  desc 'Run the web tests interactively'
  task :vitest do
    Dir.chdir('web') do
      exec('npx vitest')
    end
  end

  desc 'Run the web tests once'
  task :vitest_run do
    Dir.chdir('web') do
      exec('npx vitest run')
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

  desc 'List the available xcode schemes'
  task :list_schemas do
    sh "xcodebuild -project #{ROOT}/ios/Tribune/Tribune.xcodeproj -list"
  end

  desc 'Build the iOS app for the simulator'
  task :build do
    sh "xcodebuild -project #{ROOT}/ios/Tribune/Tribune.xcodeproj " \
       '-scheme Tribune ' \
       "-destination 'generic/platform=iOS Simulator' " \
       '-configuration Debug ' \
       'build'
  end

  # `xcodebuild test` needs a concrete, bootable simulator (unlike :build's
  # generic destination). override the device with SIMULATOR=... if the default
  # isn't installed (`xcrun simctl list devices available` to see options).
  desc 'Run the iOS unit tests (override the sim with SIMULATOR=...)'
  task :test do
    simulator = ENV.fetch('SIMULATOR', SIMULATOR)
    sh "xcodebuild test -project #{ROOT}/ios/Tribune/Tribune.xcodeproj " \
       '-scheme Tribune ' \
       "-destination 'platform=iOS Simulator,name=#{simulator}' " \
       '-only-testing:TribuneTests'
  end

  # UI tests launch the app in the simulator and drive it, so they're slower
  # than the unit tests and kept as a separate task.
  desc 'Run the iOS UI tests (override the sim with SIMULATOR=...)'
  task :uitest do
    simulator = ENV.fetch('SIMULATOR', SIMULATOR)
    sh "xcodebuild test -project #{ROOT}/ios/Tribune/Tribune.xcodeproj " \
       '-scheme Tribune ' \
       "-destination 'platform=iOS Simulator,name=#{simulator}' " \
       '-only-testing:TribuneUITests'
  end

  # archive the app and upload it to testflight (internal testers). runs on the
  # host, not in a container (no xcode in the build image), same as :build.
  #
  # requires an app store connect api key. generate one at
  # appstoreconnect.apple.com -> users and access -> integrations -> app store
  # connect api, drop the .p8 at
  # ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8, and export the ids:
  #   ASC_KEY_ID=... ASC_ISSUER_ID=... rake ios:testflight
  desc 'Archive the iOS app and upload to testflight (internal testers)'
  task :testflight do
    key_id    = ENV['ASC_KEY_ID'].to_s
    issuer_id = ENV['ASC_ISSUER_ID'].to_s
    abort 'set ASC_KEY_ID and ASC_ISSUER_ID in the environment first' if key_id.empty? || issuer_id.empty?

    archive = "#{ROOT}/ios/build/Tribune.xcarchive"
    export  = "#{ROOT}/ios/build/export"
    opts    = "#{ROOT}/ios/ExportOptions.plist"

    # unlock the login keychain so codesign can read the signing key
    # (otherwise the archive fails with errSecInternalComponent)
    pw = $stdin.getpass('login keychain password: ')
    sh 'security', 'unlock-keychain', '-p', pw,
       "#{Dir.home}/Library/Keychains/login.keychain-db", verbose: false

    # derive a fresh build number from the unix timestamp so testflight accepts
    # a new upload. passed as a build-setting override so the pbxproj is never
    # mutated (no git diff), and unique per run even between commits.
    build_no = Time.now.to_i

    sh 'xcodebuild archive ' \
       "-project #{ROOT}/ios/Tribune/Tribune.xcodeproj " \
       '-scheme Tribune -configuration Release ' \
       "-destination 'generic/platform=iOS' " \
       "-archivePath #{archive} " \
       "CURRENT_PROJECT_VERSION=#{build_no} " \
       '-allowProvisioningUpdates'

    sh 'xcodebuild -exportArchive ' \
       "-archivePath #{archive} " \
       "-exportPath #{export} " \
       "-exportOptionsPlist #{opts} " \
       '-allowProvisioningUpdates'

    sh "xcrun altool --upload-app -f #{export}/Tribune.ipa --type ios " \
       "--apiKey #{key_id} --apiIssuer #{issuer_id}"
  end
end

namespace :koreader do
  desc 'Run the KOReader plugin tests'
  task :test do
    command.run('luajit koreader/tests/tribune_test.lua')
  end

  desc 'Install the KOReader plugin into KOReader\'s data directory (COPY=1 to copy instead of symlink)'
  task :install do
    pastel = Pastel.new
    source = File.join(ROOT, 'koreader', 'tribune.koplugin')
    data_dir = koreader_data_dir

    plugins_dir = File.join(data_dir, 'plugins')
    FileUtils.mkdir_p(plugins_dir)
    dest = File.join(plugins_dir, 'tribune.koplugin')

    # clear the previous install first, or a symlink onto an existing directory
    # nests inside it. this only ever touches the plugin's own destination, and
    # rm_rf on a symlink removes the link rather than what it points at.
    FileUtils.rm_rf(dest) if File.symlink?(dest) || File.exist?(dest)

    if ENV['COPY'].to_s.empty?
      FileUtils.ln_s(source, dest)
      puts pastel.green("symlinked #{dest} -> #{source}")
    else
      FileUtils.cp_r(source, dest)
      puts pastel.green("copied #{source} to #{dest}")
    end

    puts 'restart koreader to pick it up.'
  end

  desc 'Launch KOReader on macOS and stream verbose logs to the terminal'
  task :run do
    abort 'koreader:run is only available on macOS' unless RUBY_PLATFORM.include?('darwin')

    launcher = '/Applications/KOReader.app/Contents/MacOS/koreader'
    abort "KOReader is not installed at #{launcher}" unless File.executable?(launcher)

    exec launcher, '-d', '-v'
  end

  desc 'Install the KOReader plugin on an android tablet over adb (ADB_DEVICE=<host:port> to skip the prompts)'
  task :android do
    pastel = Pastel.new
    # the probes are noise, so run them silently and let the pair/connect/push
    # commands the user cares about print themselves through the shared runner
    quiet = TTY::Command.new(printer: :null)

    adb = adb_binary
    abort pastel.red('adb not found. install the android platform-tools, or set ADB to the binary.') if adb.nil?

    serial = adb_ready_device(quiet, adb)

    if serial.nil?
      # a tablet paired earlier only needs connecting again, and the connect
      # port changes whenever wireless debugging is toggled off and on
      address = ENV['ADB_DEVICE'].to_s
      if address.empty?
        puts pastel.yellow('no device is connected. on the tablet:')
        puts '  settings > about tablet > tap "build number" seven times to unlock developer options'
        puts '  settings > system > developer options > wireless debugging > on'
        puts
        puts 'to pair for the first time, open "pair device with pairing code" there. it shows an'
        puts 'ip:port and a six digit code. the pairing port is not the port on the wireless'
        puts 'debugging screen itself, which is the one to connect to afterwards.'
        puts

        pairing = prompt('pairing ip:port (blank if this tablet is already paired): ')
        unless pairing.empty?
          code = prompt('pairing code: ')
          command.run("#{adb.shellescape} pair #{pairing.shellescape} #{code.shellescape}")
        end

        address = prompt('connect ip:port (from the wireless debugging screen): ')
        abort pastel.red('no address given.') if address.empty?
      end

      command.run("#{adb.shellescape} connect #{address.shellescape}")
      serial = adb_ready_device(quiet, adb)
    end

    if serial.nil?
      states = adb_devices(quiet, adb).map { |device, state| "#{device} (#{state})" }
      abort pastel.red("no usable device. adb sees: #{states.empty? ? 'nothing' : states.join(', ')}")
    end

    source = File.join(ROOT, 'koreader', 'tribune.koplugin')
    # koreader keeps its data in /sdcard/koreader on android unless it was sent
    # elsewhere on first run, in which case help > about names the real path
    data_dir = ENV.fetch('ANDROID_KO_HOME', '/sdcard/koreader')
    dest = "#{data_dir}/plugins/tribune.koplugin"

    puts pastel.green("pushing to #{serial}:#{dest}")

    # clear the previous install first: pushing a directory onto one that already
    # exists nests it inside rather than replacing it, and files dropped from the
    # plugin since the last push would otherwise stay behind
    command.run("#{adb.shellescape} -s #{serial.shellescape} shell rm -rf #{dest.shellescape}")
    command.run("#{adb.shellescape} -s #{serial.shellescape} shell mkdir -p #{"#{data_dir}/plugins".shellescape}")
    command.run("#{adb.shellescape} -s #{serial.shellescape} push #{source.shellescape} #{dest.shellescape}")

    puts 'force stop koreader and open it again to pick it up.'
    puts pastel.green("next time: ADB_DEVICE=#{serial} rake koreader:android")
  end

  desc 'Install the KOReader plugin on a jailbroken kindle over ssh (KINDLE_HOST=<host> to skip the prompt)'
  task :kindle do
    pastel = Pastel.new

    host = ENV['KINDLE_HOST'].to_s
    if host.empty?
      host = prompt('kindle hostname or ip: ')
      abort pastel.red('no host given.') if host.empty?
    end

    user = ENV.fetch('KINDLE_USER', 'root')
    target = "#{user}@#{host}"

    source = File.join(ROOT, 'koreader', 'tribune.koplugin')
    data_dir = ENV.fetch('KINDLE_KO_HOME', '/mnt/us/koreader')
    plugins_dir = "#{data_dir}/plugins"
    dest = "#{plugins_dir}/tribune.koplugin"

    puts pastel.green("pushing to #{target}:#{dest}")

    # ssh goes through sh rather than the tty-command runner so that a password
    # prompt or a host key confirmation reaches the terminal
    #
    # clear the previous install first: unpacking over a directory that already
    # exists leaves files dropped from the plugin since the last copy behind
    sh "ssh #{target.shellescape} #{"rm -rf #{dest.shellescape} && mkdir -p #{plugins_dir.shellescape}".shellescape}"

    # the copy goes over a tar pipe rather than scp or rsync: a jailbroken kindle
    # has neither, only the busybox tar, and its dropbear has no sftp server for
    # openssh 9 to fall back on either
    #
    # COPYFILE_DISABLE keeps bsdtar on macos from shipping ._ appledouble files
    sh "COPYFILE_DISABLE=1 tar -cf - -C #{File.dirname(source).shellescape} " \
       "#{File.basename(source).shellescape} | " \
       "ssh #{target.shellescape} #{"tar -xf - -C #{plugins_dir.shellescape}".shellescape}"

    puts 'exit koreader and start it again to pick it up.'
    puts pastel.green("next time: KINDLE_HOST=#{host} rake koreader:kindle")
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

    # the glyph is black, so it disappears against a dark tab bar. these are the
    # same icon in white, swapped in at runtime by the script in index.html
    recolor_logo(command, 'logos/logo-web.png', '#ffffff', '32x32', 'web/public/favicon/favicon-dark-32x32.png')
    recolor_logo(command, 'logos/logo-web.png', '#ffffff', '16x16', 'web/public/favicon/favicon-dark-16x16.png')
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

  # notion wants a flat, single-colour icon on a transparent background
  desc 'Build a grey, transparent notion emoji from logos/logo-web.png'
  task :notion do
    recolor_logo(command, 'logos/logo-web.png', '#808080', '512x512', 'logos/logo-notion-gray.png')
  end
end
