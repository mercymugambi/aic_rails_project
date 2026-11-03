class GalleryImage < ApplicationRecord
  # The frontend has the same list.
  CATEGORIES = %w[Worship Community Prayer Children Outreach].freeze
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  # Also Cloudinary's free-plan limit for images.
  MAX_IMAGE_SIZE = 10.megabytes

  belongs_to :created_by, class_name: 'User', optional: true
  # Rails 7.0 only deletes the file for dependent: :purge_later (a background job), so the file is
  # purged synchronously after the record is deleted instead: see purge_image.
  has_one_attached :image, dependent: false

  before_validation :normalize_fields
  before_destroy :remember_image_blob
  after_destroy_commit :purge_image

  validates :title, length: { maximum: 150 }
  validates :category, inclusion: { in: CATEGORIES, message: "must be one of #{CATEGORIES.join(', ')}" },
                       allow_nil: true
  validate :image_is_acceptable

  # Newest events first; photos without a date go last.
  scope :newest_first, -> { order(arel_table[:taken_on].desc.nulls_last, created_at: :desc, id: :desc) }

  # Saves a new photo and uploads its file. Rails 7.0 uploads the file only after the record is
  # committed, so if the upload fails (wrong CLOUDINARY_URL, no network) the rows are removed again
  # and the error is re-raised: the gallery never lists a photo without a file.
  def save_with_image
    save
  rescue StandardError
    discard_rows if persisted?
    raise
  end

  private

  def normalize_fields
    self.title = title.strip if title.is_a?(String)
    self.category = category.strip.presence if category.is_a?(String)
  end

  def image_is_acceptable
    return errors.add(:image, :blank) unless image.attached?

    errors.add(:base, 'Image must be a JPG, PNG or WEBP file') unless IMAGE_TYPES.include?(image.blob.content_type)
    errors.add(:base, 'Image must be 10 MB or smaller') if image.blob.byte_size > MAX_IMAGE_SIZE
  end

  def remember_image_blob
    @image_blob = image.blob
  end

  def purge_image
    @image_blob&.purge
  rescue StandardError => e
    Rails.logger.error("Gallery image #{id}: could not delete file #{@image_blob.key} from storage: #{e.message}")
  end

  def discard_rows
    blob_id = image_attachment&.blob_id
    transaction do
      ActiveStorage::Attachment.where(record: self).delete_all
      ActiveStorage::Blob.where(id: blob_id).delete_all
      self.class.where(id: id).delete_all
    end
  end
end
