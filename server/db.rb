# frozen_string_literal: true

require 'connection_pool'
require 'pg'

# shared postgres connection setup for the web app, the que worker and rake
module Db
  module_function

  # the specs point everything at the test database via RACK_ENV
  def database_name(config)
    ENV['RACK_ENV'] == 'test' ? config.test_database_name : config.database_name
  end

  def connect(config, dbname: nil)
    PG.connect(
      dbname: dbname || database_name(config),
      user: config.database_username,
      password: config.database_password,
      host: config.database_host,
      port: config.database_port
    ).tap do |conn|
      conn.exec("SET TIME ZONE 'UTC'")
    end
  end

  def pool(config, size:, dbname: nil, timeout: 5)
    ConnectionPool.new(size: size, timeout: timeout) { connect(config, dbname: dbname) }
  end
end
