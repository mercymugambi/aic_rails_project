# An RSVP from the public Events page. Create it through Event#reserve, which checks the seats under a lock;
# creating or deleting one keeps the event's registrations_count and seats_taken up to date.
class EventRegistration < ApplicationRecord
  ALREADY_REGISTERED = 'You’re already on the list for this event.'.freeze
  PHONE_FORMAT = /\A[\d\s+\-()]+\z/
  MAX_SEATS = 10

  belongs_to :event, inverse_of: :registrations

  before_validation :normalize_fields
  after_create :take_seats
  after_destroy :free_seats

  validates :name, presence: true, length: { maximum: 100 }
  validates :phone, length: { maximum: 20 }
  validates :email, length: { maximum: 120 },
                    format: { with: URI::MailTo::EMAIL_REGEXP, message: "doesn't look right" }, allow_nil: true
  validates :seats, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: MAX_SEATS,
                                    message: 'must be a whole number from 1 to 10' }
  validate :phone_looks_right
  validate :phone_or_email_given
  validate :not_already_registered

  # Digits only, with Kenyan numbers in one form: "0712 345 678", "+254 712 345 678" and "712345678" all
  # give "254712345678".
  def self.phone_key(phone)
    digits = phone.to_s.gsub(/\D/, '').delete_prefix('00')
    return if digits.empty?
    return "254#{digits[1..]}" if digits.length == 10 && digits.start_with?('0')
    return "254#{digits}" if digits.length == 9 && digits.match?(/\A[17]/)

    digits
  end

  private

  def normalize_fields
    %i[name phone email].each do |attribute|
      self[attribute] = self[attribute].strip.presence if self[attribute].is_a?(String)
    end
    self.seats = 1 if read_attribute_before_type_cast(:seats).blank?
    self.phone_key = self.class.phone_key(phone)
    self.email_key = email&.downcase
  end

  def phone_looks_right
    return if phone.nil? || (phone.match?(PHONE_FORMAT) && phone_key.to_s.length >= 7)

    errors.add(:phone, "doesn't look right")
  end

  def phone_or_email_given
    errors.add(:base, 'Please give a phone number or an email address') if phone.nil? && email.nil?
  end

  def not_already_registered
    others = EventRegistration.where(event_id: event_id).where.not(id: id)
    taken = (phone_key && others.exists?(phone_key: phone_key)) || (email_key && others.exists?(email_key: email_key))
    errors.add(:base, ALREADY_REGISTERED) if taken
  end

  def take_seats
    Event.update_counters(event_id, registrations_count: 1, seats_taken: seats)
  end

  def free_seats
    Event.update_counters(event_id, registrations_count: -1, seats_taken: -seats)
  end
end
