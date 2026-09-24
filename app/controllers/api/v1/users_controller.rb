module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action :require_super_admin!, only: [:create]
      before_action :set_user, only: [:show]

      # GET /api/v1/users
      def index
        users = User.includes(:member, roles: :permissions).order(:id)
        render json: users.map { |user| UserSerializer.new(user).as_json }
      end

      # GET /api/v1/users/me
      # The logged-in user, including the permissions the frontend uses to show or hide pages.
      def me
        render json: UserSerializer.new(current_user).as_json
      end

      # GET /api/v1/users/:id
      def show
        render json: UserSerializer.new(@user).as_json
      end

      # POST /api/v1/users
      # Super admin only. Creates a login account and assigns its roles in one step:
      # if anything is invalid, neither the user nor any role assignment is saved.
      #
      # Params: email, password, firstname, lastname, role_ids (array, optional), member_id (optional)
      def create
        roles = Role.where(id: role_ids).to_a
        error = creation_error(roles)
        return render json: { error: error[:message] }, status: error[:status] if error

        user = User.new(user_params)
        roles.each { |role| user.user_roles.build(role: role, assigned_by: current_user) }

        if user.save
          render json: { message: 'User created successfully', user: serialize(user) }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_user
        @user = User.includes(:member, roles: :permissions).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'User not found' }, status: :not_found
      end

      def user_params
        {
          email: params[:email],
          password: params[:password],
          firstname: params[:firstname],
          lastname: params[:lastname],
          member_id: params[:member_id].presence,
          super_admin: false
        }
      end

      def role_ids
        @role_ids ||= Array(params[:role_ids]).compact_blank.map(&:to_i).uniq
      end

      # Checks that need a specific status code; field validation is left to the model (422).
      def creation_error(roles)
        if roles.size != role_ids.size
          { message: 'One or more roles do not exist', status: :unprocessable_entity }
        elsif User.exists?(email: params[:email].to_s.strip.downcase)
          { message: 'A user with this email already exists', status: :conflict }
        elsif params[:member_id].present? && !Member.exists?(params[:member_id])
          { message: 'Member not found', status: :not_found }
        elsif params[:member_id].present? && User.exists?(member_id: params[:member_id])
          { message: 'This member is already linked to a user', status: :conflict }
        end
      end

      def serialize(user)
        UserSerializer.new(User.includes(:member, roles: :permissions).find(user.id)).as_json
      end
    end
  end
end
