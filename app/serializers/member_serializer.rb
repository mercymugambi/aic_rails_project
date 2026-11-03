# JSON shape of a member returned by the Members API.
#
# Preload PRELOAD when serializing many members to avoid N+1 queries.
class MemberSerializer
  PRELOAD = [:fellowship_groups, :leadership_positions, { user: :roles }].freeze

  def initialize(member)
    @member = member
  end

  def as_json(*)
    {
      id: member.id,
      first_name: member.first_name,
      middle_name: member.middle_name,
      last_name: member.last_name,
      phone_number: member.phone_number,
      email: member.email,
      date_of_birth: member.date_of_birth,
      place_of_residence: member.place_of_residence,
      fellowship_groups: member.fellowship_groups.sort_by(&:id).map { |g| { id: g.id, group_name: g.group_name } },
      leadership_positions: member.leadership_positions.sort_by(&:id).map do |p|
        { id: p.id, position_name: p.position_name }
      end,
      user: user_json,
      created_at: member.created_at,
      updated_at: member.updated_at
    }
  end

  private

  attr_reader :member

  def user_json
    user = member.user
    return unless user

    { id: user.id, email: user.email, super_admin: user.super_admin, roles: user.roles.map(&:name) }
  end
end
