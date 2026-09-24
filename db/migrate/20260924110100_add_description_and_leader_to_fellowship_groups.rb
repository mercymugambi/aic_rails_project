# Deleting a member who leads a group leaves the group without a leader (ON DELETE SET NULL).
class AddDescriptionAndLeaderToFellowshipGroups < ActiveRecord::Migration[7.0]
  def change
    add_column :fellowship_groups, :description, :text
    add_reference :fellowship_groups, :leader_member, index: true,
                                                      foreign_key: { to_table: :members, on_delete: :nullify }
  end
end
