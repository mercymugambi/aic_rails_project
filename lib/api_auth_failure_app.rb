# Devise runs this when a request isn't authenticated (no token, or an expired or revoked one).
#
# Requests to the JSON API always get a 401 with a JSON body, whatever their Accept header says. The
# frontend's axios sends "Accept: application/json, text/plain, */*", which Rails reads as a browser asking
# for HTML, so the default failure app would redirect (302) to the home page and the frontend would never
# see the 401 that signs an expired session out. Other paths (Devise's HTML password pages) keep the
# default behaviour.
class ApiAuthFailureApp < Devise::FailureApp
  def respond
    return super unless api_request?

    warden_options[:recall] ? recall_as_unauthorized : unauthorized_json
  end

  private

  # Warden rewrites the path to /unauthenticated before calling this, so check the path that was requested.
  def api_request?
    attempted_path.to_s.start_with?('/api/')
  end

  # A failed login: the login controller renders its own JSON error. Keep it, but answer 401 rather than
  # Devise's 422.
  def recall_as_unauthorized
    recall
    response[0] = 401
  end

  def unauthorized_json
    self.status = 401
    self.content_type = 'application/json'
    self.response_body = { error: i18n_message }.to_json
  end
end
