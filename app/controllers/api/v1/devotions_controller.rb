module Api
  module V1
    class DevotionsController < ApplicationController
      def index
        @devotions = Devotion.all
        render json: @devotions
      end

      def create
        @devotions = Devotion.new(devotions_params)
        @devotions.created_by = current_user.id

        if @devotions.save
          redirect_to @devotions, notice: 'Devotion was successfully created.'
        else
          render :new
        end
      end

      private

      def devotions_params
        params.require(:devotions).permit(:title, :content, :description)
      end
    end
  end
end
