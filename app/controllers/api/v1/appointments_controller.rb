module Api
  module V1
    class AppointmentsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!, only: %i[index update destroy]
      before_action -> { authorize!(:manage_appointments, :view_reports) }, only: :index
      before_action -> { authorize!(:manage_appointments) }, only: %i[update destroy]
      before_action :set_appointment, only: %i[update destroy]

      # GET /api/v1/appointments
      def index
        appts = Appointment.order(appointment_date: :desc, appointment_time: :asc, created_at: :desc)
        render json: appts.map { |appt| serialize_appointment(appt) }
      end

      # GET /api/v1/appointments/booked_slots?year=2026&month=10
      def booked_slots
        appts = Appointment.for_month(params[:year], params[:month])
        booked = appts.map { |a| "#{a.appointment_date} #{a.appointment_time}" }
        render json: { booked: booked }
      end

      # POST /api/v1/appointments
      def create
        appt = Appointment.new(appointment_params)
        return render_slot_conflict if slot_taken?(appt)

        if appt.save
          deliver_booking_emails(appt)
          render json: { message: 'Appointment booked successfully.', id: appt.id }, status: :created
        else
          render json: { error: appt.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end
      end

      # PATCH/PUT /api/v1/appointments/:id
      def update
        if @appointment.update(update_appointment_params)
          notify_pastor_confirmation(@appointment)
          render json: serialize_appointment(@appointment)
        else
          render json: { errors: @appointment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/appointments/:id
      def destroy
        @appointment.destroy
        render json: { message: 'Appointment deleted', id: @appointment.id }
      end

      # GET /api/v1/appointments/:id/request_reschedule
      # Backwards-compatible fallback if an older email link is clicked
      def request_reschedule
        appt = Appointment.find_by(token: params[:id] || params[:token])
        return render json: { error: 'Appointment not found' }, status: :not_found unless appt

        appt.update(status: 'reschedule_requested', reschedule_note: params[:note])
        redirect_to appt.gmail_reschedule_url, allow_other_host: true
      end

      private

      def set_appointment
        @appointment = Appointment.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Appointment not found' }, status: :not_found
      end

      def slot_taken?(appt)
        Appointment.exists?(
          appointment_date: appt.appointment_date,
          appointment_time: appt.appointment_time,
          status: %w[pending confirmed]
        )
      end

      def render_slot_conflict
        render json: { error: 'That time slot has just been booked. Please choose another.' },
               status: :conflict
      end

      def deliver_booking_emails(appt)
        AppointmentMailer.confirmation(appt).deliver_later
        AppointmentMailer.pastor_notification(appt).deliver_later
      end

      def notify_pastor_confirmation(appt)
        return unless appt.saved_change_to_status? && appt.status == 'confirmed'

        AppointmentMailer.pastor_confirmed(appt).deliver_later
      end

      def serialize_appointment(appt)
        {
          id: appt.id,
          name: appt.name,
          email: appt.email,
          phone: appt.phone,
          purpose: appt.purpose,
          notes: appt.notes,
          appointment_date: appt.appointment_date,
          appointment_time: appt.appointment_time,
          status: appt.status,
          reschedule_note: appt.reschedule_note,
          pastor_email: appt.pastor_email,
          gmail_reschedule_url: appt.gmail_reschedule_url,
          created_at: appt.created_at
        }
      end

      def appointment_params
        params.require(:appointment).permit(
          :name, :email, :phone, :purpose, :notes,
          :appointment_date, :appointment_time, :pastor_email
        )
      end

      def update_appointment_params
        params.require(:appointment).permit(
          :status, :reschedule_note, :appointment_date, :appointment_time, :notes, :phone
        )
      end
    end
  end
end
