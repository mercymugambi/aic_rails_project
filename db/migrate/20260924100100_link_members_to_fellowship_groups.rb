# One-way data migration: copies the free-text members.fellowship_group into the
# fellowship_groups_members join table before that column is dropped.
#
# Groups are matched on group_name (trimmed, case-insensitive). No groups are created;
# strings that match no group are listed in the migration output and the log.
# Rolling back keeps the links, because they can't be told apart from links made later.
class LinkMembersToFellowshipGroups < ActiveRecord::Migration[7.0]
  def up
    groups = group_ids_by_name
    unmatched = Hash.new(0)
    linked = 0

    members_with_group_text.each do |member_id, text|
      group_id = groups[normalize(text)]
      if group_id
        linked += link(member_id, group_id)
      else
        unmatched[text.strip] += 1
      end
    end

    report(linked, unmatched)
  end

  def down
    say 'Fellowship-group links created by this migration are kept.'
  end

  private

  def normalize(name)
    name.to_s.strip.downcase
  end

  # When several groups share a name, the oldest one (lowest id) is used.
  def group_ids_by_name
    select_rows('SELECT id, group_name FROM fellowship_groups ORDER BY id').each_with_object({}) do |(id, name), map|
      map[normalize(name)] ||= id.to_i if name.present?
    end
  end

  def members_with_group_text
    select_rows("SELECT id, fellowship_group FROM members WHERE btrim(COALESCE(fellowship_group, '')) <> '' ORDER BY id")
  end

  # Returns 1 if a link was added, 0 if it already existed.
  def link(member_id, group_id)
    exec_insert(<<~SQL.squish).rows.size
      INSERT INTO fellowship_groups_members (member_id, fellowship_group_id)
      SELECT #{member_id.to_i}, #{group_id.to_i}
      WHERE NOT EXISTS (
        SELECT 1 FROM fellowship_groups_members
        WHERE member_id = #{member_id.to_i} AND fellowship_group_id = #{group_id.to_i}
      )
      RETURNING member_id
    SQL
  end

  def report(linked, unmatched)
    say "Linked #{linked} member(s) to a fellowship group from the fellowship_group text"
    if unmatched.empty?
      say 'No unmatched fellowship_group text'
    else
      say "#{unmatched.values.sum} member(s) had fellowship_group text matching no group:"
      unmatched.sort.each do |text, count|
        say "  #{text.inspect}: #{count} member(s)", true
        Rails.logger.warn("[LinkMembersToFellowshipGroups] unmatched #{text.inspect}: #{count} member(s)")
      end
    end
  end
end
