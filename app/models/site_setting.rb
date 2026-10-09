# The settings shown across the public website (notice bar, SEO, contact details, social links, service
# times), stored as one JSON document in a single row. The frontend keeps the default values, so a section
# that was never saved is simply missing from the document.
class SiteSetting < ApplicationRecord
  belongs_to :updated_by, class_name: 'User', optional: true

  def self.current
    order(:id).first || new
  end

  # The saved document, or {} when nothing has been saved yet.
  def self.document
    order(:id).pick(:data) || {}
  end

  # Saves the sections sent (each replaces the stored one; the others are kept). Returns [setting, saved].
  # Two first saves at the same moment would both try to create the single row; the second one is retried
  # on top of the first.
  def self.save_sections(sections, user)
    setting = current
    [setting, setting.save_sections(sections, user)]
  rescue ActiveRecord::RecordNotUnique
    setting = current
    [setting, setting.save_sections(sections, user)]
  end

  # Returns false, with errors, when a section is invalid; nothing is saved then.
  def save_sections(sections, user)
    cleaned = SiteSettingsDocument.new(sections)
    unless cleaned.valid?
      cleaned.errors.each { |message| errors.add(:base, message) }
      return false
    end

    self.data = data.merge(cleaned.document)
    self.updated_by = user
    save
  end
end
