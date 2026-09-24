class ApplicationController < ActionController::Base
  protected

  # Permission-based authorization helper. Passes when the user has any of the given permissions.
  # Usage: before_action -> { authorize!(:manage_members) }
  #        before_action -> { authorize!(:manage_members, :manage_fellowship_groups) }
  def authorize!(*permission_names)
    return if permission_names.any? { |name| current_user&.has_permission?(name) }

    render json: { error: 'You do not have permission to perform this action' }, status: :forbidden
  end

  # Restricts an action to the super admin (users.super_admin = true).
  def require_super_admin!
    return if current_user&.super_admin?

    render json: { error: 'Only the super admin can perform this action' }, status: :forbidden
  end
end
