module Api
  module V1
    module Auth
      class SessionsController < Devise::SessionsController
        respond_to :json
        skip_before_action :verify_authenticity_token, raise: false
        skip_before_action :require_no_authentication, raise: false

        private

        def respond_with(resource, _opts = {})
          if resource.persisted?
            render json: {
              message: 'Logged in successfully.',
              user: UserSerializer.new(resource).as_json
            }, status: :ok
          else
            render json: { error: 'Invalid email or password.' }, status: :unauthorized
          end
        end

        # Devise 4.9+ passes status options (e.g. non_navigational_status:); this API always responds with JSON.
        def respond_to_on_destroy(**)
          if current_user
            render json: { message: 'Logged out successfully.' }, status: :ok
          else
            render json: { error: 'No active session.' }, status: :unauthorized
          end
        end
      end
    end
  end
end
