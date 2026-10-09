require 'test_helper'
require 'minitest/mock'

class Api::V1::EventsControllerTest < ActionDispatch::IntegrationTest
  ITEM_KEYS = %w[id title category status featured date end_date start_time end_time location speaker speaker_role
                 audience description cover_image_url registration registration_url capacity seats_taken seats_left
                 registrations_count registration_open created_by created_at updated_at].freeze
  # 9 Oct 2026, 09:00 in Nairobi.
  NOW = Time.utc(2026, 10, 9, 6).freeze

  setup do
    @manager = users(:events_manager) # manage_events only
    @treasurer = users(:treasurer) # no manage_events
    travel_to NOW
  end

  # --- Index ---

  test 'index lists upcoming published and cancelled events, soonest first, by default' do
    Event.delete_all
    evening = create_event(title: 'Evening', date: '2026-10-20', start_time: '18:00')
    all_day = create_event(title: 'All day', date: '2026-10-20')
    morning = create_event(title: 'Morning', date: '2026-10-20', start_time: '08:00')
    ongoing = create_event(title: 'Conference', date: '2026-10-07', end_date: '2026-10-10')
    cancelled = create_event(title: 'Cancelled', date: '2026-11-01', status: 'cancelled')
    create_event(title: 'Draft', date: '2026-10-15', status: 'draft')
    create_event(title: 'Past', date: '2026-10-08')

    get '/api/v1/events', as: :json

    assert_response :ok
    assert_kind_of Array, response.parsed_body
    assert_equal [ongoing, all_day, morning, evening, cancelled].map(&:id), response.parsed_body.pluck('id')
  end

  test 'when=past lists finished events, latest last day first; when=all lists everything public, newest first' do
    Event.delete_all
    long_ago = create_event(title: 'Long ago', date: '2026-08-01')
    retreat = create_event(title: 'Retreat', date: '2026-09-01', end_date: '2026-10-08')
    last_week = create_event(title: 'Last week', date: '2026-10-02')
    upcoming = create_event(title: 'Upcoming', date: '2026-10-20')
    create_event(title: 'Old draft', date: '2026-09-15', status: 'draft')

    get '/api/v1/events', params: { when: 'past' }, as: :json
    assert_equal [retreat, last_week, long_ago].map(&:id), response.parsed_body.pluck('id')

    get '/api/v1/events', params: { when: 'all' }, as: :json
    assert_equal [upcoming, last_week, retreat, long_ago].map(&:id), response.parsed_body.pluck('id')
  end

  test 'status=all adds drafts for manage_events and combines with when' do
    Event.delete_all
    draft = create_event(title: 'Draft', date: '2026-10-15', status: 'draft')
    published = create_event(title: 'Published', date: '2026-10-16')
    old_draft = create_event(title: 'Old draft', date: '2026-09-15', status: 'draft')

    get '/api/v1/events', params: { status: 'all' }, headers: auth_headers(@manager)
    assert_response :ok
    assert_equal [draft, published].map(&:id), response.parsed_body.pluck('id')

    get '/api/v1/events', params: { status: 'all', when: 'all' }, headers: auth_headers(@manager)
    assert_equal [published, draft, old_draft].map(&:id), response.parsed_body.pluck('id')
  end

  test 'status=all needs login and manage_events' do
    get '/api/v1/events', params: { status: 'all' }, headers: { 'Accept' => 'application/json' }
    assert_response :unauthorized

    get '/api/v1/events', params: { status: 'all' }, headers: auth_headers(@treasurer)
    assert_response :forbidden
    assert_equal({ 'error' => 'You do not have permission to perform this action' }, response.parsed_body)
  end

  test 'items have exactly the documented keys and values' do
    get "/api/v1/events/#{events(:youth_camp).id}", as: :json

    item = response.parsed_body
    assert_equal ITEM_KEYS, item.keys
    camp = events(:youth_camp)
    assert_equal({ 'id' => camp.id, 'title' => 'Youth camp', 'category' => 'Youth', 'status' => 'published',
                   'featured' => false, 'date' => camp.date.iso8601, 'end_date' => nil, 'start_time' => '09:00',
                   'end_time' => '16:00', 'location' => 'Youth Fellowship Center', 'speaker' => nil,
                   'speaker_role' => nil, 'audience' => nil, 'description' => 'Annual youth camp',
                   'cover_image_url' => nil, 'registration' => 'rsvp', 'registration_url' => nil, 'capacity' => 50,
                   'seats_taken' => 3, 'seats_left' => 47, 'registrations_count' => 2, 'registration_open' => true,
                   'created_by' => { 'id' => users(:super_admin).id, 'name' => 'admin@example.com' } },
                 item.except('created_at', 'updated_at'))
  end

  test 'created_by shows the first and last name when there is one; seats_left is null without a capacity' do
    event = create_event(created_by: @manager)

    get "/api/v1/events/#{event.id}", as: :json

    assert_equal({ 'id' => @manager.id, 'name' => 'Esther Muthoni' }, response.parsed_body['created_by'])
    assert_nil response.parsed_body['seats_left']
  end

  test 'index loads covers and creators without N+1 queries' do
    Event.delete_all
    create_event(cover: true)
    one_event = count_queries { get '/api/v1/events', as: :json }
    3.times { |n| create_event(cover: true, created_by: n.even? ? @manager : users(:super_admin)) }
    four_events = count_queries { get '/api/v1/events', as: :json }

    assert_equal 4, response.parsed_body.size
    assert_equal one_event, four_events
  end

  # --- Show ---

  test 'show hides drafts unless the request comes from someone who manages events' do
    draft = create_event(status: 'draft')

    get "/api/v1/events/#{draft.id}", as: :json
    assert_response :not_found
    assert_equal({ 'error' => 'Event not found' }, response.parsed_body)

    get "/api/v1/events/#{draft.id}", headers: auth_headers(@treasurer)
    assert_response :not_found

    get "/api/v1/events/#{draft.id}", headers: auth_headers(@manager)
    assert_response :ok
    assert_equal 'draft', response.parsed_body['status']

    get '/api/v1/events/999999', as: :json
    assert_response :not_found
  end

  # --- Create ---

  test 'create accepts the multipart form the admin sends, with a cover photo' do
    fields = form_fields.merge(featured: 'true', end_date: '', start_time: '14:00', end_time: '17:30',
                               speaker: '', registration: 'rsvp', capacity: '80', registration_url: '',
                               cover_image: fixture_file_upload('photo.jpg', 'image/jpeg'))

    assert_difference -> { Event.count } => 1, -> { ActiveStorage::Blob.count } => 1 do
      post '/api/v1/events', headers: auth_headers(@manager), params: { event: fields }
    end

    assert_response :created
    assert_equal 'Event created', response.parsed_body['message']
    item = response.parsed_body['event']
    assert_equal ITEM_KEYS, item.keys
    assert_equal [true, nil, '14:00', '17:30', nil, 'rsvp', 80, 80, true],
                 item.values_at('featured', 'end_date', 'start_time', 'end_time', 'speaker', 'registration',
                                'capacity', 'seats_left', 'registration_open')
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/.+/photo\.jpg\z},
                 item['cover_image_url']
    event = Event.find(item['id'])
    assert_equal @manager, event.created_by
    assert ActiveStorage::Blob.service.exist?(event.cover_image.key)
  end

  test 'create accepts JSON and saves a draft with only a title and a date' do
    post '/api/v1/events', headers: auth_headers(@manager), as: :json,
                           params: { event: { title: 'Ideas', date: '2026-12-01', status: 'draft' } }

    assert_response :created
    assert_equal %w[draft none], response.parsed_body['event'].values_at('status', 'registration')
  end

  test 'create explains what is missing or wrong' do
    assert_no_difference -> { Event.count } do
      post '/api/v1/events', headers: auth_headers(@manager),
                             params: { event: { title: 'Vigil', date: '2026-12-01', category: '', description: ' ',
                                                start_time: '21:00', end_time: '05:00' } }
    end

    assert_response :unprocessable_entity
    assert_equal ["Category can't be blank", "Description can't be blank", Event::OVERNIGHT_ERROR],
                 response.parsed_body['errors']
  end

  test 'create rejects a cover that is not a photo and keeps no file' do
    pdf = Rack::Test::UploadedFile.new(StringIO.new('%PDF-1.4 hello'), 'application/pdf', original_filename: 'a.pdf')

    assert_no_difference [-> { Event.count }, -> { ActiveStorage::Blob.count }] do
      post '/api/v1/events', headers: auth_headers(@manager), params: { event: form_fields.merge(cover_image: pdf) }
    end
    assert_equal ['Cover image must be a JPG, PNG or WEBP file'], response.parsed_body['errors']
  end

  test 'a failed cover upload leaves no event or file behind' do
    failing_upload = ->(*, **) { raise ActiveStorage::IntegrityError, 'Invalid api_key' }

    assert_no_difference [-> { Event.count }, -> { ActiveStorage::Blob.count }] do
      ActiveStorage::Blob.service.stub(:upload, failing_upload) do
        post '/api/v1/events', headers: auth_headers(@manager),
                               params: { event: form_fields.merge(cover_image: fixture_file_upload('photo.jpg')) }
      end
    end

    assert_response :bad_gateway
    assert_equal({ 'error' => "The photo couldn't be saved to storage. Please try again." }, response.parsed_body)
  end

  test 'create requires the event key' do
    post '/api/v1/events', headers: auth_headers(@manager), params: { title: 'x' }
    assert_response :bad_request
    assert_equal({ 'error' => 'Send the event details under an "event" key' }, response.parsed_body)
  end

  # --- Update ---

  test 'a partial update changes only the keys sent' do
    camp = events(:youth_camp)

    patch "/api/v1/events/#{camp.id}", headers: auth_headers(@manager), as: :json,
                                       params: { event: { location: 'Main Sanctuary' } }

    assert_response :ok
    assert_equal 'Event updated', response.parsed_body['message']
    item = response.parsed_body['event']
    assert_equal ['Main Sanctuary', 'Youth camp', '09:00', 50, 3], item.values_at('location', 'title', 'start_time',
                                                                                  'capacity', 'seats_taken')
  end

  test 'the admin list can cancel an event with a JSON status change' do
    camp = events(:youth_camp)

    patch "/api/v1/events/#{camp.id}", headers: auth_headers(@manager), as: :json,
                                       params: { event: { status: 'cancelled' } }

    assert_response :ok
    assert_equal ['cancelled', false], response.parsed_body['event'].values_at('status', 'registration_open')
  end

  test 'featuring an event moves the feature from the old one' do
    old = create_event(featured: true)
    camp = events(:youth_camp)

    patch "/api/v1/events/#{camp.id}", headers: auth_headers(@manager), params: { event: { featured: 'true' } }

    assert_response :ok
    assert response.parsed_body['event']['featured']
    assert_not old.reload.featured
  end

  test 'update validates and changes nothing on error' do
    camp = events(:youth_camp)

    patch "/api/v1/events/#{camp.id}", headers: auth_headers(@manager), as: :json,
                                       params: { event: { title: 'New', capacity: 2 } }

    assert_response :unprocessable_entity
    assert_equal ['3 seats are already taken'], response.parsed_body['errors']
    assert_equal 'Youth camp', camp.reload.title
  end

  test 'remove_cover_image deletes the cover' do
    event = create_event(cover: true)
    blob = event.cover_image.blob

    assert_difference -> { ActiveStorage::Blob.count } => -1 do
      patch "/api/v1/events/#{event.id}", headers: auth_headers(@manager),
                                          params: { event: { remove_cover_image: 'true' } }
    end

    assert_response :ok
    assert_nil response.parsed_body['event']['cover_image_url']
    assert_not ActiveStorage::Blob.service.exist?(blob.key)
  end

  test 'replacing the cover deletes the old file' do
    event = create_event(cover: true)
    old_blob = event.cover_image.blob

    patch "/api/v1/events/#{event.id}", headers: auth_headers(@manager),
                                        params: { event: { cover_image: fixture_file_upload('photo.png'),
                                                           remove_cover_image: 'true' } }

    assert_response :ok
    assert_match(/photo\.png\z/, response.parsed_body['event']['cover_image_url'])
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
    assert_not ActiveStorage::Blob.service.exist?(old_blob.key)
  end

  # --- Destroy ---

  test 'destroy deletes the event, its registrations and its cover file' do
    event = create_event(cover: true, registration: 'rsvp')
    event.reserve(name: 'Mary', phone: '0722 000 111')
    key = event.cover_image.key

    assert_difference -> { Event.count } => -1, -> { EventRegistration.count } => -1,
                      -> { ActiveStorage::Blob.count } => -1 do
      delete "/api/v1/events/#{event.id}", headers: auth_headers(@manager), as: :json
    end

    assert_response :ok
    assert_equal({ 'message' => 'Event deleted', 'id' => event.id }, response.parsed_body)
    assert_not ActiveStorage::Blob.service.exist?(key)
  end

  test 'unknown event id returns 404' do
    patch '/api/v1/events/999999', headers: auth_headers(@manager), as: :json, params: { event: { title: 'X' } }
    assert_response :not_found
    assert_equal({ 'error' => 'Event not found' }, response.parsed_body)

    delete '/api/v1/events/999999', headers: auth_headers(@manager), as: :json
    assert_response :not_found
  end

  # --- Authentication and permissions ---

  test 'create, update and destroy need login' do
    camp = events(:youth_camp)

    post '/api/v1/events', as: :json, params: { event: form_fields }
    assert_response :unauthorized

    patch "/api/v1/events/#{camp.id}", as: :json, params: { event: { title: 'X' } }
    assert_response :unauthorized

    delete "/api/v1/events/#{camp.id}", as: :json
    assert_response :unauthorized
    assert Event.exists?(camp.id)
  end

  test 'users without manage_events get 403' do
    camp = events(:youth_camp)
    headers = auth_headers(@treasurer)

    assert_no_difference -> { Event.count } do
      post '/api/v1/events', headers: headers, as: :json, params: { event: form_fields }
    end
    assert_response :forbidden

    patch "/api/v1/events/#{camp.id}", headers: headers, as: :json, params: { event: { title: 'X' } }
    assert_response :forbidden

    delete "/api/v1/events/#{camp.id}", headers: headers, as: :json
    assert_response :forbidden
    assert_equal 'Youth camp', camp.reload.title
  end

  test 'super admin and church admin are allowed' do
    [users(:super_admin), users(:church_admin)].each do |user|
      post '/api/v1/events', headers: auth_headers(user), as: :json, params: { event: form_fields }
      assert_response :created, user.email
    end
  end

  private

  def form_fields
    { title: 'Marriage seminar', category: 'Worship & Services', status: 'published', date: '2026-10-17',
      description: 'For engaged and married couples.' }
  end

  def create_event(cover: false, **attrs)
    event = Event.new({ title: 'Prayer night', category: 'Prayer', description: 'Come and pray.', date: '2026-10-20',
                        created_by: users(:super_admin) }.merge(attrs))
    if cover
      event.cover_image.attach(io: file_fixture('photo.jpg').open, filename: 'photo.jpg', content_type: 'image/jpeg')
    end
    event.save!
    event
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
