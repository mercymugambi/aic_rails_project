ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
require 'rails/test_help'

class ActiveSupport::TestCase
  # Threaded workers share one database and deadlock while loading fixtures, and Windows cannot
  # fork process workers, so tests run serially. Set PARALLEL_WORKERS=4 to opt in on Linux/macOS.
  parallelize(workers: ENV.fetch('PARALLEL_WORKERS', 1).to_i)

  # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
  fixtures :all

  # Add more helper methods to be used by all tests here...
end

require 'devise/jwt/test_helpers'

class ActionDispatch::IntegrationTest
  # Headers carrying a valid JWT for `user`, as the frontend would send after logging in.
  def auth_headers(user)
    Devise::JWT::TestHelpers.auth_headers({ 'Accept' => 'application/json' }, user)
  end
end
