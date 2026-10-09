require 'test_helper'
require 'minitest/mock'

class Api::V1::EventRegistrationsControllerTest < ActionDispatch::IntegrationTest
  REGISTRATION_KEYS = %w[id name phone email seats created_at].freeze

  setup do
    @manager = users(:events_manager) # manage_events only
    @camp = events(:youth_camp) # RSVP, capacity 50, 3 seats taken by 2 registrations
    travel_to Time.utc(2026, 10, 9, 6)
  end

  # --- Signing up ---

  test 'an RSVP is saved, counted and answered without contact details' do
    assert_difference -> { EventRegistration.count } => 1 do
      rsvp name: ' Mary Njeri ', phone: '0722 000 111', email: '', seats: 4, website: ''
    end

    assert_response :created
    registration = EventRegistration.last
    assert_equal({ 'message' => 'You’re on the list',
                   'registration' => { 'id' => registration.id, 'name' => 'Mary Njeri', 'seats' => 4 },
                   'event' => { 'id' => @camp.id, 'seats_taken' => 7, 'seats_left' => 43, 'registration_open' => true,
                                'registrations_count' => 3 } }, response.parsed_body)
    assert_equal ['0722 000 111', nil, '254722000111'], [registration.phone, registration.email, registration.phone_key]
  end

  test 'the same phone number written another way is a duplicate' do
    assert_no_difference -> { EventRegistration.count } do
      rsvp name: 'Grace', phone: '+254712345678' # Grace signed up as 0712 345 678
    end
    assert_response :unprocessable_entity
    assert_equal ['You’re already on the list for this event.'], response.parsed_body['errors']
  end

  test 'a full event and too few seats are refused' do
    @camp.update!(capacity: 5)

    rsvp name: 'Mary', phone: '0722 000 111', seats: 3
    assert_response :unprocessable_entity
    assert_equal ['Only 2 seats are left.'], response.parsed_body['errors']

    rsvp name: 'Mary', phone: '0722 000 111', seats: 2
    assert_response :created
    assert_equal [5, 0, false],
                 response.parsed_body['event'].values_at('seats_taken', 'seats_left', 'registration_open')

    rsvp name: 'John', phone: '0733 000 222'
    assert_response :unprocessable_entity
    assert_equal ['This event is full.'], response.parsed_body['errors']
  end

  test 'sign-ups close when the event starts' do
    @camp.update!(date: '2026-10-09', start_time: '09:00') # 06:00 UTC

    travel_to(Time.utc(2026, 10, 9, 5, 59)) { rsvp name: 'Early', phone: '0722 000 111' }
    assert_response :created

    travel_to(Time.utc(2026, 10, 9, 6, 0)) { rsvp name: 'Late', phone: '0733 000 222' }
    assert_response :unprocessable_entity
    assert_equal ['Sign-ups for this event have closed.'], response.parsed_body['errors']
  end

  test 'cancelled events and events without website sign-ups are refused' do
    @camp.update!(status: 'cancelled')
    rsvp name: 'Mary', phone: '0722 000 111'
    assert_equal ['This event has been cancelled.'], response.parsed_body['errors']

    @camp.update!(status: 'published', registration: 'none')
    rsvp name: 'Mary', phone: '0722 000 111'
    assert_equal ['This event doesn’t take sign-ups on the website.'], response.parsed_body['errors']
  end

  test 'drafts and unknown events are not found' do
    @camp.update!(status: 'draft')
    rsvp name: 'Mary', phone: '0722 000 111'
    assert_response :not_found
    assert_equal({ 'error' => 'Event not found' }, response.parsed_body)

    post '/api/v1/events/999999/registrations', as: :json, params: { registration: { name: 'Mary', phone: '0722' } }
    assert_response :not_found
  end

  test 'invalid details are explained' do
    rsvp name: '', phone: '', email: '', seats: 11
    assert_response :unprocessable_entity
    assert_equal ["Name can't be blank", 'Seats must be a whole number from 1 to 10',
                  'Please give a phone number or an email address'], response.parsed_body['errors']
  end

  test 'a filled-in honeypot looks like success but saves nothing' do
    assert_no_difference -> { EventRegistration.count } do
      rsvp name: 'Bot', phone: '0722 000 111', website: 'http://spam.example'
    end

    assert_response :created
    assert_equal 'You’re on the list', response.parsed_body['message']
    assert_equal [3, 2], [@camp.reload.seats_taken, @camp.registrations_count]
  end

  test 'more than 5 sign-ups from one connection in 10 minutes get 429' do
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      5.times { |n| rsvp name: "Person #{n}", phone: "072200011#{n}" }
      assert_response :created

      rsvp name: 'Person 6', phone: '0722000116'
      assert_response :too_many_requests
      assert_equal({ 'error' => 'Too many sign-ups from this connection. Please try again in a few minutes.' },
                   response.parsed_body)

      travel 10.minutes
      rsvp name: 'Person 7', phone: '0722000117'
      assert_response :created
    end
  end

  test 'there is no limit with a null cache store' do
    7.times { |n| rsvp name: "Person #{n}", phone: "072200011#{n}" }
    assert_response :created
    assert_equal 9, @camp.reload.registrations_count
  end

  test 'create requires the registration key' do
    post "/api/v1/events/#{@camp.id}/registrations", as: :json, params: { name: 'Mary' }
    assert_response :bad_request
    assert_equal({ 'error' => 'Send the registration details under a "registration" key' }, response.parsed_body)
  end

  # --- The list (manage_events) ---

  test 'managers see the registrations, oldest first' do
    get "/api/v1/events/#{@camp.id}/registrations", headers: auth_headers(@manager)

    assert_response :ok
    rows = response.parsed_body
    assert_equal REGISTRATION_KEYS, rows.first.keys
    assert_equal @camp.registrations.order(:created_at, :id).pluck(:id), rows.pluck('id')
    assert_includes rows.pluck('phone'), '0712 345 678'
  end

  test 'removing a registration frees its seats' do
    grace = event_registrations(:grace_at_youth_camp)

    delete "/api/v1/events/#{@camp.id}/registrations/#{grace.id}", headers: auth_headers(@manager)

    assert_response :ok
    assert_equal({ 'message' => 'Registration removed', 'id' => grace.id }, response.parsed_body)
    assert_equal [1, 1], [@camp.reload.registrations_count, @camp.seats_taken]

    delete "/api/v1/events/#{@camp.id}/registrations/#{grace.id}", headers: auth_headers(@manager)
    assert_response :not_found
  end

  test 'the list and removing need login and manage_events' do
    grace = event_registrations(:grace_at_youth_camp)

    get "/api/v1/events/#{@camp.id}/registrations", headers: { 'Accept' => 'application/json' }
    assert_response :unauthorized
    delete "/api/v1/events/#{@camp.id}/registrations/#{grace.id}", as: :json
    assert_response :unauthorized

    get "/api/v1/events/#{@camp.id}/registrations", headers: auth_headers(users(:treasurer))
    assert_response :forbidden
    delete "/api/v1/events/#{@camp.id}/registrations/#{grace.id}", headers: auth_headers(users(:treasurer))
    assert_response :forbidden
    assert EventRegistration.exists?(grace.id)
  end

  test 'public event JSON never includes who signed up' do
    get "/api/v1/events/#{@camp.id}", as: :json
    assert_not_includes response.body, 'Grace'
    assert_not_includes response.body, '0712'
  end

  private

  def rsvp(**fields)
    post "/api/v1/events/#{@camp.id}/registrations", as: :json, params: { registration: fields }
  end
end
