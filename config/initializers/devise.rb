Devise.setup do |config|
  config.navigational_formats = ['*/*', :html, :turbo_stream]
  config.mailer_sender = 'please-change-me-at-config-initializers-devise@example.com'
  # config.mailer_sender = 'mercymugambi2016@gmail.com'

  require 'devise/orm/active_record'
  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.skip_session_storage = [:http_auth]

  config.stretches = Rails.env.test? ? 1 : 12

  # configured to send confirmation to emails
  # config.confirmation_keys = [:email]
  # config.reconfirmable = true


  config.reconfirmable = true
  config.expire_all_remember_me_on_sign_out = true
  config.password_length = 6..128

  config.email_regexp = /\A[^@\s]+@[^@\s]+\z/
 
  config.reset_password_within = 6.hours

  config.sign_out_via = :delete

  config.responder.error_status = :unprocessable_entity
  config.responder.redirect_status = :see_other

  # JWT Configuration
  config.jwt do |jwt|
    jwt.secret = ENV.fetch('DEVISE_JWT_SECRET_KEY') { Rails.application.credentials.secret_key_base }
    jwt.dispatch_requests = [
      ['POST', %r{^/api/v1/auth/login$}]
    ]
    jwt.revocation_requests = [
      ['DELETE', %r{^/api/v1/auth/logout$}]
    ]
    jwt.expiration_time = 86_400 # 24 hours
  end
end
