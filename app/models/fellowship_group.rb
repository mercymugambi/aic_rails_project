class FellowshipGroup < ApplicationRecord
  CODE_FORMAT = /\A[A-Z0-9-]+\z/

  belongs_to :created_by, class_name: 'User'
  # The leader is always kept in the group: see add_leader_to_group and Member#apply_fellowship_group_ids.
  belongs_to :leader, class_name: 'Member', foreign_key: :leader_member_id, optional: true, inverse_of: false
  has_and_belongs_to_many :members

  before_validation :normalize_fields

  validates :group_name, presence: true, length: { maximum: 60 }, uniqueness: { case_sensitive: false }
  validates :group_code, length: { maximum: 10 },
                         format: { with: CODE_FORMAT, message: 'can only contain letters A-Z, numbers and -' },
                         uniqueness: true, allow_nil: true
  validates :description, length: { maximum: 500 }
  validate :leader_is_a_member

  after_save :add_leader_to_group

  private

  def normalize_fields
    self.group_name = group_name.strip if group_name.is_a?(String)
    self.group_code = group_code.strip.upcase.presence if group_code.is_a?(String)
    self.description = description.strip.presence if description.is_a?(String)
  end

  def leader_is_a_member
    return if leader_member_id.nil? || Member.exists?(leader_member_id)

    errors.add(:base, 'Leader must be a member in the directory')
  end

  def add_leader_to_group
    return if leader_member_id.nil? || members.exists?(leader_member_id)

    members << Member.find(leader_member_id)
  end
end
