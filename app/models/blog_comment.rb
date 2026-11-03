# A visitor's comment on a published blog post. Visitors post them through the public API; people with
# manage_blog approve, hide, reply to and delete them. author_email and ip_address are never shown publicly.
class BlogComment < ApplicationRecord
  STATUSES = %w[pending approved hidden].freeze
  # New public comments are approved straight away when true, and wait for approval otherwise. The frontend
  # handles both.
  AUTO_APPROVE = false
  MAX_BODY_LENGTH = 2000
  # Signs a reply from a user without a first or last name.
  CHURCH_NAME = 'AIC Kabuku'.freeze

  belongs_to :blog_post, inverse_of: :comments
  belongs_to :replied_by, class_name: 'User', optional: true

  before_validation :normalize_fields

  validates :author_name, presence: true, length: { maximum: 80 }
  validates :author_email, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 254 }, allow_nil: true
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
  validates :reply_body, length: { maximum: MAX_BODY_LENGTH }, allow_nil: true
  validates :status, inclusion: { in: STATUSES, message: "must be one of #{STATUSES.join(', ')}" }

  scope :approved, -> { where(status: 'approved') }
  scope :oldest_first, -> { order(:created_at, :id) }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def self.initial_status
    AUTO_APPROVE ? 'approved' : 'pending'
  end

  # { [blog_post_id, status] => count } for the given posts, in one query.
  def self.counts_for(post_ids)
    where(blog_post_id: post_ids).group(:blog_post_id, :status).count
  end

  # Sets the church's reply, signed by `user`; blank text removes the reply. replied_at changes only when the
  # text does.
  def reply_with(text, by:)
    text = text.to_s.strip.presence
    return remove_reply unless text

    self.replied_at = Time.current if text != reply_body
    assign_attributes(reply_body: text, replied_by: by,
                      reply_author_name: [by.firstname, by.lastname].compact_blank.join(' ').presence || CHURCH_NAME)
  end

  private

  def remove_reply
    assign_attributes(reply_body: nil, reply_author_name: nil, replied_at: nil, replied_by: nil)
  end

  # Strips whitespace; a blank email or reply becomes nil (the name and comment stay strings so they fail
  # presence).
  def normalize_fields
    self.author_name = author_name.strip if author_name.is_a?(String)
    self.body = body.strip if body.is_a?(String)
    self.author_email = author_email.strip.downcase.presence if author_email.is_a?(String)
    self.reply_body = reply_body.strip.presence if reply_body.is_a?(String)
  end
end
