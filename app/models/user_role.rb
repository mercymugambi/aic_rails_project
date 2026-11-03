class UserRole < ApplicationRecord
  belongs_to :user
  belongs_to :role
  belongs_to :assigned_by, class_name: 'User', optional: true

  validates :role_id, uniqueness: { scope: :user_id, message: 'has already been assigned to this user' }
end
