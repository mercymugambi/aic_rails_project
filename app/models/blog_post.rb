class BlogPost < ApplicationRecord
  include CoverImage

  # The frontend has the same list.
  CATEGORIES = ['Faith & Devotion', 'Church Life', 'Youth', 'Family', 'Outreach', 'Testimonies'].freeze
  STATUSES = %w[published draft].freeze
  SLUG_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  MAX_SLUG_LENGTH = 80
  MAX_TAGS = 10
  WORDS_PER_MINUTE = 200

  belongs_to :created_by, class_name: 'User', optional: true
  # Photos inside the body (see BlogPostImage). Destroying a post deletes them and their files.
  has_many :body_images, class_name: 'BlogPostImage', dependent: :destroy, inverse_of: :blog_post

  before_validation :normalize_fields
  before_validation :assign_slug
  before_save :unfeature_other_posts, if: -> { featured? && will_save_change_to_featured? }
  after_save :attach_body_images, if: :saved_change_to_body?
  after_commit :purge_unused_body_images, on: %i[create update]

  validates :title, presence: true, length: { maximum: 150 }
  validates :slug, presence: true, length: { maximum: MAX_SLUG_LENGTH }, uniqueness: true,
                   format: { with: SLUG_FORMAT, allow_blank: true,
                             message: 'can only contain lowercase letters, numbers and single hyphens' }
  validates :excerpt, length: { maximum: 220 }
  validates :category, inclusion: { in: CATEGORIES, message: "must be one of #{CATEGORIES.join(', ')}" },
                       allow_nil: true
  validates :status, inclusion: { in: STATUSES, message: 'must be published or draft' }
  # A draft only needs a title.
  validates :excerpt, :category, :published_on, presence: true, if: :published?
  validate :body_is_valid

  scope :published, -> { where(status: 'published') }
  scope :newest_first, -> { order(published_on: :desc, created_at: :desc, id: :desc) }

  # Accepts the blocks as an array or as a JSON string (multipart forms send a string). Unreadable
  # JSON leaves the body unchanged and fails validation.
  def body=(value)
    @body_unreadable = false
    value = JSON.parse(value) if value.is_a?(String) && value.present?
    super(value.presence || [])
  rescue JSON::ParserError
    @body_unreadable = true
  end

  def published?
    status == 'published'
  end

  def read_minutes
    [(BlogPostBody.word_count(body) / WORDS_PER_MINUTE.to_f).round, 1].max
  end

  private

  # Strips whitespace; blank optional strings become nil (the title stays a string so it fails presence).
  def normalize_fields
    self.title = title.strip if title.is_a?(String)
    %i[slug excerpt category status author_name author_role].each do |attribute|
      self[attribute] = self[attribute].strip.presence if self[attribute].is_a?(String)
    end
    self.tags = normalized_tags
    self.body = BlogPostBody.normalize(body) unless @body_unreadable
  end

  # Trimmed, no blanks, deduplicated ignoring case (the first spelling wins), at most MAX_TAGS.
  def normalized_tags
    Array(tags).map { |tag| tag.to_s.strip }.reject(&:empty?).uniq(&:downcase).first(MAX_TAGS)
  end

  # A blank slug is made from the title. On update a blank slug keeps the current one, so old links
  # keep working. A slug that is taken gets -2, -3... appended. Outer hyphens are trimmed: the editor
  # cuts its slug at 80 characters, which can end on a hyphen.
  def assign_slug
    self.slug = slug.to_s.gsub(/\A-+|-+\z/, '').presence || (slug_in_database if persisted?) || slug_from_title
    return unless will_save_change_to_slug? && slug.length <= MAX_SLUG_LENGTH && slug.match?(SLUG_FORMAT)

    self.slug = unique_slug(slug)
  end

  # "God's Love!" => "gods-love"; "post" when the title has no letters or digits.
  def slug_from_title
    title.to_s.delete("'’").parameterize[0, MAX_SLUG_LENGTH].to_s.sub(/-+\z/, '').presence || 'post'
  end

  def unique_slug(candidate)
    return candidate unless slug_taken?(candidate)

    (2..).each do |number|
      suffix = "-#{number}"
      attempt = "#{candidate[0, MAX_SLUG_LENGTH - suffix.length].sub(/-+\z/, '')}#{suffix}"
      return attempt unless slug_taken?(attempt)
    end
  end

  def slug_taken?(candidate)
    self.class.where.not(id: id).exists?(slug: candidate)
  end

  def body_is_valid
    return errors.add(:base, 'The post content could not be read. Please try saving again.') if @body_unreadable

    BlogPostBody.errors_for(body).each { |message| errors.add(:base, message) }
    errors.add(:body, :blank) if published? && body == []
    body_images_are_uploaded if new_record? || will_save_change_to_body?
  end

  # Every photo in the body was uploaded and is either unattached or already attached to this post.
  def body_images_are_uploaded
    ids = BlogPostBody.image_ids(body)
    return if ids.empty? || errors.added?(:base, BlogPostBody::PHOTO_ERROR)
    return if BlogPostImage.where(token: ids, blog_post_id: [nil, id].uniq).count == ids.size

    errors.add(:base, BlogPostBody::PHOTO_ERROR)
  end

  # Only one post is featured; the unique index enforces it.
  def unfeature_other_posts
    self.class.where(featured: true).where.not(id: id).update_all(featured: false, updated_at: Time.current)
  end

  # Claims the body's photos for this post. Validation already checked them; this guards against
  # another post claiming one in between, and rolls the save back if so.
  def attach_body_images
    @check_unused_images = true
    ids = BlogPostBody.image_ids(body)
    return if ids.empty?

    claimed = BlogPostImage.where(token: ids, blog_post_id: [nil, id]).update_all(blog_post_id: id,
                                                                                  updated_at: Time.current)
    return if claimed == ids.size

    errors.add(:base, BlogPostBody::PHOTO_ERROR)
    raise ActiveRecord::RecordInvalid, self
  end

  # Deletes photos no longer used in the body.
  def purge_unused_body_images
    return unless @check_unused_images

    @check_unused_images = false
    body_images.where.not(token: BlogPostBody.image_ids(body)).destroy_all
    body_images.reset
  end
end
