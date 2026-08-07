# app/controllers/api/v1/users_controller.rb
module Api
  module V1
    class UsersController < ApplicationController
      before_action :authenticate_user!
      before_action :authorize_user_management!, only: [:create]
      before_action :set_user, only: [:show]

      # GET /api/v1/users
      def index
        @users = User.includes(:roles, :member).all
        render json: @users.map { |u| user_data(u) }
      end

      # GET /api/v1/users/:id
      def show
        render json: user_data(@user)
      end

      # POST /api/v1/users
      def create
        required_member = Member.joins(:leadership_positions).find_by(id: params[:member_id])

        unless required_member
          return render json: { error: 'Member with a leadership position not found' }, status: :not_found
        end

        if User.exists?(email: params[:email])
          return render json: { error: 'A user with this email already exists' }, status: :conflict
        end

        user = User.new(
          email: params[:email],
          password: params[:password],
          firstname: params[:firstname],
          lastname: params[:lastname],
          member_id: required_member.id,
          super_admin: false
        )

        if user.save
          render json: { message: 'User created successfully', user: user_data(user) }, status: :created
        else
          render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def set_user
        @user = User.includes(:roles, :member).find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'User not found' }, status: :not_found
      end

      def authorize_user_management!
        return if current_user.has_permission?(:manage_users) || current_user.super_admin?

        render json: { error: 'Not authorized to manage users' }, status: :forbidden
      end

      def user_data(user)
        {
          id: user.id,
          email: user.email,
          firstname: user.firstname,
          lastname: user.lastname,
          super_admin: user.super_admin,
          roles: user.roles.pluck(:name),
          member: user.member ? {
            id: user.member.id,
            first_name: user.member.first_name,
            last_name: user.member.last_name,
            phone_number: user.member.phone_number,
            date_of_birth: user.member.date_of_birth,
            place_of_residence: user.member.place_of_residence
          } : nil
        }
      end
    end
  end
end
