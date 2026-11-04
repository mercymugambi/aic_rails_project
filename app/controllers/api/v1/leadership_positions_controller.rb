module Api
  module V1
    class LeadershipPositionsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action -> { authorize!(:manage_leadership_positions, :manage_members, :view_reports) },
                    only: %i[index show]
      before_action -> { authorize!(:manage_leadership_positions) }, only: %i[create update destroy]
      before_action :set_position, only: %i[show update destroy]

      # GET /api/v1/leadership_positions
      def index
        positions = LeadershipPosition.includes(:members).order(:position_name, :id)
        render json: positions.map { |pos| serialize_position(pos) }
      end

      # GET /api/v1/leadership_positions/:id
      def show
        render json: serialize_position(@position)
      end

      # POST /api/v1/leadership_positions
      def create
        position = LeadershipPosition.new(position_params.merge(created_by: current_user))

        if position.save
          render json: { message: 'Leadership position created', leadership_position: serialize_position(position) },
                 status: :created
        else
          render json: { errors: position.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/leadership_positions/:id
      def update
        if @position.update(position_params)
          render json: { message: 'Leadership position updated', leadership_position: serialize_position(@position) }
        else
          render json: { errors: @position.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/leadership_positions/:id
      def destroy
        @position.members.clear
        @position.destroy!
        render json: { message: 'Leadership position deleted', id: @position.id }
      end

      private

      def set_position
        @position = LeadershipPosition.includes(:members).find_by(id: params[:id])
        render json: { error: 'Leadership position not found' }, status: :not_found unless @position
      end

      def position_params
        raw = params[:leadership_position].is_a?(ActionController::Parameters) ? params[:leadership_position] : params
        raw.permit(:position_name, :description, :position_code, :member_id)
      end

      def serialize_position(pos)
        holder = pos.members.first
        {
          id: pos.id,
          position_name: pos.position_name,
          position_code: pos.position_code,
          description: pos.description,
          member_id: holder&.id,
          holder: holder ? serialize_holder(holder) : nil,
          created_at: pos.created_at
        }
      end

      def serialize_holder(member)
        {
          id: member.id,
          first_name: member.first_name,
          middle_name: member.middle_name,
          last_name: member.last_name,
          phone_number: member.phone_number,
          email: member.email
        }
      end
    end
  end
end
