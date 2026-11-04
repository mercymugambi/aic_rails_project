class AddMustChangePasswordAndUniquePositionHolder < ActiveRecord::Migration[7.0]
  def up
    add_column :users, :must_change_password, :boolean, default: false, null: false unless column_exists?(:users, :must_change_password)

    # Ensure each leadership position is held by at most one member before adding a unique index
    execute <<~SQL.squish
      DELETE FROM members_leadership_positions a
      USING members_leadership_positions b
      WHERE a.ctid < b.ctid
        AND a.leadership_position_id = b.leadership_position_id;
    SQL

    return if index_exists?(:members_leadership_positions, :leadership_position_id, name: 'index_unique_holder_per_leadership_position')

    add_index :members_leadership_positions,
              :leadership_position_id,
              unique: true,
              name: 'index_unique_holder_per_leadership_position'
  end

  def down
    remove_index :members_leadership_positions, name: 'index_unique_holder_per_leadership_position' if index_exists?(:members_leadership_positions, :leadership_position_id, name: 'index_unique_holder_per_leadership_position')
    remove_column :users, :must_change_password if column_exists?(:users, :must_change_password)
  end
end

