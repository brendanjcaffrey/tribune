# frozen_string_literal: true

require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

require_relative '../server'

RSpec.describe 'Tribune Server' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before(:each) do
    DB_POOL.with { |conn| conn.exec('BEGIN') }
  end

  after(:each) do
    DB_POOL.with { |conn| conn.exec('ROLLBACK') }
  end

  before do
    allow(Config).to receive(:load).and_return(Config.new)
    allow(PG).to receive(:load).and_return(Config.new)
  end

  describe '/users' do
    it 'should return that no users exists' do
      get '/users'
      expect(last_response).to be_ok
      expect(last_response.body).to eq('{"any":false}')
    end

    it 'greets a person' do
      DB_POOL.with do |conn|
        conn.exec('INSERT INTO users (username, password_sha256) VALUES ($1, $2)', %w[testuser testpassword])
      end

      get '/users'
      expect(last_response.body).to eq('{"any":true}')
    end
  end
end
