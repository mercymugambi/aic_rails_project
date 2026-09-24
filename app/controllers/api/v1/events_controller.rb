module Api
  module V1
    class EventsController < ApplicationController
      def index
        @events = Event.all
        render json: @events
      end

      def create
        @events = Event.new(events_params)
        @events.created_by = current_user.id

        if @events.save
          redirect_to @events, notice: 'Event was successfully created.'
        else
          render :new
        end
      end

      private

      def events_params
        params.require(:events).permit(:title, :description, :image)
      end
    end
  end
end
