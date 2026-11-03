# The church no longer records baptism, and fellowship groups now live only in the
# fellowship_groups_members join table (copied over by LinkMembersToFellowshipGroups).
# Rolling back restores both columns, empty.
class RemoveBaptisedAndFellowshipGroupFromMembers < ActiveRecord::Migration[7.0]
  def change
    reversible do |dir|
      dir.up do
        count = select_value('SELECT COUNT(*) FROM members WHERE baptised IS NOT NULL')
        say "Dropping members.baptised: #{count} non-NULL value(s) will be lost"
      end
    end

    remove_column :members, :baptised, :boolean
    remove_column :members, :fellowship_group, :string
  end
end
