# A member can belong to several fellowship groups, but only once to each.
class AddUniqueIndexToFellowshipGroupsMembers < ActiveRecord::Migration[7.0]
  INDEX_NAME = 'index_fg_members_on_member_id_and_fg_id'.freeze

  def up
    # Duplicate links would stop the unique index from being created, so remove them first.
    removed = exec_delete(<<~SQL.squish)
      DELETE FROM fellowship_groups_members a
      USING fellowship_groups_members b
      WHERE a.ctid < b.ctid
        AND a.member_id = b.member_id
        AND a.fellowship_group_id = b.fellowship_group_id
    SQL
    say "Removed #{removed} duplicate member/fellowship-group link(s)"

    remove_index :fellowship_groups_members, name: INDEX_NAME
    add_index :fellowship_groups_members, %i[member_id fellowship_group_id], unique: true, name: INDEX_NAME
  end

  def down
    remove_index :fellowship_groups_members, name: INDEX_NAME
    add_index :fellowship_groups_members, %i[member_id fellowship_group_id], name: INDEX_NAME
  end
end
