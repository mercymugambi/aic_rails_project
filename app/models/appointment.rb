class Appointment < ApplicationRecord
  STATUSES = %w[pending confirmed reschedule_requested completed cancelled].freeze

  validates :name, :email, :phone, :appointment_date, :appointment_time, :purpose, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :status, inclusion: { in: STATUSES }, allow_nil: true

  before_create :generate_token
  before_create :set_default_status

  scope :for_month, lambda { |year, month|
    where(appointment_date: Date.new(year.to_i, month.to_i, 1)..Date.new(year.to_i, month.to_i, -1))
      .where(status: %w[confirmed pending])
  }

  def gmail_reschedule_url
    date_str = appointment_date.strftime('%A, %B %d, %Y')
    query = URI.encode_www_form(
      view: 'cm',
      fs: 1,
      to: email,
      su: "Reschedule Request: Appointment at AIC Kabuku Church (#{date_str})",
      body: reschedule_email_body(date_str)
    )
    "https://mail.google.com/mail/?#{query}"
  end

  private

  def reschedule_email_body(date_str)
    "Dear #{name},\n\n" \
      "Thank you for booking an appointment for #{purpose} on #{date_str} at #{appointment_time}.\n\n" \
      'Unfortunately, I will not be available at that time. Could we please reschedule to another ' \
      "date and time that works for you?\n\n" \
      "God bless you,\nPastor — AIC Kabuku Church"
  end

  def generate_token
    self.token = SecureRandom.urlsafe_base64(16)
  end

  def set_default_status
    self.status ||= 'pending'
  end
end
