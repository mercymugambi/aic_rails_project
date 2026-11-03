module Api
  module V1
    # RSVPs for events that take sign-ups on the website. Anyone can sign up; seeing the list and removing
    # someone needs manage_events. Names and contact details are never shown publicly.
    class EventRegistrationsController < ApplicationController
      # Sign-ups allowed from one IP address per window, counted in Rails.cache (off with a null store).
      RSVP_LIMIT = 5
      RSVP_WINDOW = 10.minutes

      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!, except: :create
      before_action -> { authorize!(:manage_events) }, except: :create
      before_action :throttle_sign_ups!, only: :create
      before_action :set_event

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the registration details under a "registration" key' }, status: :bad_request
      end

      # GET /api/v1/events/:event_id/registrations (oldest first)
      def index
        registrations = @event.registrations.order(:created_at, :id)
        render json: registrations.map { |registration| serialize(registration) }
      end

      # POST /api/v1/events/:event_id/registrations
      # `website` is a field people never see: a bot that fills it in is told it worked, and nothing is saved.
      def create
        fields = params.require(:registration).permit(:name, :phone, :email, :seats, :website)
        return render_signed_up(EventRegistration.new(fields.except(:website))) if fields[:website].present?

        registration = @event.reserve(fields.except(:website))
        if registration.persisted?
          render_signed_up(registration)
        else
          render json: { errors: registration.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/events/:event_id/registrations/:id
      def destroy
        registration = @event.registrations.find_by(id: params[:id])
        return render json: { error: 'Registration not found' }, status: :not_found unless registration

        @event.remove_registration(registration)
        render json: { message: 'Registration removed', id: registration.id }
      end

      private

      # Visitors can't sign up for drafts, so a draft looks like a missing event to them.
      def set_event
        @event = Event.find_by(id: params[:event_id])
        @event = nil if @event&.draft? && action_name == 'create'
        render json: { error: 'Event not found' }, status: :not_found unless @event
      end

      # Counts attempts in fixed windows per IP address.
      def throttle_sign_ups!
        return if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

        key = "event-rsvps/#{request.remote_ip}/#{Time.current.to_i / RSVP_WINDOW.to_i}"
        count = Rails.cache.increment(key, 1, expires_in: RSVP_WINDOW)
        count ||= Rails.cache.write(key, 1, expires_in: RSVP_WINDOW, raw: true) && 1
        return if count <= RSVP_LIMIT

        render json: { error: 'Too many sign-ups from this connection. Please try again in a few minutes.' },
               status: :too_many_requests
      end

      def render_signed_up(registration)
        @event.reload
        render json: { message: 'You’re on the list',
                       registration: { id: registration.id, name: registration.name, seats: registration.seats || 1 },
                       event: { id: @event.id, seats_taken: @event.seats_taken, seats_left: @event.seats_left,
                                registration_open: @event.registration_open?,
                                registrations_count: @event.registrations_count } },
               status: :created
      end

      def serialize(registration)
        registration.slice(:id, :name, :phone, :email, :seats, :created_at)
      end
    end
  end
end
