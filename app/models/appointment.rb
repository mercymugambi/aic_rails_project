class Appointment < ApplicationRecord
  validates :name, :email, :appointment_date, :appointment_time, :purpose, presence: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }

  before_create :generate_token
  before_create :set_default_status

  scope :for_month, ->(year, month) {
    where(appointment_date: Date.new(year.to_i, month.to_i, 1)..Date.new(year.to_i, month.to_i, -1))
      .where(status: %w[confirmed pending])
  }

  private

  def generate_token
    self.token = SecureRandom.urlsafe_base64(16)
  end

  def set_default_status
    self.status ||= 'pending'
  end
end
