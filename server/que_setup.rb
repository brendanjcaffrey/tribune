# frozen_string_literal: true

require 'que'
require_relative 'config'
require_relative 'db'

# entrypoint for the worker process: bundle exec que ./server/que_setup.rb
# (or rake que:work, which keeps the worker count and the pool size in sync)

QUE_WORKER_COUNT = Integer(ENV.fetch('QUE_WORKER_COUNT', 6))

# the locker keeps one connection open for listen/notify on top of the workers
Que.connection = Db.pool(Config.load, size: QUE_WORKER_COUNT + 1)

Dir[File.join(__dir__, 'jobs', '*.rb')].each { |job| require job }
