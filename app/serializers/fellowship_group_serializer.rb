# JSON shape of a fellowship group returned by the Fellowship Groups API.
#
# Use FellowshipGroupSerializer.many for lists: it counts members for all groups in one query.
# Preload :leader when serializing many groups.
class FellowshipGroupSerializer
  def self.many(groups)
    counts = FellowshipGroup.joins(:members).where(id: groups.map(&:id)).group(:id).count
    groups.map { |group| new(group, member_count: counts.fetch(group.id, 0)).as_json }
  end

  def initialize(group, member_count: nil, include_members: false)
    @group = group
    @member_count = member_count
    @include_members = include_members
  end

  def as_json(*)
    json = {
      id: group.id,
      group_name: group.group_name,
      group_code: group.group_code,
      description: group.description,
      leader: leader_json,
      member_count: @member_count || group.members.count,
      created_at: group.created_at,
      updated_at: group.updated_at
    }
    json[:members] = members_json if @include_members
    json
  end

  private

  attr_reader :group

  def leader_json
    leader = group.leader
    return unless leader

    { id: leader.id, first_name: leader.first_name, last_name: leader.last_name }
  end

  def members_json
    group.members.order(:first_name, :last_name, :id).map do |member|
      { id: member.id, first_name: member.first_name, last_name: member.last_name, phone_number: member.phone_number }
    end
  end
end
