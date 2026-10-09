require 'test_helper'
require 'minitest/mock'

class EventTest < ActiveSupport::TestCase
  setup do
    @admin = users(:super_admin)
  end

  # --- Draft, published and cancelled ---

  test 'a draft needs only a title and a date' do
    event = Event.new(title: 'Ideas', date: '2026-11-07', status: 'draft', created_by: @admin)
    assert event.save, event.errors.full_messages.to_sentence
    assert_equal ['none', false, 0, 0],
                 [event.registration, event.featured, event.seats_taken, event.registrations_count]
  end

  test 'a title and a date are always required' do
    event = Event.new(status: 'draft', title: ' ', created_by: @admin)
    assert_not event.valid?
    assert_equal ["Title can't be blank", "Date can't be blank"], event.errors.full_messages
  end

  test 'published and cancelled events also need a category and a description' do
    %w[published cancelled].each do |status|
      event = Event.new(title: 'Prayer night', date: '2026-11-07', status: status, created_by: @admin)
      assert_not event.valid?, status
      assert_equal ["Category can't be blank", "Description can't be blank"], event.errors.full_messages
    end
    assert_equal 'published', Event.new.status
  end

  test 'lists and lengths are checked' do
    event = build(category: 'Weddings', status: 'archived', registration: 'tickets', title: 'a' * 151,
                  description: 'a' * 3001, location: 'a' * 151, speaker: 'a' * 121, speaker_role: 'a' * 121,
                  audience: 'a' * 81)
    assert_not event.valid?
    [
      'Category must be one of Conferences, Youth, Worship & Services, Outreach, Prayer',
      'Status must be draft, published or cancelled', 'Registration must be none, rsvp or external',
      'Title is too long (maximum is 150 characters)', 'Description is too long (maximum is 3000 characters)',
      'Location is too long (maximum is 150 characters)', 'Speaker is too long (maximum is 120 characters)',
      'Speaker role is too long (maximum is 120 characters)', 'Audience is too long (maximum is 80 characters)'
    ].each { |message| assert_includes event.errors.full_messages, message }
  end

  test 'strings are stripped and blank optional ones become nil' do
    event = build(title: ' Prayer night ', location: ' ', speaker: '', audience: '  Youth  ', registration: '')
    event.save!
    assert_equal ['Prayer night', nil, nil, 'Youth', 'none'],
                 [event.title, event.location, event.speaker, event.audience, event.registration]
  end

  # --- Days and times ---

  test 'a last day equal to the first is stored as nil; one before it is rejected' do
    assert_nil build(end_date: '2026-11-07').tap(&:save!).end_date

    event = build(end_date: '2026-11-06')
    assert_not event.valid?
    assert_equal ["Last day can't be before the first day"], event.errors.full_messages
  end

  test 'an end time needs a start time and must come after it' do
    assert_invalid build(end_time: '17:00'), "Start time is needed when there's an end time"
    assert_invalid build(start_time: '14:00', end_time: '12:00'), Event::OVERNIGHT_ERROR
    assert_invalid build(start_time: '14:00', end_time: '14:00'), Event::OVERNIGHT_ERROR
    assert build(start_time: '14:00', end_time: '17:30').valid?
    assert build(start_time: '14:00').valid?
  end

  test 'an overnight event is valid only when its last day is the next day' do
    assert_invalid build(start_time: '21:00', end_time: '05:00'), Event::OVERNIGHT_ERROR
    assert build(start_time: '21:00', end_time: '05:00', end_date: '2026-11-08').valid?
  end

  test 'unreadable dates and times are reported instead of dropped' do
    event = build(start_time: '25:99', end_time: 'later', end_date: '2026-13-01')
    assert_not event.valid?
    assert_includes event.errors.full_messages, "Start time isn't a valid time"
    assert_includes event.errors.full_messages, "End time isn't a valid time"
    assert_includes event.errors.full_messages, "Last day isn't a valid date"
  end

  # --- How people sign up ---

  test 'an external sign-up needs an http(s) link of at most 500 characters' do
    assert_invalid build(registration: 'external'), "Registration link can't be blank"
    assert_invalid build(registration: 'external', registration_url: 'forms.google.com/x'),
                   'Registration link must start with http:// or https://'
    assert_invalid build(registration: 'external', registration_url: 'javascript:alert(1)'),
                   'Registration link must start with http:// or https://'
    assert_invalid build(registration: 'external', registration_url: "https://example.com/#{'a' * 500}"),
                   'Registration link is too long (maximum is 500 characters)'
    assert build(registration: 'external', registration_url: 'https://forms.gle/abc').valid?
  end

  test 'settings for other ways of signing up are cleared' do
    event = build(registration: 'none', registration_url: 'https://forms.gle/abc', capacity: 40).tap(&:save!)
    assert_nil event.registration_url
    assert_nil event.capacity

    event.update!(registration: 'external', registration_url: 'https://forms.gle/abc', capacity: 40)
    assert_nil event.capacity
    event.update!(registration: 'rsvp', capacity: 40)
    assert_nil event.registration_url
    assert_equal 40, event.capacity
  end

  test 'capacity is a whole number from 1 to 10,000 and never below the seats taken' do
    [0, 10_001, 'abc', '2.5'].each do |capacity|
      assert_invalid build(registration: 'rsvp', capacity: capacity), 'Capacity must be a whole number from 1 to 10,000'
    end

    camp = events(:youth_camp) # 3 seats taken
    camp.capacity = 2
    assert_not camp.valid?
    assert_equal ['3 seats are already taken'], camp.errors.full_messages
    camp.capacity = 3
    assert camp.valid?
  end

  # --- Featured ---

  test 'featuring an event unfeatures the others' do
    first = build(featured: true).tap(&:save!)
    second = build(featured: true).tap(&:save!)
    assert_not first.reload.featured
    assert second.reload.featured

    first.update!(featured: true)
    assert_equal [first.id], Event.where(featured: true).pluck(:id)
  end

  # --- Upcoming and past, in Nairobi time ---

  test 'upcoming and past use the last day in Nairobi time' do
    Event.delete_all
    yesterday = build(title: 'Yesterday', date: '2026-11-06').tap(&:save!)
    today = build(title: 'Today', date: '2026-11-07').tap(&:save!)
    ongoing = build(title: 'Conference', date: '2026-11-05', end_date: '2026-11-08').tap(&:save!)

    # 21:30 UTC on the 6th is 00:30 on the 7th in Nairobi.
    travel_to Time.utc(2026, 11, 6, 21, 30) do
      assert_equal [today, ongoing].map(&:id).sort, Event.upcoming.pluck(:id).sort
      assert_equal [yesterday.id], Event.past.pluck(:id)
      assert ongoing.upcoming?
      assert_not yesterday.upcoming?
    end
  end

  test 'sign-ups are open for a published RSVP event until it starts, in Nairobi time' do
    event = build(registration: 'rsvp', start_time: '18:00').tap(&:save!) # 7 Nov, 18:00 Nairobi = 15:00 UTC

    travel_to(Time.utc(2026, 11, 7, 14, 59)) { assert event.registration_open? }
    travel_to(Time.utc(2026, 11, 7, 15, 0)) do
      assert_not event.registration_open?
      assert_equal 'Sign-ups for this event have closed.', event.sign_up_closed_reason
    end
  end

  test 'without a start time, sign-ups close when the first day begins in Nairobi' do
    event = build(registration: 'rsvp').tap(&:save!)

    travel_to(Time.utc(2026, 11, 6, 20, 59)) { assert event.registration_open? }
    travel_to(Time.utc(2026, 11, 6, 21, 0)) { assert_not event.registration_open? }
  end

  test 'sign-ups are closed for drafts, cancelled, non-RSVP and full events' do
    travel_to Time.utc(2026, 10, 9) do
      assert build(registration: 'rsvp', capacity: 2).registration_open?
      assert_not build(registration: 'rsvp', status: 'draft').registration_open?
      assert_not build(registration: 'none').registration_open?
      assert_equal 'This event has been cancelled.',
                   build(registration: 'rsvp', status: 'cancelled').sign_up_closed_reason
      assert_equal 'This event doesn’t take sign-ups on the website.',
                   build(registration: 'external').sign_up_closed_reason
      full = build(registration: 'rsvp', capacity: 2, seats_taken: 2)
      assert_equal 'This event is full.', full.sign_up_closed_reason
      assert_equal 0, full.seats_left
    end
  end

  # --- Reserving seats ---

  test 'reserve saves the sign-up and updates the counters; removing it frees the seats' do
    camp = events(:youth_camp)
    registration = camp.reserve(name: 'Mary', phone: '0722 000 111', seats: '4')

    assert registration.persisted?, registration.errors.full_messages.to_sentence
    assert_equal [3, 7], [camp.reload.registrations_count, camp.seats_taken]

    camp.remove_registration(registration)
    assert_equal [2, 3], [camp.reload.registrations_count, camp.seats_taken]
  end

  test 'reserve refuses more seats than are left' do
    camp = events(:youth_camp)
    camp.update!(capacity: 5) # 3 taken

    registration = camp.reserve(name: 'Mary', phone: '0722 000 111', seats: 3)
    assert_not registration.persisted?
    assert_equal ['Only 2 seats are left.'], registration.errors.full_messages
    assert_equal 3, camp.reload.seats_taken
  end

  test 'reserve reports a duplicate caught by the unique index' do
    camp = events(:youth_camp)
    racing = EventRegistration.new(event: camp, name: 'Grace again', phone: '+254712345678')
    racing.define_singleton_method(:not_already_registered) { nil } # as if both requests passed validation

    result = EventRegistration.stub(:new, racing) { camp.reserve({}) }

    assert_not result.persisted?
    assert_equal [EventRegistration::ALREADY_REGISTERED], result.errors.full_messages
    assert_equal 3, camp.reload.seats_taken
  end

  test 'deleting an event deletes its registrations' do
    assert_difference -> { EventRegistration.count } => -2 do
      events(:youth_camp).destroy!
    end
  end

  private

  def build(**attrs)
    Event.new({ title: 'Prayer night', category: 'Prayer', description: 'Come and pray.', date: '2026-11-07',
                created_by: @admin }.merge(attrs))
  end

  def assert_invalid(event, message)
    assert_not event.valid?, "expected #{message.inspect}"
    assert_includes event.errors.full_messages, message
  end
end
