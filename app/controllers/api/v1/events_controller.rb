module Api
  module V1
    # Events for the public Events page. Anyone can list published and cancelled events and read one;
    # listing drafts (?status=all), creating, editing and deleting needs manage_events.
    class EventsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!, except: %i[index show]
      before_action -> { authorize!(:manage_events) }, except: %i[index show]
      before_action :authorize_all_statuses!, only: :index, if: -> { params[:status] == 'all' }
      before_action :set_event, only: %i[update destroy]

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the event details under an "event" key' }, status: :bad_request
      end

      # Storage failures while uploading the cover photo (e.g. Cloudinary rejects the credentials).
      rescue_from ActiveStorage::Error do |error|
        logger.error("Event cover upload failed: #{error.class}: #{error.message}")
        render json: { error: "The photo couldn't be saved to storage. Please try again." }, status: :bad_gateway
      end

      # GET /api/v1/events?when=upcoming|past|all   published and cancelled events (upcoming by default)
      # GET /api/v1/events?status=all&when=...       drafts too (manage_events)
      def index
        events = Event.with_attached_cover_image.includes(:created_by).happening(params[:when])
        events = events.visible unless params[:status] == 'all'
        render json: events.map { |event| serialize(event) }
      end

      # GET /api/v1/events/:id
      # A draft is shown only to users who can manage events.
      def show
        event = Event.find_by(id: params[:id])
        event = nil if event&.draft? && !current_user&.has_permission?(:manage_events)
        return render json: { error: 'Event not found' }, status: :not_found unless event

        render json: serialize(event)
      end

      # POST /api/v1/events (multipart form data or JSON)
      def create
        event = Event.new(event_params.merge(created_by: current_user))

        if event.save_with_uploads
          render json: { message: 'Event created', event: serialize(event.reload) }, status: :created
        else
          render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/events/:id
      # Only the keys sent are changed. remove_cover_image=true deletes the cover (unless a new one is sent).
      def update
        @event.assign_attributes(event_params)
        @event.cover_image = nil if remove_cover_image? && !event_params.key?(:cover_image)

        if @event.save_with_uploads
          render json: { message: 'Event updated', event: serialize(@event.reload) }
        else
          render json: { errors: @event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/events/:id
      # Also deletes its registrations and its cover photo from storage.
      def destroy
        @event.destroy!
        render json: { message: 'Event deleted', id: @event.id }
      end

      private

      def authorize_all_statuses!
        authenticate_user!
        authorize!(:manage_events)
      end

      def set_event
        @event = Event.find_by(id: params[:id])
        render json: { error: 'Event not found' }, status: :not_found unless @event
      end

      # Only an uploaded file is accepted as the cover (not a string such as a signed blob id).
      # Form data has no null, so blank values become nil in the model (and in Active Record's type casting).
      def event_params
        @event_params ||= begin
          permitted = params.require(:event).permit(
            :title, :category, :status, :featured, :date, :end_date, :start_time, :end_time, :location, :speaker,
            :speaker_role, :audience, :description, :registration, :registration_url, :capacity, :cover_image
          )
          permitted.delete(:cover_image) unless permitted[:cover_image].is_a?(ActionDispatch::Http::UploadedFile)
          permitted
        end
      end

      def remove_cover_image?
        ActiveModel::Type::Boolean.new.cast(params.require(:event)[:remove_cover_image]) == true
      end

      def serialize(event)
        EventSerializer.new(event).as_json
      end
    end
  end
end
