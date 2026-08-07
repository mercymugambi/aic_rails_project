class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :assigned_by, class_name: 'User', optional: true

  validates :role_id, uniqueness: { scope: :user_id, message: 'has already been assigned to this user' }
  validate :user_must_be_eligible_member

  private

  # User must be linked to a member who has at least one leadership position
  def user_must_be_eligible_member
    return if user&.super_admin?

    if user&.member.nil?
      errors.add(:user, 'must be linked to a member')
    elsif user.member.leadership_positions.empty?
      errors.add(:user, 'must have a leadership position to be assigned a system role')
    end
  end
end
