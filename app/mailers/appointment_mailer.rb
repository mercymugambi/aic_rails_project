class AppointmentMailer < ApplicationMailer
  default from: ENV.fetch('GMAIL_USERNAME', nil)

  def confirmation(appointment)
    @appointment = appointment
    @reschedule_url = "#{ENV.fetch('FRONTEND_URL', nil)}/appointments/reschedule/#{appointment.token}"
    mail(
      to: appointment.email,
      subject: '📅 Appointment Scheduled — AIC Kabuku Church'
    )
  end

  def pastor_confirmed(appointment)
    @appointment = appointment
    mail(
      to: appointment.email,
      subject: '✅ Appointment Confirmed by Pastor — AIC Kabuku Church'
    )
  end

  def pastor_notification(appointment)
    @appointment = appointment
    @dashboard_url = "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3001')}/admin/appointments"
    @reschedule_url = appointment.gmail_reschedule_url
    mail(
      to: appointment.pastor_email,
      subject: "📅 New Appointment Request: #{appointment.name} — #{appointment.appointment_date.strftime('%B %d, %Y')}"
    )
  end

  def reschedule_request(appointment)
    @appointment = appointment
    mail(
      to: appointment.email,
      subject: '📅 Reschedule Request — AIC Kabuku Church'
    )
  end
end
