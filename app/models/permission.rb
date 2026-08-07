class Permission < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  has_many :role_permissions, dependent: :destroy
  has_many :roles, through: :role_permissions
end
