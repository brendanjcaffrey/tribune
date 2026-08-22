# frozen_string_literal: true

require 'logger'
require 'que'
require_relative 'config'
require_relative 'db'

# entrypoint for the worker process: bundle exec que ./server/que_setup.rb
# (or rake que:work, which keeps the worker count and the pool size in sync)

QUE_WORKER_COUNT = Integer(ENV.fetch('QUE_WORKER_COUNT', 6))

# que says nothing at all without a logger, which makes a job that keeps failing
# invisible unless you go and read que_jobs.last_error yourself
Que.logger = Logger.new($stdout)

# the locker keeps one connection open for listen/notify on top of the workers
Que.connection = Db.pool(Config.load, size: QUE_WORKER_COUNT + 1)

Dir[File.join(__dir__, 'jobs', '*.rb')].each { |job| require job }

require_relative 'que_schedule'
