# frozen_string_literal: true

require 'yaml'

Config = Struct.new(:database_host, :database_port, :database_username, :database_password, :database_name, :test_database_name,
                    :server_environment, :server_port, :server_bind, :server_secret, :server_accel, :newsletters_dir, :full_text_rss_api_key,
                    keyword_init: true) do
  def self.load
    config_dir = File.expand_path("#{__dir__}/../")
    config_path = File.join(config_dir, 'config.yaml')
    begin
      new(YAML.safe_load(File.open(config_path)))
    rescue ArgumentError => e
      puts "Could not parse config: #{e.message}"
      exit
    end
  end
end
