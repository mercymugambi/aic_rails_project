# JSON shape of a user returned by the API (login, /users, /users/me).
# The frontend uses `super_admin` and `permissions` to decide which pages and buttons to show.
#
# Preload `roles: :permissions` and `member` when serializing many users to avoid N+1 queries.
class UserSerializer
  def initialize(user)
    @user = user
  end

  def as_json(*)
    {
      id: user.id,
      email: user.email,
      firstname: user.firstname,
      lastname: user.lastname,
      super_admin: user.super_admin,
      roles: user.roles.map(&:name),
      permissions: permission_names,
      member: member_json
    }
  end

  private

  attr_reader :user

  def permission_names
    return Permission.order(:id).pluck(:name) if user.super_admin?

    user.roles.flat_map(&:permissions).map(&:name).uniq
  end

  def member_json
    member = user.member
    return unless member

    {
      id: member.id,
      first_name: member.first_name,
      last_name: member.last_name,
      phone_number: member.phone_number,
      date_of_birth: member.date_of_birth,
      place_of_residence: member.place_of_residence
    }
  end
end
