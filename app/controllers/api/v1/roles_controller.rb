module Api
  module V1
    class RolesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action :authorize_role_management!, only: %i[create update destroy]
      before_action :set_role, only: %i[update destroy]

      # GET /api/v1/permissions
      def permissions
        render json: Permission.order(:id).as_json(only: %i[id name description])
      end

      # GET /api/v1/roles
      def index
        roles = Role.includes(:permissions, :users).order(:id)
        render json: roles.map { |role| serialize_role(role) }
      end

      # POST /api/v1/roles
      def create
        role = Role.new(role_params)

        if role.save
          render json: serialize_role(role), status: :created
        else
          render json: { errors: role.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/roles/:id
      def update
        if @role.update(role_params)
          render json: serialize_role(@role)
        else
          render json: { errors: @role.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/roles/:id
      def destroy
        @role.destroy!
        render json: { message: 'Role deleted', id: @role.id }
      end

      private

      def set_role
        @role = Role.includes(:permissions, :users).find_by(id: params[:id])
        render json: { error: 'Role not found' }, status: :not_found unless @role
      end

      def role_params
        raw = params[:role].is_a?(ActionController::Parameters) ? params[:role] : params
        raw.permit(:name, :description, permission_ids: [])
      end

      def serialize_role(role)
        {
          id: role.id,
          name: role.name,
          description: role.description,
          users_count: role.users.size,
          permission_ids: role.permissions.map(&:id),
          permissions: role.permissions.map { |p| { id: p.id, name: p.name, description: p.description } }
        }
      end

      def authorize_role_management!
        return if current_user.super_admin? || current_user.has_permission?('manage_roles')

        render json: { error: 'Not authorized to manage roles' }, status: :forbidden
      end
    end
  end
end
