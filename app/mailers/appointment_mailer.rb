class AppointmentMailer < ApplicationMailer
  default from: ENV['GMAIL_USERNAME']

  def confirmation(appointment)
    @appointment = appointment
    @reschedule_url = "#{ENV['FRONTEND_URL']}/appointments/reschedule/#{appointment.token}"
    mail(
      to: appointment.email,
      subject: "✅ Appointment Confirmed — AIC Kabuku Church"
    )
  end

  def pastor_notification(appointment)
    @appointment = appointment
    @reschedule_url = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/api/v1/appointments/#{appointment.token}/request_reschedule"
    mail(
      to: appointment.pastor_email,
      subject: "📅 New Appointment Request: #{appointment.name} — #{appointment.appointment_date.strftime('%B %d, %Y')}"
    )
  end

  def reschedule_request(appointment)
    @appointment = appointment
    mail(
      to: appointment.email,
      subject: "📅 Reschedule Request — AIC Kabuku Church"
    )
  end
end
