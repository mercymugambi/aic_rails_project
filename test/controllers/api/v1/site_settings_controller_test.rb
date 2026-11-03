require 'test_helper'

class Api::V1::SiteSettingsControllerTest < ActionDispatch::IntegrationTest
  # The document the admin Settings page sends: all five sections.
  DOCUMENT = {
    'notice' => { 'enabled' => true, 'label' => 'Notice', 'message' => 'Watch sermons on YouTube every week.',
                  'link_text' => 'Watch Sermons', 'link_url' => 'https://youtube.com', 'style' => 'blue',
                  'starts_on' => nil, 'ends_on' => '2026-12-31' },
    'seo' => { 'site_name' => 'AIC Kabuku Church', 'home_title' => 'AIC Kabuku Church | Kiambu, Kenya',
               'description' => 'A Bible-believing church family.',
               'pages' => { 'about' => { 'title' => 'About Us', 'description' => 'Our story.' },
                            'events' => { 'title' => 'Church Events & Calendar', 'description' => 'What is on.' },
                            'blog' => { 'title' => 'Blog', 'description' => '' },
                            'gallery' => { 'title' => 'Photo Gallery', 'description' => 'Photos.' },
                            'contact' => { 'title' => 'Contact Us', 'description' => 'Get in touch.' } } },
    'contact' => { 'address' => 'Kabuku, Kiambu County, Kenya', 'phone' => '+254 712 345 678',
                   'email' => 'office@aickabuku.org', 'office_hours' => 'Mon–Fri, 9:00–17:00',
                   'map_url' => 'https://maps.app.goo.gl/abc123' },
    'social' => { 'facebook' => '', 'youtube' => 'https://youtube.com/@aickabuku', 'instagram' => '', 'x' => '',
                  'tiktok' => '', 'whatsapp' => '' },
    'service_times' => [
      { 'day' => 'Sundays', 'tagline' => 'Our main day of worship', 'note' => '',
        'services' => [
          { 'name' => 'First Service', 'slots' => [{ 'start' => '08:30', 'end' => '10:00' }], 'main' => true,
            'description' => 'A calm start in worship and the Word.' },
          { 'name' => 'Sunday School (Children)', 'main' => false, 'description' => '',
            'slots' => [{ 'start' => '08:30', 'end' => '10:00' }, { 'start' => '11:00', 'end' => '12:30' }] }
        ] }
    ]
  }.freeze

  setup do
    @manager = users(:settings_manager) # manage_settings only
  end

  # --- GET ---

  test 'GET answers {} before anything is saved, without a token' do
    get '/api/v1/site_settings'

    assert_response :ok
    assert_equal({}, response.parsed_body)
  end

  test 'GET returns exactly what was saved, unwrapped' do
    save_settings DOCUMENT
    assert_response :ok

    get '/api/v1/site_settings'

    assert_response :ok
    assert_equal DOCUMENT, response.parsed_body
  end

  # --- PATCH: access ---

  test 'PATCH needs login' do
    patch '/api/v1/site_settings', as: :json, params: { site_settings: DOCUMENT }
    assert_response :unauthorized
    assert_equal 0, SiteSetting.count
  end

  test 'PATCH needs manage_settings' do
    save_settings DOCUMENT, user: users(:treasurer)
    assert_response :forbidden
    assert_equal({ 'error' => 'You do not have permission to perform this action' }, response.parsed_body)
    assert_equal 0, SiteSetting.count
  end

  test 'PATCH is allowed with manage_settings and for the super admin' do
    save_settings DOCUMENT
    assert_response :ok

    save_settings DOCUMENT, user: users(:super_admin)
    assert_response :ok
    assert_equal users(:super_admin), SiteSetting.current.updated_by
  end

  # --- PATCH: saving ---

  test 'PATCH saves the whole document, answers with it unwrapped and records who saved it' do
    save_settings DOCUMENT

    assert_equal DOCUMENT, response.parsed_body
    assert_equal 1, SiteSetting.count
    assert_equal DOCUMENT, SiteSetting.current.data
    assert_equal @manager, SiteSetting.current.updated_by
  end

  test 'unknown keys are dropped at every level' do
    document = DOCUMENT.deep_dup
    document['theme'] = 'dark'
    document['notice']['html'] = '<script>'
    document['seo']['pages']['shop'] = { 'title' => 'Shop', 'description' => '' }
    document['social']['myspace'] = 'https://myspace.com/x'
    service = document['service_times'][0]['services'][0]
    service['price'] = 100
    service['slots'][0]['room'] = 'Hall'

    save_settings document

    assert_response :ok
    assert_equal DOCUMENT, response.parsed_body
    assert_equal DOCUMENT, SiteSetting.current.data
  end

  test 'strings are trimmed and blank dates stored as null' do
    document = DOCUMENT.deep_dup
    document['notice'].merge!('message' => '  Join us  ', 'starts_on' => '', 'ends_on' => ' 2026-12-31 ')
    document['contact']['phone'] = ' +254 712 345 678 '

    save_settings document

    notice = response.parsed_body['notice']
    assert_equal ['Join us', nil, '2026-12-31'], notice.values_at('message', 'starts_on', 'ends_on')
    assert_equal '+254 712 345 678', response.parsed_body['contact']['phone']
  end

  test 'each section sent replaces the stored one; sections not sent are kept' do
    save_settings DOCUMENT
    notice = DOCUMENT['notice'].merge('enabled' => false, 'message' => '')

    save_settings({ 'notice' => notice })

    assert_response :ok
    assert_equal DOCUMENT.merge('notice' => notice), response.parsed_body
    assert_equal DOCUMENT['seo'], SiteSetting.current.data['seo']
  end

  test 'an empty list of service times is stored as an empty list' do
    save_settings DOCUMENT.merge('service_times' => [])

    assert_response :ok
    assert_equal [], response.parsed_body['service_times']
    assert_equal [], SiteSetting.current.data['service_times']
  end

  # --- PATCH: rejections ---

  test 'an enabled notice needs a message' do
    assert_rejected({ 'notice' => { 'enabled' => true, 'message' => '  ' } },
                    'Notice › Message: write the message, or switch the notice bar off')
  end

  test 'the notice link must be a web link or a page on this site' do
    ['javascript:alert(1)', 'JavaScript:alert(1)', 'data:text/html,hi', '//evil.example', 'youtube.com'].each do |url|
      assert_rejected({ 'notice' => { 'link_text' => 'Watch', 'link_url' => url } },
                      'Notice › Link: use a full link (https://…) or a page on this site (/events)')
    end
    assert_rejected({ 'notice' => { 'link_text' => 'Watch', 'link_url' => '' } },
                    'Notice › Link: use a full link (https://…) or a page on this site (/events)')

    save_settings({ 'notice' => { 'link_text' => 'Events', 'link_url' => '/events' } })
    assert_response :ok
  end

  test 'notice dates must be real and in order' do
    assert_rejected({ 'notice' => { 'starts_on' => '2026-12-01', 'ends_on' => '2026-11-30' } },
                    'Notice › Last day: can’t be before the first day')
    assert_rejected({ 'notice' => { 'starts_on' => '2026-02-30' } },
                    'Notice › First day: must be a real date written YYYY-MM-DD')
    assert_rejected({ 'notice' => { 'ends_on' => '31/12/2026' } },
                    'Notice › Last day: must be a real date written YYYY-MM-DD')
  end

  test 'the notice style must be one of the four' do
    assert_rejected({ 'notice' => { 'style' => 'purple' } }, 'Notice › Style: must be one of blue, red, dark, green')
  end

  test 'contact email, phone and map link are checked' do
    assert_rejected({ 'contact' => { 'email' => 'office@' } }, 'Contact › Email: enter a valid email address')
    assert_rejected({ 'contact' => { 'phone' => 'call us' } },
                    'Contact › Phone: use only digits, spaces and + - ( ), 7 to 20 characters')
    assert_rejected({ 'contact' => { 'map_url' => 'maps.app.goo.gl/x' } },
                    'Contact › Map link: use a full link starting with https://')
  end

  test 'social links need https://' do
    assert_rejected({ 'social' => { 'facebook' => 'facebook.com/aickabuku' } },
                    'Social links › Facebook: use a full link starting with https://')
  end

  test 'service times are checked and the messages name the day and service' do
    assert_rejected(service('slots' => [{ 'start' => '10:00', 'end' => '08:30' }]),
                    'Sundays › First Service: the end time must be after the start time')
    assert_rejected(service('slots' => [{ 'start' => '8:30', 'end' => '10:00' }]),
                    'Sundays › First Service: times must be written HH:MM (24-hour), like 08:30')
    assert_rejected(service('slots' => [{ 'start' => '08:30' }]), 'Sundays › First Service: set both times')
    assert_rejected(service('slots' => []), 'Sundays › First Service: add 1 to 4 times')
    assert_rejected(service('name' => ' '), 'Sundays › Service 1: name the service')
    assert_rejected({ 'service_times' => [{ 'day' => '', 'services' => [] }] }, 'Day 1: name the day')
  end

  test 'over-long text is rejected' do
    assert_rejected({ 'notice' => { 'message' => 'a' * 141 } }, 'Notice › Message: must be 140 characters or fewer')
    assert_rejected({ 'seo' => DOCUMENT['seo'].merge('site_name' => 'a' * 61) },
                    'SEO › Site name: must be 60 characters or fewer')
    assert_rejected(service('description' => 'a' * 101),
                    'Sundays › First Service › Description: must be 100 characters or fewer')
  end

  test 'values of the wrong type are rejected, never a 500' do
    assert_rejected({ 'notice' => { 'enabled' => 'yes' } }, 'Notice › Show the notice bar: must be true or false')
    assert_rejected({ 'service_times' => 'Sundays at 8' }, 'Service times: must be a list of days')
    assert_rejected(service('slots' => '08:30-10:00'), 'Sundays › First Service: add 1 to 4 times')
    assert_rejected(service('main' => 'yes'), 'Sundays › First Service › Main service: must be true or false')
    assert_rejected({ 'seo' => 'AIC Kabuku' }, 'SEO: must be a group of settings')
    assert_rejected({ 'contact' => { 'email' => 42 } }, 'Contact › Email: must be text')
  end

  test 'every problem is reported at once' do
    save_settings({ 'notice' => { 'enabled' => true, 'message' => '', 'style' => 'pink' },
                    'contact' => { 'email' => 'nope' } })

    assert_response :unprocessable_entity
    assert_equal ['Notice › Message: write the message, or switch the notice bar off',
                  'Notice › Style: must be one of blue, red, dark, green',
                  'Contact › Email: enter a valid email address'], response.parsed_body['errors']
  end

  test 'a rejected save changes nothing' do
    save_settings DOCUMENT

    save_settings({ 'seo' => DOCUMENT['seo'].merge('site_name' => 'New name'), 'social' => { 'x' => 'x.com/aic' } })

    assert_response :unprocessable_entity
    assert_equal DOCUMENT, SiteSetting.current.data
  end

  # --- PATCH: request shape ---

  test 'the site_settings key is required' do
    patch '/api/v1/site_settings', headers: auth_headers(@manager), as: :json, params: { notice: DOCUMENT['notice'] }

    assert_response :bad_request
    assert_equal({ 'error' => 'Send the settings under a "site_settings" key' }, response.parsed_body)
  end

  test 'site_settings that is not an object is rejected' do
    patch '/api/v1/site_settings', headers: auth_headers(@manager), as: :json, params: { site_settings: 'reset' }

    assert_response :unprocessable_entity
    assert_equal ['Settings must be a group of sections'], response.parsed_body['errors']
  end

  private

  def save_settings(document, user: @manager)
    patch '/api/v1/site_settings', headers: auth_headers(user), as: :json, params: { site_settings: document }
  end

  # A document whose first Sunday service has the given changes.
  def service(changes)
    day = DOCUMENT['service_times'][0].deep_dup
    day['services'][0].merge!(changes)
    { 'service_times' => [day] }
  end

  def assert_rejected(document, message)
    assert_no_difference -> { SiteSetting.count } do
      save_settings document
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'], message
  end
end
