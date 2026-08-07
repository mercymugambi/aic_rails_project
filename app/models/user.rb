class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  include Devise::JWT::RevocationStrategies::JTIMatcher

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :jwt_authenticatable, jwt_revocation_strategy: self

  belongs_to :member, optional: true # Allow member to be optional
  has_many :devotions
  has_and_belongs_to_many :leadership_positions, through: :member
  has_many :created_fellowship_groups, class_name: 'FellowshipGroup', foreign_key: 'created_by_id'
  has_many :created_events, class_name: 'Event', foreign_key: 'created_by_id'
  has_many :created_devotions, class_name: 'Devotion', foreign_key: 'created_by_id'

  # RBAC associations
  has_many :user_roles, dependent: :destroy
  has_many :roles, through: :user_roles
  has_many :assigned_roles, class_name: 'UserRole', foreign_key: 'assigned_by_id'

  # Define the check_leadership_position method to validate presence of leadership_position
  validate :check_leadership_position

  #  validate :super_admin_without_member and leadership_role
  def check_leadership_position
    return unless !super_admin? && (member.nil? || member.leadership_positions.empty?)

    errors.add(:base, 'User must have a leadership position and be a member')
  end

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
