module Api
  module V1
    class AppointmentsController < ApplicationController
      skip_before_action :verify_authenticity_token

      # GET /api/v1/appointments/booked_slots?year=2026&month=10
      def booked_slots
        appts = Appointment.for_month(params[:year], params[:month])
        booked = appts.map { |a| "#{a.appointment_date} #{a.appointment_time}" }
        render json: { booked: booked }
      end

      # POST /api/v1/appointments
      def create
        appt = Appointment.new(appointment_params)

        # Check if slot is already taken
        conflict = Appointment.where(
          appointment_date: appt.appointment_date,
          appointment_time: appt.appointment_time,
          status: %w[pending confirmed]
        ).exists?

        if conflict
          return render json: { error: 'That time slot has just been booked. Please choose another.' }, status: :conflict
        end

        if appt.save
          AppointmentMailer.confirmation(appt).deliver_later
          AppointmentMailer.pastor_notification(appt).deliver_later
          render json: { message: 'Appointment booked successfully.', id: appt.id }, status: :created
        else
          render json: { error: appt.errors.full_messages.join(', ') }, status: :unprocessable_entity
        end
      end

      # GET /api/v1/appointments/:token/request_reschedule
      # Pastor clicks this link in their email to trigger a reschedule request
      def request_reschedule
        appt = Appointment.find_by(token: params[:token])
        return render json: { error: 'Appointment not found' }, status: :not_found unless appt

        appt.update(status: 'reschedule_requested', reschedule_note: params[:note])
        AppointmentMailer.reschedule_request(appt).deliver_later
        render json: { message: 'Reschedule request sent to the visitor.' }
      end

      private

      def appointment_params
        params.require(:appointment).permit(
          :name, :email, :phone, :purpose, :notes,
          :appointment_date, :appointment_time, :pastor_email
        )
      end
    end
  end
end
