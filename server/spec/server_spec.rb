# frozen_string_literal: true

require 'rack/test'
require 'rspec'

ENV['RACK_ENV'] = 'test'

require_relative '../server'

SHA256 = {
  testpassword: '9f735e0df9a1ddc702bf0a1a7b83033f9f7153a00c29de82cedadc9957289b05'
}.freeze

BASE_TIME = Time.new(2025, 1, 1, 0, 0, 0.456789).utc
HALF_MICROSECOND = Rational(1, 2_000_000)
CREATE_TEST_USER_QUERY = 'INSERT INTO users (username, password_sha256) VALUES ($1, $2);'
CREATE_TEST_NEWSLETTER_QUERY = 'INSERT INTO newsletters (id, title, author, filename, read, deleted, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);'
UPDATE_TEST_NEWSLETTER_UPDATED_AT = 'UPDATE newsletters SET updated_at = $1 WHERE id = $2;'

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

  # users
  def create_user(username = 'testuser', password_sha256 = SHA256[:testpassword])
    DB_POOL.with do |conn|
      conn.exec(CREATE_TEST_USER_QUERY, [username, password_sha256])
    end
  end

  # auth
  def get_auth_header(username = 'testuser')
    { 'HTTP_AUTHORIZATION' => "Bearer #{build_jwt(username, CONFIG.secret, 5)}" }
  end

  def get_expired_auth_header(username = 'testuser')
    { 'HTTP_AUTHORIZATION' => "Bearer #{build_jwt(username, CONFIG.secret, -5)}" }
  end

  def get_invalid_auth_header
    { 'HTTP_AUTHORIZATION' => 'Bearer blah' }
  end

  # newsletters
  def create_newsletter(id:, title: nil, author: nil, filename: nil, read: false, deleted: false, created_at: nil, updated_at: nil)
    title ||= "t#{id}"
    author ||= "a#{id}"
    filename ||= "f#{id}"
    created_at ||= BASE_TIME + id
    updated_at ||= BASE_TIME + id
    DB_POOL.with do |conn|
      conn.exec(CREATE_TEST_NEWSLETTER_QUERY, [id, title, author, filename, read, deleted, created_at.iso8601(6), updated_at.iso8601(6)])
    end
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

  describe 'GET /newsletter' do
    before(:each) do
      create_user
    end

    it 'should return an error if no auth header' do
      get '/newsletters'
      expect(last_response.status).to eq(401)
    end

    it 'should return false if expired jwt' do
      get '/newsletters', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'should return false if invalid jwt' do
      get '/newsletters', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'should return nothing if the database is empty' do
      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body).to eq('meta' => {}, 'result' => [])
    end

    it 'should return an item if it exists' do
      create_newsletter(id: 1)
      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body['meta']).to eq({})
      expect(body['result'].size).to eq(1)

      item = body['result'][0]
      expect(item['id']).to eq(1)
      expect(item['title']).to eq('t1')
      expect(item['author']).to eq('a1')
      expect(item['filename']).to eq('f1')
      expect(item['read']).to eq(false)
      expect(item['deleted']).to eq(false)
      expect(Time.parse(item['created_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME + 1)
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME + 1)
    end

    it 'should return only the newest 100 items' do
      105.times do |i|
        create_newsletter(id: i + 1)
      end

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']).to eq({})
      expect(body['result'].size).to eq(100)
      expect(body['result'].map { _1['id'] }).to eq((6..105).to_a.reverse)
    end

    it 'should validate after params if at least one is present' do
      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6) }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { after_id: 1 }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { after_timestamp: '', after_id: 1 }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: '' }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: '0' }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: 0 }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'should support pagination with after' do
      5.times do |i|
        create_newsletter(id: i + 1)
      end

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: 1 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq(BASE_TIME.iso8601(6))
      expect(body['meta']['after_id']).to eq(1)
      expect(body['result'].size).to eq(5)

      get '/newsletters', { after_timestamp: (BASE_TIME + 0.99).iso8601(6), after_id: 1 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 0.99).iso8601(6))
      expect(body['meta']['after_id']).to eq(1)
      expect(body['result'].size).to eq(5)

      get '/newsletters', { after_timestamp: (BASE_TIME + 1).iso8601(6), after_id: 1 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 1).iso8601(6))
      expect(body['meta']['after_id']).to eq(1)
      expect(body['result'].size).to eq(4)

      get '/newsletters', { after_timestamp: (BASE_TIME + 2).iso8601(6), after_id: 2 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 2).iso8601(6))
      expect(body['meta']['after_id']).to eq(2)
      expect(body['result'].size).to eq(3)

      get '/newsletters', { after_timestamp: (BASE_TIME + 3).iso8601(6), after_id: 3 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 3).iso8601(6))
      expect(body['meta']['after_id']).to eq(3)
      expect(body['result'].size).to eq(2)

      get '/newsletters', { after_timestamp: (BASE_TIME + 4).iso8601(6), after_id: 4 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 4).iso8601(6))
      expect(body['meta']['after_id']).to eq(4)
      expect(body['result'].size).to eq(1)

      get '/newsletters', { after_timestamp: (BASE_TIME + 4.99).iso8601(6), after_id: 4 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 4.99).iso8601(6))
      expect(body['meta']['after_id']).to eq(4)
      expect(body['result'].size).to eq(1)

      get '/newsletters', { after_timestamp: (BASE_TIME + 5).iso8601(6), after_id: 5 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq((BASE_TIME + 5).iso8601(6))
      expect(body['meta']['after_id']).to eq(5)
      expect(body['result'].size).to eq(0)
    end

    it 'should support id tiebreakers with after' do
      100.times do |i|
        create_newsletter(id: i + 1, updated_at: BASE_TIME)
      end

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']).to eq({})
      expect(body['result'].map { _1['id'] }).to eq((1..100).to_a.reverse)

      5.times do |i|
        create_newsletter(id: i + 101, updated_at: BASE_TIME)
      end

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: 100 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq(BASE_TIME.iso8601(6))
      expect(body['meta']['after_id']).to eq(100)
      expect(body['result'].map { _1['id'] }).to eq((101..105).to_a.reverse)
    end

    it 'should return the item if the newest item got updated' do
      create_newsletter(id: 1, updated_at: BASE_TIME)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']).to eq({})
      expect(body['result'].size).to eq(1)

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: 1 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq(BASE_TIME.iso8601(6))
      expect(body['meta']['after_id']).to eq(1)
      expect(body['result'].size).to eq(0)

      DB_POOL.with do |conn|
        conn.exec_params(UPDATE_TEST_NEWSLETTER_UPDATED_AT, [(BASE_TIME + 0.1).iso8601(6), 1])
      end

      get '/newsletters', { after_timestamp: BASE_TIME.iso8601(6), after_id: 1 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['after_timestamp']).to eq(BASE_TIME.iso8601(6))
      expect(body['meta']['after_id']).to eq(1)
      expect(body['result'].size).to eq(1)
    end

    it 'should validate before params if at least one is present' do
      get '/newsletters', { before_timestamp: BASE_TIME.iso8601(6) }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { before_id: 1 }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { before_timestamp: '', before_id: 1 }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { before_timestamp: BASE_TIME.iso8601(6), before_id: '' }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { before_timestamp: BASE_TIME.iso8601(6), before_id: '0' }, get_auth_header
      expect(last_response.status).to eq(400)

      get '/newsletters', { before_timestamp: BASE_TIME.iso8601(6), before_id: 0 }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'should support pagination with before' do
      5.times do |i|
        create_newsletter(id: i + 1)
      end

      get '/newsletters', { before_timestamp: (BASE_TIME + 6).iso8601(6), before_id: 6 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq((BASE_TIME + 6).iso8601(6))
      expect(body['meta']['before_id']).to eq(6)
      expect(body['result'].size).to eq(5)

      get '/newsletters', { before_timestamp: (BASE_TIME + 5).iso8601(6), before_id: 5 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq((BASE_TIME + 5).iso8601(6))
      expect(body['meta']['before_id']).to eq(5)
      expect(body['result'].size).to eq(4)

      get '/newsletters', { before_timestamp: (BASE_TIME + 4).iso8601(6), before_id: 4 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq((BASE_TIME + 4).iso8601(6))
      expect(body['meta']['before_id']).to eq(4)
      expect(body['result'].size).to eq(3)

      get '/newsletters', { before_timestamp: (BASE_TIME + 3).iso8601(6), before_id: 3 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq((BASE_TIME + 3).iso8601(6))
      expect(body['meta']['before_id']).to eq(3)
      expect(body['result'].size).to eq(2)

      get '/newsletters', { before_timestamp: (BASE_TIME + 2).iso8601(6), before_id: 2 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq((BASE_TIME + 2).iso8601(6))
      expect(body['meta']['before_id']).to eq(2)
      expect(body['result'].size).to eq(1)

      get '/newsletters', { before_timestamp: (BASE_TIME + 1).iso8601(6), before_id: 1 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq((BASE_TIME + 1).iso8601(6))
      expect(body['meta']['before_id']).to eq(1)
      expect(body['result'].size).to eq(0)
    end

    it 'should support id tiebreakers with before' do
      105.times do |i|
        create_newsletter(id: i + 1, updated_at: BASE_TIME)
      end

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']).to eq({})
      expect(body['result'].map { _1['id'] }).to eq((6..105).to_a.reverse)

      get '/newsletters', { before_timestamp: BASE_TIME.iso8601(6), before_id: 6 }, get_auth_header
      expect(last_response).to be_ok
      body = JSON.parse(last_response.body)
      expect(body['meta']['before_timestamp']).to eq(BASE_TIME.iso8601(6))
      expect(body['meta']['before_id']).to eq(6)
      expect(body['result'].map { _1['id'] }).to eq((1..5).to_a.reverse)
    end
  end
end
