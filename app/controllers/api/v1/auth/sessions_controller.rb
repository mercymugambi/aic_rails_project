# app/controllers/api/v1/auth/sessions_controller.rb
module Api
  module V1
    module Auth
      class SessionsController < Devise::SessionsController
        respond_to :json
        skip_before_action :verify_authenticity_token

        private

        def respond_with(resource, _opts = {})
          if resource.persisted?
            render json: {
              message: 'Logged in successfully.',
              user: user_data(resource)
            }, status: :ok
          else
            render json: { error: 'Invalid email or password.' }, status: :unauthorized
          end
        end

        def respond_to_on_destroy
          if current_user
            render json: { message: 'Logged out successfully.' }, status: :ok
          else
            render json: { error: 'No active session.' }, status: :unauthorized
          end
        end

        def user_data(user)
          {
            id: user.id,
            email: user.email,
            firstname: user.firstname,
            lastname: user.lastname,
            super_admin: user.super_admin,
            roles: user.roles.pluck(:name),
            permissions: user.all_permissions.pluck(:name)
          }
        end
      end
    end
  end
end
