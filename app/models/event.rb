class Event < ApplicationRecord
  include CoverImage

  # The frontend has the same list (src/data/events.js).
  CATEGORIES = ['Conferences', 'Youth', 'Worship & Services', 'Outreach', 'Prayer'].freeze
  STATUSES = %w[draft published cancelled].freeze
  # How people sign up: not at all, an RSVP on the website, or a link to another site.
  REGISTRATIONS = %w[none rsvp external].freeze
  MAX_CAPACITY = 10_000
  # Dates and times are the church's wall clock (UTC+3, no daylight saving), whatever config.time_zone is.
  TIME_ZONE = ActiveSupport::TimeZone['Africa/Nairobi']
  OVERNIGHT_ERROR = 'Ends before it starts. If it runs past midnight, set the last day.'.freeze

  belongs_to :created_by, class_name: 'User'
  has_many :registrations, class_name: 'EventRegistration', dependent: :delete_all, inverse_of: :event

  before_validation :normalize_fields
  before_save :unfeature_other_events, if: -> { featured? && will_save_change_to_featured? }

  validates :title, presence: true, length: { maximum: 150 }
  validates :date, presence: true
  # A draft only needs a title and a date.
  validates :category, :description, presence: true, unless: :draft?
  validates :description, length: { maximum: 3000 }
  validates :location, length: { maximum: 150 }
  validates :speaker, :speaker_role, length: { maximum: 120 }
  validates :audience, length: { maximum: 80 }
  validates :registration_url, length: { maximum: 500 }
  validates :category, inclusion: { in: CATEGORIES, message: "must be one of #{CATEGORIES.join(', ')}" },
                       allow_nil: true
  validates :status, inclusion: { in: STATUSES, message: 'must be draft, published or cancelled' }
  validates :registration, inclusion: { in: REGISTRATIONS, message: 'must be none, rsvp or external' }
  validates :capacity, numericality: { only_integer: true, greater_than_or_equal_to: 1,
                                       less_than_or_equal_to: MAX_CAPACITY,
                                       message: 'must be a whole number from 1 to 10,000' }, allow_nil: true
  validate :dates_and_times_are_readable
  validate :end_date_is_valid
  validate :timing_is_valid
  validate :registration_url_is_valid
  validate :capacity_holds_seats_taken

  # What visitors see: drafts are hidden, cancelled events are shown so people know.
  scope :visible, -> { where(status: %w[published cancelled]) }
  # An event is upcoming until its last day is over, so an event on now is still upcoming.
  scope :upcoming, -> { where('COALESCE(events.end_date, events.date) >= ?', TIME_ZONE.today) }
  scope :past, -> { where('COALESCE(events.end_date, events.date) < ?', TIME_ZONE.today) }

  # period: 'upcoming' (the default, soonest first), 'past' (latest last day first) or 'all' (newest first).
  def self.happening(period)
    case period
    when 'past' then past.order(Arel.sql('COALESCE(events.end_date, events.date) DESC'), date: :desc, id: :desc)
    when 'all' then order(date: :desc, id: :desc)
    else upcoming.order(:date).order(arel_table[:start_time].asc.nulls_first).order(:id)
    end
  end

  def draft?
    status == 'draft'
  end

  def last_day
    end_date || date
  end

  def upcoming?
    last_day >= TIME_ZONE.today
  end

  # Start of the first day when there is no start time.
  def starts_at
    wall_clock(date, start_time)
  end

  def seats_left
    [capacity - seats_taken, 0].max if capacity
  end

  def registration_open?
    sign_up_closed_reason.nil?
  end

  # Why the website can't take an RSVP right now, or nil when it can.
  def sign_up_closed_reason
    return 'This event has been cancelled.' if status == 'cancelled'
    return 'This event doesn’t take sign-ups on the website.' unless registration == 'rsvp'
    return 'Sign-ups for this event have closed.' unless status == 'published' && Time.current < starts_at

    'This event is full.' if seats_left&.zero?
  end

  # Signs someone up. The row lock makes the seat check and the counters hold when people sign up at the
  # same moment. Returns the registration: saved, or with errors to show.
  def reserve(attributes)
    registration = EventRegistration.new(attributes.merge(event: self))
    with_lock { add_registration(registration) }
    registration
  rescue ActiveRecord::RecordNotUnique
    # The same person signed up twice at once; the unique index stopped the second one.
    registration.errors.add(:base, EventRegistration::ALREADY_REGISTERED)
    registration
  end

  # Removes a sign-up and frees its seats (EventRegistration updates the counters).
  def remove_registration(registration)
    with_lock { registration.destroy! }
  end

  private

  def add_registration(registration)
    reason = sign_up_closed_reason
    reason ||= seats_shortage(registration.seats) if registration.valid?
    return registration.errors.add(:base, reason) if reason

    registration.save
  end

  def seats_shortage(seats)
    return unless seats_left && seats > seats_left

    "Only #{seats_left} #{seats_left == 1 ? 'seat is' : 'seats are'} left."
  end

  def wall_clock(day, time)
    TIME_ZONE.local(day.year, day.month, day.day, time&.hour.to_i, time&.min.to_i)
  end

  # Strips whitespace; blank optional strings become nil (the title stays a string so it fails presence).
  # Settings that only apply to one way of signing up are cleared for the others.
  def normalize_fields
    self.title = title.strip if title.is_a?(String)
    %i[category status location speaker speaker_role audience description registration
       registration_url].each do |attribute|
      self[attribute] = self[attribute].strip.presence if self[attribute].is_a?(String)
    end
    self.end_date = nil if end_date == date
    clear_other_sign_up_settings
  end

  def clear_other_sign_up_settings
    self.registration ||= 'none'
    self.registration_url = nil unless registration == 'external'
    self.capacity = nil unless registration == 'rsvp'
  end

  # A date or time that couldn't be read is stored as nil; say so instead of ignoring it.
  def dates_and_times_are_readable
    { end_date: "isn't a valid date", start_time: "isn't a valid time", end_time: "isn't a valid time" }
      .each do |attribute, message|
        errors.add(attribute, message) if self[attribute].nil? && read_attribute_before_type_cast(attribute).present?
      end
  end

  def end_date_is_valid
    errors.add(:end_date, "can't be before the first day") if date && end_date && end_date < date
  end

  # Compares the full start and end moments, so an overnight vigil (21:00 to 05:00) needs the next day as
  # its last day.
  def timing_is_valid
    return unless end_time
    return errors.add(:start_time, "is needed when there's an end time") unless start_time
    return if date.nil? || (end_date && end_date < date)
    return if wall_clock(last_day, end_time) > starts_at

    errors.add(:base, OVERNIGHT_ERROR)
  end

  def registration_url_is_valid
    return unless registration == 'external'
    return errors.add(:registration_url, :blank) if registration_url.blank?

    errors.add(:registration_url, 'must start with http:// or https://') unless http_url?(registration_url)
  end

  def http_url?(value)
    uri = URI.parse(value)
    uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def capacity_holds_seats_taken
    return unless capacity.is_a?(Integer) && capacity < seats_taken

    errors.add(:base, "#{seats_taken} #{seats_taken == 1 ? 'seat is' : 'seats are'} already taken")
  end

  # Only one event is featured; the unique index enforces it.
  def unfeature_other_events
    self.class.where(featured: true).where.not(id: id).update_all(featured: false, updated_at: Time.current)
  end
end
