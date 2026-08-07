class ApplicationController < ActionController::Base
  before_action :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_up, keys: %i[firstname lastname])
  end

  # Permission-based authorization helper
  # Usage: authorize!(:manage_members)
  def authorize!(permission_name)
    return if current_user&.has_permission?(permission_name)

    render json: { error: 'You do not have permission to perform this action' }, status: :forbidden
  end
end
