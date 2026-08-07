# app/controllers/api/v1/user_roles_controller.rb
module Api
  module V1
    class UserRolesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action :authorize_role_assignment!

      # POST /api/v1/user_roles
      def create
        role = Role.find(params[:role_id])
        user = User.find(params[:user_id])

        # Only super admin can assign church_admin role
        if role.name == 'church_admin' && !current_user.super_admin?
          return render json: { error: 'Only super admin can assign the church_admin role' }, status: :forbidden
        end

        user_role = UserRole.new(
          user: user,
          role: role,
          assigned_by: current_user
        )

        if user_role.save
          render json: {
            message: "Role '#{role.name}' assigned to #{user.email}",
            user_role: user_role.as_json(include: { role: { only: [:id, :name] }, user: { only: [:id, :email] } })
          }, status: :created
        else
          render json: { errors: user_role.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/user_roles/:id
      def destroy
        user_role = UserRole.find(params[:id])

        # Only super admin can remove church_admin role
        if user_role.role.name == 'church_admin' && !current_user.super_admin?
          return render json: { error: 'Only super admin can remove the church_admin role' }, status: :forbidden
        end

        user_role.destroy
        render json: { message: 'Role removed successfully' }, status: :ok
      end

      private

      def authorize_role_assignment!
        return if current_user.can_assign_roles?

        render json: { error: 'Not authorized to assign roles' }, status: :forbidden
      end
    end
  end
end
