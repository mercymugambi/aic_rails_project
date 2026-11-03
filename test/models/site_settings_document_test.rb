require 'test_helper'

class SiteSettingsDocumentTest < ActiveSupport::TestCase
  SLOT = { 'start' => '08:30', 'end' => '10:00' }.freeze

  test 'fields that are not sent are not stored' do
    document = SiteSettingsDocument.new('notice' => { 'message' => 'Hi' }, 'social' => { 'youtube' => '' })

    assert document.valid?
    assert_equal({ 'notice' => { 'message' => 'Hi' }, 'social' => { 'youtube' => '' } }, document.document)
  end

  test 'unknown sections are dropped' do
    assert_equal({}, SiteSettingsDocument.new('theme' => { 'color' => 'red' }).document)
  end

  test 'SEO needs a site name, home title and description, and keeps only the five pages' do
    document = SiteSettingsDocument.new('seo' => { 'pages' => { 'about' => { 'title' => 'a' * 81 }, 'shop' => {} } })

    assert_equal ['SEO › Site name: give the site a name', 'SEO › Home page title: the home page needs a title',
                  'SEO › Description: search results need a description',
                  'SEO › About page › Title: must be 80 characters or fewer'], document.errors
    assert_equal %w[about], document.document['seo']['pages'].keys
  end

  test 'at most 7 days, 12 services a day and 4 times a service' do
    day = { 'day' => 'Sundays', 'services' => [{ 'name' => 'Service', 'slots' => [SLOT] * 5 }] * 13 }
    document = SiteSettingsDocument.new('service_times' => [day] * 8)

    assert_includes document.errors, 'Service times: can have at most 7 days'
    assert_includes document.errors, 'Sundays: can have at most 12 services'
    assert_includes document.errors, 'Sundays › Service: add 1 to 4 times'
  end

  test 'a day without a services list is stored without one; a services value that is not a list is rejected' do
    assert_equal [{ 'day' => 'Fridays' }], SiteSettingsDocument.new('service_times' => [{ 'day' => 'Fridays' }])
      .document['service_times']

    document = SiteSettingsDocument.new('service_times' => [{ 'day' => 'Fridays', 'services' => 'Youth' }])
    assert_equal ['Fridays: the services must be a list'], document.errors
  end

  test 'web links need http(s) and a real host' do
    { 'https://wa.me/254712345678' => true, 'http://facebook.com/aic' => true, 'https://localhost' => false,
      'ftp://files.example.com' => false, 'https://exa mple.com' => false, 'javascript://example.com' => false }
      .each do |url, ok|
        document = SiteSettingsDocument.new('social' => { 'whatsapp' => url })
        assert_equal ok, document.valid?, url
      end
  end

  test 'the notice link may be a page on this site' do
    assert SiteSettingsDocument.new('notice' => { 'link_text' => 'Events', 'link_url' => '/events?when=past' }).valid?
    assert_not SiteSettingsDocument.new('notice' => { 'link_url' => '//evil.example/x' }).valid?
  end

  test 'a disabled notice may have an empty message' do
    assert SiteSettingsDocument.new('notice' => { 'enabled' => false, 'message' => '' }).valid?
  end
end
