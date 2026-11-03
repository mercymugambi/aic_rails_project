class User < ApplicationRecord
  # JWT revocation: each user's `jti` is rotated on logout, invalidating issued tokens.
  include Devise::JWT::RevocationStrategies::JTIMatcher

  # No :registerable - accounts are created only by the super admin (POST /api/v1/users).
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  # Optional link to the congregation record of the person using this account.
  belongs_to :member, optional: true
  has_many :leadership_positions, through: :member
  has_many :created_fellowship_groups, class_name: 'FellowshipGroup', foreign_key: 'created_by_id'
  has_many :created_events, class_name: 'Event', foreign_key: 'created_by_id'
  has_many :created_devotions, class_name: 'Devotion', foreign_key: 'created_by_id'

  # RBAC associations
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :assigned_roles, class_name: 'UserRole', foreign_key: 'assigned_by_id'

  # Check if user has a specific permission (through any of their roles)
  def has_permission?(permission_name)
    return true if super_admin?

    roles.joins(:permissions).where(permissions: { name: permission_name }).exists?
  end

  # Check if user has a specific role
  def has_role?(role_name)
    return true if role_name.to_s == 'super_admin' && super_admin?

    roles.where(name: role_name).exists?
  end

  # Check if user is a church admin
  def church_admin?
    has_role?('church_admin')
  end

  # Check if user can assign roles
  def can_assign_roles?
    super_admin? || church_admin?
  end

  # All permissions for this user (aggregated from all roles)
  def all_permissions
    return Permission.all if super_admin?

    Permission.joins(roles: :users).where(users: { id: id }).distinct
  end
end
