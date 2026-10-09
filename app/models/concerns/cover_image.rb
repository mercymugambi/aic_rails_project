# A cover photo (has_one_attached :cover_image) for blog posts and events: JPG, PNG or WEBP up to 10 MB.
#
# Save with save_with_uploads: the file is uploaded before the record is saved, so a storage failure leaves
# nothing half-saved. A replaced or removed cover, and the cover of a deleted record, is deleted from storage
# after the transaction commits (Rails 7.0 would only do that with a background job).
module CoverImage
  extend ActiveSupport::Concern

  included do
    has_one_attached :cover_image, dependent: false

    before_save :remember_replaced_cover
    before_destroy :remember_cover_blob
    after_commit :purge_replaced_cover

    validate :cover_image_is_acceptable
  end

  # Validates, uploads a new cover image, then saves. If the save itself fails the uploaded file is
  # deleted again.
  def save_with_uploads
    return false unless valid?

    uploaded = upload_new_cover
    save.tap { |saved| uploaded&.purge unless saved }
  rescue StandardError
    uploaded&.purge
    raise
  end

  private

  def cover_image_is_acceptable
    return unless cover_image.attached?

    blob = cover_image.blob
    unless BlogPostImage::IMAGE_TYPES.include?(blob.content_type)
      errors.add(:base, 'Cover image must be a JPG, PNG or WEBP file')
    end
    errors.add(:base, 'Cover image must be 10 MB or smaller') if blob.byte_size > BlogPostImage::MAX_IMAGE_SIZE
  end

  def upload_new_cover
    change = attachment_changes['cover_image']
    return unless change.is_a?(ActiveStorage::Attached::Changes::CreateOne) && !change.blob.persisted?

    change.upload
    change.blob.save!
    # Attaching the stored blob (not the file) stops Active Storage uploading it a second time.
    self.cover_image = change.blob
    change.blob
  end

  def remember_replaced_cover
    return unless attachment_changes.key?('cover_image')

    old_blob = cover_image_attachment&.blob
    @replaced_cover_blob = old_blob unless old_blob == attachment_changes['cover_image'].try(:blob)
  end

  def remember_cover_blob
    @replaced_cover_blob = cover_image.blob if cover_image.attached?
  end

  def purge_replaced_cover
    blob = @replaced_cover_blob
    @replaced_cover_blob = nil
    blob&.purge
  rescue StandardError => e
    Rails.logger.error("#{self.class.name} #{id}: could not delete file #{blob.key} from storage: #{e.message}")
  end
end
