# frozen_string_literal: true

require 'rack/test'
require 'rspec'
require 'rspec/temp_dir'

ENV['RACK_ENV'] = 'test'

require_relative '../server'

SHA256 = {
  testpassword: '9f735e0df9a1ddc702bf0a1a7b83033f9f7153a00c29de82cedadc9957289b05'
}.freeze

BASE_TIME = Time.new(2025, 1, 1, 0, 0, 0.456789).utc
HALF_MICROSECOND = Rational(1, 2_000_000)
HALF_SECOND = Rational(1, 2)
CREATE_TEST_USER_QUERY = 'INSERT INTO users (username, password_sha256) VALUES ($1, $2);'
CREATE_TEST_NEWSLETTER_QUERY = 'INSERT INTO newsletters (id, title, author, filename, read, deleted, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $6, $7, $8);'
UPDATE_TEST_NEWSLETTER_UPDATED_AT = 'UPDATE newsletters SET updated_at = $1 WHERE id = $2;'

RSpec.describe 'Tribune Server' do
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  before do
    DB_POOL.with { |conn| conn.exec('BEGIN') }
  end

  after do
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
    it 'returns that no users exists' do
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
    before do
      create_user
    end

    it 'returns 400 for no params' do
      post '/auth'
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 for missing username' do
      post '/auth', { password: 'pass' }
      expect(last_response.status).to eq(400)
    end

    it 'returns 400 for missing password' do
      post '/auth', { username: 'user' }
      expect(last_response.status).to eq(400)
    end

    it 'returns 401 for invalid credentials' do
      post '/auth', { username: 'invaliduser', password: 'invalidpassword' }
      expect(last_response.status).to eq(401)
    end

    it 'returns 401 for invalid username' do
      post '/auth', { username: 'testuserx', password: 'testpassword' }
      expect(last_response.status).to eq(401)
    end

    it 'returns 401 for invalid password' do
      post '/auth', { username: 'testuser', password: 'testpasswordx' }
      expect(last_response.status).to eq(401)
    end

    it 'returns a jwt for valid username and password' do
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
    before do
      create_user
    end

    it 'returns an error if no auth header' do
      put '/auth'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      put '/auth', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      put '/auth', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns a new token if valid jwt' do
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

  describe 'GET /newsletters' do
    before do
      create_user
    end

    it 'returns an error if no auth header' do
      get '/newsletters'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      get '/newsletters', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      get '/newsletters', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns nothing if the database is empty' do
      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok

      body = JSON.parse(last_response.body)
      expect(body).to eq('meta' => {}, 'result' => [])
    end

    it 'returns an item if it exists' do
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
      expect(item['read']).to be(false)
      expect(item['deleted']).to be(false)
      expect(Time.parse(item['created_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME + 1)
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME + 1)
    end

    it 'returns only the newest 100 items' do
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

    it 'validates after params if at least one is present' do
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

    it 'supports pagination with after' do
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

    it 'supports id tiebreakers with after' do
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

    it 'returns the item if the newest item got updated' do
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

    it 'validates before params if at least one is present' do
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

    it 'supports pagination with before' do
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

    it 'supports id tiebreakers with before' do
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

  describe 'PUT /newsletters/:id/read' do
    before do
      create_user
      create_newsletter(id: 1, updated_at: BASE_TIME)
    end

    it 'returns an error if no auth header' do
      put '/newsletters/1/read'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      put '/newsletters/1/read', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      put '/newsletters/1/read', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if non-numeric id' do
      put '/newsletters/hi/read', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if too small id' do
      put '/newsletters/0/read', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if non-existant id' do
      put '/newsletters/2/read', {}, get_auth_header
      expect(last_response.status).to eq(404)
    end

    it 'sets read to true if id exists' do
      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(false)

      put '/newsletters/1/read', {}, get_auth_header
      expect(last_response.status).to eq(200)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_SECOND).of(Time.now.utc)
      expect(item['read']).to be(true)
    end

    it 'does not change the updated_at timestamp if already read' do
      create_newsletter(id: 2, updated_at: BASE_TIME, read: true)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(true)

      put '/newsletters/2/read', {}, get_auth_header
      expect(last_response).to be_ok

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(true)
    end

    it 'returns a 404 and not change the updated_at timestamp if deleted' do
      create_newsletter(id: 2, updated_at: BASE_TIME, read: false, deleted: true)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(false)
      expect(item['deleted']).to be(true)

      put '/newsletters/2/unread', {}, get_auth_header
      expect(last_response.status).to eq(404)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(false)
      expect(item['deleted']).to be(true)
    end
  end

  describe 'PUT /newsletters/:id/unread' do
    before do
      create_user
      create_newsletter(id: 1, updated_at: BASE_TIME, read: true)
    end

    it 'returns an error if no auth header' do
      put '/newsletters/1/unread'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      put '/newsletters/1/unread', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      put '/newsletters/1/unread', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if non-numeric id' do
      put '/newsletters/hi/unread', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if too small id' do
      put '/newsletters/0/unread', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if non-existant id' do
      put '/newsletters/2/unread', {}, get_auth_header
      expect(last_response.status).to eq(404)
    end

    it 'sets read to true if id exists' do
      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(true)

      put '/newsletters/1/unread', {}, get_auth_header
      expect(last_response.status).to eq(200)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_SECOND).of(Time.now.utc)
      expect(item['read']).to be(false)
    end

    it 'does not change the changed_at timestamp if already unread' do
      create_newsletter(id: 2, updated_at: BASE_TIME, read: false)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(false)

      put '/newsletters/2/unread', {}, get_auth_header
      expect(last_response).to be_ok

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(false)
    end

    it 'returns a 404 and not change the updated_at timestamp if deleted' do
      create_newsletter(id: 2, updated_at: BASE_TIME, read: true, deleted: true)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(true)
      expect(item['deleted']).to be(true)

      put '/newsletters/2/unread', {}, get_auth_header
      expect(last_response.status).to eq(404)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['read']).to be(true)
      expect(item['deleted']).to be(true)
    end
  end

  describe 'DELETE /newsletters/:id' do
    before do
      create_user
      create_newsletter(id: 1, updated_at: BASE_TIME)
    end

    it 'returns an error if no auth header' do
      delete '/newsletters/1'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      delete '/newsletters/1', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      delete '/newsletters/1', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if non-numeric id' do
      delete '/newsletters/hi', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if too small id' do
      delete '/newsletters/0', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if non-existant id' do
      delete '/newsletters/2', {}, get_auth_header
      expect(last_response.status).to eq(404)
    end

    it 'returns a 404 and not change the updated_at timestamp if already deleted' do
      create_newsletter(id: 2, updated_at: BASE_TIME, deleted: true)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['deleted']).to be(true)

      delete '/newsletters/2', {}, get_auth_header
      expect(last_response.status).to eq(404)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['deleted']).to be(true)
    end

    it 'sets deleted to true if id exists' do
      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(item['deleted']).to be(false)

      delete '/newsletters/1', {}, get_auth_header
      expect(last_response.status).to eq(200)

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['updated_at'])).to be_within(HALF_SECOND).of(Time.now.utc)
      expect(item['deleted']).to be(true)
    end
  end

  describe 'POST /newsletters' do
    include_context 'uses temp dir'

    let(:test_file_path) do
      Tempfile.new('test_newsletter.epub').tap do |f|
        f.write('test test test')
      end
    end

    let(:file) do
      Rack::Test::UploadedFile.new(test_file_path.path, 'application/epub+zip')
    end

    let(:metadata) do
      { 'title' => 'Test Title', 'author' => 'Test Author' }
    end

    before do
      create_user
      CONFIG.newsletters_dir = temp_dir
    end

    it 'returns an error if no auth header' do
      post '/newsletters'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      post '/newsletters', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      post '/newsletters', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if there is no file' do
      post '/newsletters', {
        metadata: metadata.to_json
      }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if there is no metadata' do
      post '/newsletters', {
        file: file
      }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if metadata is not valid json' do
      post '/newsletters', {
        metadata: '{{{{',
        file: file
      }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if metadata.title is not valid' do
      metadata['title'] = nil
      post '/newsletters', {
        metadata: metadata.to_json,
        file: file
      }, get_auth_header
      expect(last_response.status).to eq(400)

      metadata['title'] = ''
      post '/newsletters', {
        metadata: metadata.to_json,
        file: file
      }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if metadata.author is not valid' do
      metadata['author'] = nil
      post '/newsletters', {
        metadata: metadata.to_json,
        file: file
      }, get_auth_header
      expect(last_response.status).to eq(400)

      metadata['author'] = ''
      post '/newsletters', {
        metadata: metadata.to_json,
        file: file
      }, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'creates a database entry and move the file into place' do
      post '/newsletters', {
        metadata: metadata.to_json,
        file: file
      }, get_auth_header
      expect(last_response).to be_ok
      expect(File).to exist(File.join(temp_dir, 'd41d8cd98f00b204e9800998ecf8427e.epub'))

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['created_at'])).to be_within(HALF_SECOND).of(Time.now)
      expect(Time.parse(item['updated_at'])).to be_within(HALF_SECOND).of(Time.now)
      expect(item['title']).to eq(metadata['title'])
      expect(item['author']).to eq(metadata['author'])
      expect(item['filename']).to eq('d41d8cd98f00b204e9800998ecf8427e.epub')
      expect(item['read']).to be(false)
      expect(item['deleted']).to be(false)
    end

    it 'creates a database entry with a creation time if specified' do
      metadata['created_at'] = BASE_TIME.iso8601(6)
      post '/newsletters', {
        metadata: metadata.to_json,
        file: file
      }, get_auth_header
      expect(last_response).to be_ok
      expect(File).to exist(File.join(temp_dir, 'd41d8cd98f00b204e9800998ecf8427e.epub'))

      get '/newsletters', {}, get_auth_header
      expect(last_response).to be_ok
      item = JSON.parse(last_response.body)['result'][0]
      expect(Time.parse(item['created_at'])).to be_within(HALF_MICROSECOND).of(BASE_TIME)
      expect(Time.parse(item['updated_at'])).to be_within(HALF_SECOND).of(Time.now)
      expect(item['title']).to eq(metadata['title'])
      expect(item['author']).to eq(metadata['author'])
      expect(item['filename']).to eq('d41d8cd98f00b204e9800998ecf8427e.epub')
      expect(item['read']).to be(false)
      expect(item['deleted']).to be(false)
    end
  end

  describe 'GET /newsletters/:id/epub' do
    include_context 'uses temp dir'

    before do
      create_user
      create_newsletter(id: 1, updated_at: BASE_TIME, read: true, filename: 'd41d8cd98f00b204e9800998ecf8427e.epub')
      CONFIG.newsletters_dir = temp_dir
    end

    it 'returns an error if no auth header' do
      get '/newsletters/1/epub'
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if expired jwt' do
      get '/newsletters/1/epub', {}, get_expired_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if invalid jwt' do
      get '/newsletters/1/epub', {}, get_invalid_auth_header
      expect(last_response.status).to eq(401)
    end

    it 'returns an error if non-numeric id' do
      get '/newsletters/hi/epub', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if too small id' do
      get '/newsletters/0/epub', {}, get_auth_header
      expect(last_response.status).to eq(400)
    end

    it 'returns an error if non-existant id' do
      get '/newsletters/2/epub', {}, get_auth_header
      expect(last_response.status).to eq(404)
    end

    it 'returns an error if the file does not exist' do
      get '/newsletters/1/epub', {}, get_auth_header
      expect(last_response.status).to eq(500)
    end

    it 'returns the file contents' do
      File.write(File.join(temp_dir, 'd41d8cd98f00b204e9800998ecf8427e.epub'), 'test test test')

      get '/newsletters/1/epub', {}, get_auth_header
      expect(last_response).to be_ok
      expect(last_response.body).to eq('test test test')
    end
  end
end
