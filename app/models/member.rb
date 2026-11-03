class Member < ApplicationRecord
  STRING_ATTRIBUTES = %w[first_name middle_name last_name phone_number email place_of_residence].freeze
  PHONE_FORMAT = /\A[\d\s+\-()]+\z/

  # Deleting a member who has a login account is refused (see MembersController#destroy),
  # so the user is never silently unlinked by the users.member_id ON DELETE NULLIFY foreign key.
  has_one :user, dependent: :restrict_with_error
  has_and_belongs_to_many :leadership_positions, join_table: 'members_leadership_positions'
  has_and_belongs_to_many :fellowship_groups

  before_validation :normalize_strings

  validates :first_name, :last_name, presence: true, length: { maximum: 50 }
  validates :middle_name, length: { maximum: 50 }
  validates :phone_number, presence: true, length: { maximum: 20 }
  validates :phone_number, format: { with: PHONE_FORMAT, message: 'can only contain digits, spaces and + - ( )' },
                           allow_blank: true
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, message: 'is not a valid email address' },
                    uniqueness: { case_sensitive: false, message: 'is already used by another member' },
                    allow_blank: true
  validates :place_of_residence, length: { maximum: 100 }
  validate :date_of_birth_is_valid
  validate :fellowship_groups_exist
  validate :linked_user_exists

  after_save :apply_fellowship_group_ids
  after_save :apply_user_link

  # Replaces the member's fellowship groups when the record is saved, in the same transaction.
  # Unknown ids become a validation error instead of raising ActiveRecord::RecordNotFound.
  def fellowship_group_ids=(ids)
    @pending_fellowship_group_ids = Array(ids).compact_blank.map(&:to_i).uniq
  end

  # Links a login account (users.member_id) when the record is saved, in the same transaction.
  # nil unlinks the current account. A member has at most one account, so linking a new one
  # unlinks the previous one. Never calling this leaves the link untouched.
  def user_id=(id)
    @user_link_requested = true
    @pending_user_id = id.presence&.to_i
  end

  # True when a user_id was assigned that differs from the currently linked account.
  def user_link_change?
    @user_link_requested == true && @pending_user_id != user&.id
  end

  # True when the requested account is already linked to a different member.
  def requested_user_linked_elsewhere?
    return false unless user_link_change? && @pending_user_id

    User.where(id: @pending_user_id).where.not(member_id: nil).where.not(member_id: id).exists?
  end

  private

  def normalize_strings
    STRING_ATTRIBUTES.each do |attribute|
      value = self[attribute]
      self[attribute] = value.strip.presence if value.is_a?(String)
    end
    self.email = email&.downcase
  end

  def date_of_birth_is_valid
    if date_of_birth.nil?
      errors.add(:date_of_birth, 'is not a valid date') if date_of_birth_before_type_cast.present?
    elsif date_of_birth > Date.current
      errors.add(:date_of_birth, "can't be in the future")
    end
  end

  def fellowship_groups_exist
    return if @pending_fellowship_group_ids.blank?

    missing = @pending_fellowship_group_ids - FellowshipGroup.where(id: @pending_fellowship_group_ids).pluck(:id)
    return if missing.empty?

    errors.add(:base, "Fellowship group not found (id #{missing.join(', ')})")
  end

  def apply_fellowship_group_ids
    return if @pending_fellowship_group_ids.nil?

    self.fellowship_groups = FellowshipGroup.where(id: @pending_fellowship_group_ids)
    # A leader must belong to their group, so leaving a group also gives up leading it.
    FellowshipGroup.where(leader_member_id: id).where.not(id: @pending_fellowship_group_ids)
      .update_all(leader_member_id: nil, updated_at: Time.current)
    @pending_fellowship_group_ids = nil
  end

  def linked_user_exists
    return unless user_link_change? && @pending_user_id
    return if User.exists?(@pending_user_id)

    errors.add(:base, 'Login account not found')
  end

  def apply_user_link
    return unless user_link_change?

    User.where(member_id: id).where.not(id: @pending_user_id).find_each { |old| old.update!(member_id: nil) }
    User.find(@pending_user_id).update!(member_id: id) if @pending_user_id
    @user_link_requested = false
    association(:user).reset
  end
end
