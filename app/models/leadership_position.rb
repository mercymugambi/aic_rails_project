class LeadershipPosition < ApplicationRecord
  CODE_FORMAT = /\A[A-Z0-9-]+\z/

  belongs_to :created_by, class_name: 'User', optional: true
  has_and_belongs_to_many :members, join_table: 'members_leadership_positions'

  before_validation :normalize_fields

  validates :position_name, presence: true, length: { maximum: 80 }, uniqueness: { case_sensitive: false }
  validates :position_code, length: { maximum: 15 },
                            format: { with: CODE_FORMAT, message: 'can only contain letters A-Z, numbers and -' },
                            uniqueness: { case_sensitive: false },
                            allow_nil: true
  validates :description, length: { maximum: 500 }, allow_nil: true
  validate :holder_member_exists

  after_save :apply_holder_member

  def holder
    members.first
  end

  def member_id
    holder&.id
  end

  def member_id=(id)
    @member_assignment_requested = true
    @pending_member_id = id.presence&.to_i
  end

  private

  def normalize_fields
    self.position_name = position_name.strip if position_name.is_a?(String)
    self.position_code = position_code.strip.upcase.presence if position_code.is_a?(String)
    self.description = description.strip.presence if description.is_a?(String)
  end

  def holder_member_exists
    return unless @member_assignment_requested && @pending_member_id
    return if Member.exists?(@pending_member_id)

    errors.add(:base, 'Selected member does not exist in the directory')
  end

  def apply_holder_member
    return unless @member_assignment_requested

    self.members = @pending_member_id ? [Member.find(@pending_member_id)] : []
    @member_assignment_requested = false
  end
end
