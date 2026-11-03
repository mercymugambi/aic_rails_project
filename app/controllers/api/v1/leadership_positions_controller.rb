module Api
  module V1
    class LeadershipPositionsController < ApplicationController
      def index
        @position = LeadershipPosition.all
        render json: @position
      end

      def create
        @position = LeadershipPosition.new(position_params)
        @position.created_by = current_user.id

        if @position.save
          redirect_to @position, notice: 'Leadership position was successfully created.'
        else
          render :new
        end
      end

      private

      def position_params
        params.require(:leadership_position).permit(:position_name, :description, :position_code)
      end
    end
  end
end
