# frozen_string_literal: true

require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

require_relative '../server'

SHA256 = {
  testpassword: '9f735e0df9a1ddc702bf0a1a7b83033f9f7153a00c29de82cedadc9957289b05'
}.freeze

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

  def create_user(username = 'testuser', password_sha256 = SHA256[:testpassword])
    DB_POOL.with do |conn|
      conn.exec('INSERT INTO users (username, password_sha256) VALUES ($1, $2)', [username, password_sha256])
    end
  end

  def get_auth_header(username = 'testuser')
    { 'HTTP_AUTHORIZATION' => "Bearer #{build_jwt(username, CONFIG.secret, 5)}" }
  end

  def get_expired_auth_header(username = 'testuser')
    { 'HTTP_AUTHORIZATION' => "Bearer #{build_jwt(username, CONFIG.secret, -5)}" }
  end

  def get_invalid_auth_header
    { 'HTTP_AUTHORIZATION' => 'Bearer blah' }
  end

  describe 'GET /users' do
    it 'should return that no users exists' do
      get '/users'
      expect(last_response).to be_ok
      expect(last_response.body).to eq('{"any":false}')
    end

    it 'greets a person' do
      create_user
      get '/users'
      expect(last_response.body).to eq('{"any":true}')
    end
  end

  describe 'POST /auth' do
    before(:each) do
      create_user
    end

    it 'should return 400 for no params' do
      post '/auth'
      expect(last_response.status).to eq(400)
    end

    it 'should return 400 for missing username' do
      post '/auth', { password: 'pass' }
      expect(last_response.status).to eq(400)
    end

    it 'should return 400 for missing password' do
      post '/auth', { username: 'user' }
      expect(last_response.status).to eq(400)
    end

    it 'should return 401 for invalid credentials' do
      post '/auth', { username: 'invaliduser', password: 'invalidpassword' }
      expect(last_response.status).to eq(401)
    end

    it 'should return 401 for invalid username' do
      post '/auth', { username: 'testuserx', password: 'testpassword' }
      expect(last_response.status).to eq(401)
    end

    it 'should return 401 for invalid password' do
      post '/auth', { username: 'testuser', password: 'testpasswordx' }
      expect(last_response.status).to eq(401)
    end

    it 'should return a jwt for valid username and password' do
      post '/auth', { username: 'testuser', password: 'testpassword' }
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      values = decode_jwt(body['jwt'], CONFIG.secret)
      expect(values[0]['username']).to eq('testuser')
      expect(values[1]['alg']).to eq(JWT_ALGO)
      expect(values[1]['exp']).to be > Time.now.to_i
    end
  end

  describe 'PUT /auth' do
    before(:each) do
      create_user
    end

    it 'should return an error if no auth header' do
      put '/auth'
      expect(last_response.status).to eq(401)
    end

    it 'should return false if expired jwt' do
      put '/auth', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'should return false if invalid jwt' do
      put '/auth', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'should return a new token if valid jwt' do
      auth_header = get_auth_header
      put '/auth', {}, auth_header
      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      values = decode_jwt(body['jwt'], CONFIG.secret)
      expect(values[0]['username']).to eq('testuser')
      expect(values[1]['alg']).to eq(JWT_ALGO)
      expect(values[1]['exp']).to be > Time.now.to_i
    end
  end
end
