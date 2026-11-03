# Group names are unique regardless of case. Existing names that differ only in case must be
# renamed or merged by hand first, so this migration stops and lists them instead of guessing.
class AddUniqueLowerGroupNameIndexToFellowshipGroups < ActiveRecord::Migration[7.0]
  INDEX_NAME = 'index_fellowship_groups_on_lower_group_name'.freeze

  def up
    duplicates = select_rows(<<~SQL.squish)
      SELECT string_agg(id::text || ' ' || quote_literal(group_name), ', ' ORDER BY id)
      FROM fellowship_groups
      WHERE group_name IS NOT NULL
      GROUP BY lower(group_name)
      HAVING COUNT(*) > 1
    SQL

    if duplicates.any?
      raise "Fellowship group names differ only in case; rename or merge them, then re-run: #{duplicates.join(' | ')}"
    end

    say 'No case-insensitive duplicate group names'
    add_index :fellowship_groups, 'lower(group_name)', unique: true, name: INDEX_NAME
  end

  def down
    remove_index :fellowship_groups, name: INDEX_NAME
  end
end
