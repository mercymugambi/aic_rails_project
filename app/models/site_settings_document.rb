# Cleans and checks the sections of the site settings document sent by the admin Settings page.
#
# Only the documented keys are kept, strings are trimmed and blank dates become nil. A field that isn't sent
# isn't stored: the frontend keeps the default values and fills in anything missing. Every problem is
# collected as a sentence an admin can read, e.g. "Sundays › First Service: the end time must be after
# the start time". Values of the wrong type are reported, never stored or raised.
class SiteSettingsDocument
  include Fields

  SECTIONS = %w[notice seo contact social service_times].freeze
  NOTICE_STYLES = %w[blue red dark green].freeze
  SEO_PAGES = { 'about' => 'About page', 'events' => 'Events page', 'blog' => 'Blog page',
                'gallery' => 'Gallery page', 'contact' => 'Contact page' }.freeze
  SOCIAL_NETWORKS = { 'facebook' => 'Facebook', 'youtube' => 'YouTube', 'instagram' => 'Instagram',
                      'x' => 'X (Twitter)', 'tiktok' => 'TikTok', 'whatsapp' => 'WhatsApp' }.freeze
  MAX_DAYS = 7
  MAX_SERVICES = 12
  SLOTS = (1..4)
  MAX_URL = 500
  TIME_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/
  PHONE_FORMAT = /\A[\d\s+\-()]{7,20}\z/
  EMAIL_FORMAT = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
  WEB_LINK = 'use a full link starting with https://'.freeze

  attr_reader :document, :errors

  # sections: the sections sent, keyed by name. Unknown sections are dropped.
  def initialize(sections)
    @errors = []
    @document = {}
    sections.each do |name, value|
      @document[name] = send(:"clean_#{name}", value) if SECTIONS.include?(name)
    end
  end

  def valid?
    errors.empty?
  end

  private

  def clean_notice(value)
    notice = group(value, 'Notice') or return
    out = {}
    take_boolean(notice, out, 'enabled', 'Notice › Show the notice bar')
    take_text(notice, out, 'label', 'Notice › Label', max: 20)
    message_needed = notice['enabled'] == true && 'write the message, or switch the notice bar off'
    take_text(notice, out, 'message', 'Notice › Message', max: 140, required: message_needed)
    take_text(notice, out, 'link_text', 'Notice › Link text', max: 24)
    take_notice_link(notice, out)
    take_choice(notice, out, 'style', 'Notice › Style', NOTICE_STYLES)
    take_dates(notice, out)
    out
  end

  # The link is rendered as an href, so only web links and paths on this site are allowed (never javascript:).
  def take_notice_link(notice, out)
    take_text(notice, out, 'link_url', 'Notice › Link', max: MAX_URL)
    url = out['link_url'].to_s
    needed = notice['link_text'].is_a?(String) && notice['link_text'].strip.present?
    return if url.empty? ? !needed : web_link?(url) || site_path?(url)

    add('Notice › Link', 'use a full link (https://…) or a page on this site (/events)')
  end

  def take_dates(notice, out)
    take_date(notice, out, 'starts_on', 'Notice › First day')
    take_date(notice, out, 'ends_on', 'Notice › Last day')
    return unless out['starts_on'] && out['ends_on'] && out['ends_on'] < out['starts_on']

    add('Notice › Last day', 'can’t be before the first day')
  end

  def clean_seo(value)
    seo = group(value, 'SEO') or return
    out = {}
    take_text(seo, out, 'site_name', 'SEO › Site name', max: 60, required: 'give the site a name')
    take_text(seo, out, 'home_title', 'SEO › Home page title', max: 120, required: 'the home page needs a title')
    take_text(seo, out, 'description', 'SEO › Description', max: 300, required: 'search results need a description')
    out['pages'] = clean_seo_pages(seo['pages']) if seo.key?('pages')
    out
  end

  def clean_seo_pages(value)
    pages = group(value, 'SEO › Pages') or return
    SEO_PAGES.each_with_object({}) do |(key, label), out|
      next unless pages.key?(key)

      page = group(pages[key], "SEO › #{label}") or next
      out[key] = {}
      take_text(page, out[key], 'title', "SEO › #{label} › Title", max: 80)
      take_text(page, out[key], 'description', "SEO › #{label} › Description", max: 300)
    end
  end

  def clean_contact(value)
    contact = group(value, 'Contact') or return
    out = {}
    take_text(contact, out, 'address', 'Contact › Address', max: 150)
    take_text(contact, out, 'phone', 'Contact › Phone', max: 20)
    take_text(contact, out, 'email', 'Contact › Email', max: 254)
    take_text(contact, out, 'office_hours', 'Contact › Office hours', max: 120)
    take_web_link(contact, out, 'map_url', 'Contact › Map link')
    check(out['phone'], 'Contact › Phone', 'use only digits, spaces and + - ( ), 7 to 20 characters') do |phone|
      phone.match?(PHONE_FORMAT)
    end
    check(out['email'], 'Contact › Email', 'enter a valid email address') { |email| email.match?(EMAIL_FORMAT) }
    out
  end

  def clean_social(value)
    social = group(value, 'Social links') or return
    SOCIAL_NETWORKS.each_with_object({}) do |(key, label), out|
      take_web_link(social, out, key, "Social links › #{label}")
    end
  end

  def clean_service_times(value)
    return add('Service times', 'must be a list of days') unless value.is_a?(Array)

    add('Service times', "can have at most #{MAX_DAYS} days") if value.size > MAX_DAYS
    value.each_with_index.map { |day, index| clean_day(day, index) }
  end

  def clean_day(value, index)
    day = group(value, "Day #{index + 1}") or return
    where = name_of(day['day'], "Day #{index + 1}")
    out = {}
    take_text(day, out, 'day', where, max: 40, required: 'name the day')
    take_text(day, out, 'tagline', "#{where} › Tagline", max: 60)
    take_text(day, out, 'note', "#{where} › Note", max: 300)
    out['services'] = clean_services(day['services'], where) if day.key?('services')
    out
  end

  def clean_services(value, where)
    return add(where, 'the services must be a list') unless value.is_a?(Array)

    add(where, "can have at most #{MAX_SERVICES} services") if value.size > MAX_SERVICES
    value.each_with_index.map do |service, index|
      clean_service(service, "#{where} › #{name_of(service.is_a?(Hash) && service['name'], "Service #{index + 1}")}")
    end
  end

  def clean_service(value, where)
    service = group(value, where) or return
    out = {}
    take_text(service, out, 'name', where, max: 60, required: 'name the service')
    take_boolean(service, out, 'main', "#{where} › Main service")
    take_text(service, out, 'description', "#{where} › Description", max: 100)
    out['slots'] = clean_slots(service['slots'], where)
    out
  end

  def clean_slots(value, where)
    return add(where, "add #{SLOTS.min} to #{SLOTS.max} times") unless value.is_a?(Array) && SLOTS.cover?(value.size)

    value.map do |slot|
      slot = group(slot, where) or next
      times = { 'start' => slot['start'], 'end' => slot['end'] }.transform_values do |time|
        time.is_a?(String) ? time.strip : time
      end
      check_slot(times, where)
      times
    end
  end

  def check_slot(times, where)
    return add(where, 'set both times') if times.values.any?(&:blank?)
    return add(where, 'times must be written HH:MM (24-hour), like 08:30') unless times.values.all?(TIME_FORMAT)

    add(where, 'the end time must be after the start time') unless times['end'] > times['start']
  end
end
