module Api
  module V1
    class UsersController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action :require_super_admin!, only: %i[create update reset_password destroy]
      before_action :set_user, only: %i[show update reset_password destroy]

      # GET /api/v1/users
      def index
        users = User.includes(:member, roles: :permissions).order(:id)
        render json: users.map { |user| UserSerializer.new(user).as_json }
      end

      # GET /api/v1/users/me
      def me
        render json: UserSerializer.new(current_user).as_json
      end

      # GET /api/v1/users/:id
      def show
        render json: UserSerializer.new(@user).as_json
      end

      # POST /api/v1/users
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

      # PATCH/PUT /api/v1/users/:id
      def update
        roles = Role.where(id: role_ids).to_a
        error = update_error(roles)
        return render json: { error: error[:message] }, status: error[:status] if error

        if apply_user_updates(roles)
          render json: { message: 'User updated successfully', user: serialize(@user) }
        else
          render json: { errors: @user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # POST /api/v1/users/:id/reset_password
      def reset_password
        new_password = params[:password].to_s
        if new_password.length < 6
          return render json: { error: 'Temporary password must be at least 6 characters' },
                        status: :unprocessable_entity
        end

        @user.update!(password: new_password, must_change_password: true)
        render json: { message: "Password reset for #{@user.email}. They will be prompted to change it on login.",
                       user: serialize(@user) }
      end

      # PATCH /api/v1/users/change_password
      def change_password
        new_password = params[:password].to_s
        confirmation = params[:password_confirmation].presence || new_password
        return render_password_error('New password must be at least 6 characters') if new_password.length < 6
        return render_password_error('Passwords do not match') if new_password != confirmation

        if current_user.update(password: new_password, must_change_password: false)
          render json: { message: 'Password changed successfully', user: serialize(current_user) }
        else
          render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/users/:id
      def destroy
        if @user.super_admin? || @user.id == current_user.id
          return render json: { error: 'Cannot delete the super admin account' }, status: :forbidden
        end

        @user.destroy!
        render json: { message: 'User deleted', id: @user.id }
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
          super_admin: false,
          must_change_password: true
        }
      end

      def apply_user_updates(roles)
        User.transaction do
          attrs = {
            firstname: params.key?(:firstname) ? params[:firstname] : @user.firstname,
            lastname: params.key?(:lastname) ? params[:lastname] : @user.lastname,
            email: params.key?(:email) ? params[:email] : @user.email,
            member_id: params.key?(:member_id) ? params[:member_id].presence : @user.member_id
          }
          return false unless @user.update(attrs)

          replace_user_roles(roles) if params.key?(:role_ids)
          true
        end
      end

      def replace_user_roles(roles)
        @user.user_roles.destroy_all
        roles.each { |role| @user.user_roles.create!(role: role, assigned_by: current_user) }
      end

      def role_ids
        @role_ids ||= Array(params[:role_ids]).compact_blank.map(&:to_i).uniq
      end

      def creation_error(roles)
        if roles.size != role_ids.size
          { message: 'One or more roles do not exist', status: :unprocessable_entity }
        elsif User.exists?(email: params[:email].to_s.strip.downcase)
          { message: 'A user with this email already exists', status: :conflict }
        else
          member_link_error(params[:member_id], nil)
        end
      end

      def update_error(roles)
        if params.key?(:role_ids) && roles.size != role_ids.size
          { message: 'One or more roles do not exist', status: :unprocessable_entity }
        elsif params.key?(:member_id)
          member_link_error(params[:member_id], @user.id)
        end
      end

      def member_link_error(member_id, exclude_user_id)
        return if member_id.blank?
        return { message: 'Member not found', status: :not_found } unless Member.exists?(member_id)

        scope = User.where(member_id: member_id)
        scope = scope.where.not(id: exclude_user_id) if exclude_user_id
        { message: 'This member is already linked to another user', status: :conflict } if scope.exists?
      end

      def render_password_error(msg)
        render json: { error: msg }, status: :unprocessable_entity
      end

      def serialize(user)
        UserSerializer.new(User.includes(:member, roles: :permissions).find(user.id)).as_json
      end
    end
  end
end
