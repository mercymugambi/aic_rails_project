# app/controllers/api/v1/roles_controller.rb
module Api
  module V1
    class RolesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action :authorize_role_management!, only: [:create]

      # GET /api/v1/roles
      def index
        @roles = Role.includes(:permissions).all
        render json: @roles.as_json(include: { permissions: { only: [:id, :name, :description] } })
      end

      # POST /api/v1/roles
      def create
        @role = Role.new(role_params)

        if @role.save
          render json: @role, status: :created
        else
          render json: { errors: @role.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def role_params
        params.require(:role).permit(:name, :description, permission_ids: [])
      end

      def authorize_role_management!
        return if current_user.super_admin? || current_user.church_admin?

        render json: { error: 'Not authorized to manage roles' }, status: :forbidden
      end
    end
  end
end
