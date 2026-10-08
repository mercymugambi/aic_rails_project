# A photo placed between paragraphs of a blog post. Writers upload it while drafting, before the post
# exists; the post's body then refers to it by `token` (the opaque `image_id` the frontend sees). Saving
# the post attaches the photo (sets blog_post_id). Photos never attached are removed by purge_orphans.
class BlogPostImage < ApplicationRecord
  # Same rules as gallery photos. Also Cloudinary's free-plan limit for images.
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_IMAGE_SIZE = 10.megabytes
  ORPHAN_AGE = 24.hours

  belongs_to :blog_post, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  # Purged synchronously after the record is deleted, as in GalleryImage.
  has_one_attached :image, dependent: false
  has_secure_token :token

  before_destroy :remember_image_blob
  after_destroy_commit :purge_image

  validate :image_is_acceptable

  scope :unattached, -> { where(blog_post_id: nil) }

  # Deletes photos uploaded more than ORPHAN_AGE ago that no post refers to, with their files.
  # Run with `bin/rails blog:purge_orphan_images`. Returns the number of photos deleted.
  def self.purge_orphans(older_than: ORPHAN_AGE.ago)
    unattached.where(created_at: ...older_than).find_each.count(&:destroy)
  end

  # Saves the photo and uploads its file; on a storage failure the rows are removed and the error
  # re-raised, as in GalleryImage#save_with_image.
  def save_with_image
    save
  rescue StandardError
    discard_rows if persisted?
    raise
  end

  private

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
    Rails.logger.error("Blog post image #{id}: could not delete file #{@image_blob.key} from storage: #{e.message}")
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
