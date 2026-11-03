require 'test_helper'

# Requests as the frontend's axios sends them. Its Accept header lists */* after JSON, which Rails reads as a
# browser asking for HTML; the API must still answer 401 JSON (never a 302 redirect) so the frontend can sign
# an expired session out.
class ApiAuthenticationTest < ActionDispatch::IntegrationTest
  BROWSER_ACCEPT = 'application/json, text/plain, */*'.freeze
  SIGN_IN = 'You need to sign in or sign up before continuing.'.freeze

  setup do
    @manager = users(:settings_manager)
  end

  test 'protected endpoints answer 401 JSON without a token' do
    patch_settings
    assert_unauthorized SIGN_IN

    post '/api/v1/events', params: { event: { title: 'Prayer night' } }.to_json, headers: browser
    assert_unauthorized SIGN_IN

    get '/api/v1/events', params: { status: 'all' }, headers: browser
    assert_unauthorized SIGN_IN

    get '/api/v1/users/me', headers: browser
    assert_unauthorized SIGN_IN

    delete "/api/v1/events/#{events(:youth_camp).id}", headers: browser
    assert_unauthorized SIGN_IN
    assert Event.exists?(events(:youth_camp).id)
  end

  test 'an expired token gets 401 JSON' do
    token = auth_headers(@manager)['Authorization']

    travel 25.hours do
      patch_settings(token)
      assert_unauthorized
      post '/api/v1/events', params: { event: { title: 'Prayer night' } }.to_json,
                             headers: browser('Authorization' => token)
      assert_unauthorized
    end
  end

  test 'a revoked token gets 401 JSON' do
    token = auth_headers(@manager)['Authorization']
    @manager.update!(jti: SecureRandom.uuid) # what logging out does

    patch_settings(token)
    assert_unauthorized
    post '/api/v1/events', params: { event: { title: 'Prayer night' } }.to_json,
                           headers: browser('Authorization' => token)
    assert_unauthorized
  end

  test 'a valid token still works with the browser-style Accept header' do
    patch_settings(auth_headers(@manager)['Authorization'])
    assert_response :ok
  end

  test 'a wrong password gets 401 with the login error, whatever the Accept header' do
    [browser, { 'Content-Type' => 'application/json', 'Accept' => 'application/json' }].each do |headers|
      post '/api/v1/auth/login', params: { user: { email: @manager.email, password: 'wrong' } }.to_json,
                                 headers: headers

      assert_response :unauthorized, headers['Accept']
      assert_equal({ 'error' => 'Invalid email or password.' }, response.parsed_body)
      assert_nil response.headers['Authorization']
    end
  end

  test 'a correct password still logs in' do
    post '/api/v1/auth/login', params: { user: { email: @manager.email, password: 'password123' } }.to_json,
                               headers: browser

    assert_response :ok
    assert_match(/\ABearer /, response.headers['Authorization'])
  end

  test 'paths outside /api keep Devise’s default redirect for browsers' do
    env = Rack::MockRequest.env_for('/unauthenticated', 'HTTP_ACCEPT' => 'text/html')
    env['warden.options'] = { scope: :user, attempted_path: '/users/password/edit' }
    env['rack.session'] = ActionController::TestSession.new # stores where to return after login
    env['warden'] = Struct.new(:message).new(nil) # what warden would pass: no specific failure message

    status, headers, = ApiAuthFailureApp.call(env)

    assert_equal 302, status
    assert headers['Location'].present?
  end

  private

  def browser(extra = {})
    { 'Accept' => BROWSER_ACCEPT, 'Content-Type' => 'application/json' }.merge(extra)
  end

  def patch_settings(token = nil)
    headers = token ? browser('Authorization' => token) : browser
    patch '/api/v1/site_settings', params: { site_settings: { notice: { enabled: false } } }.to_json, headers: headers
  end

  def assert_unauthorized(message = nil)
    assert_response :unauthorized
    assert_equal 'application/json', response.media_type
    error = response.parsed_body['error']
    assert error.present?, 'expected a JSON error'
    assert_equal message, error if message
  end
end
