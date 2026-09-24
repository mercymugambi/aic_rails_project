# One-way data fix: blank group codes become NULL, so the unique index on group_code
# doesn't treat two groups without a code as duplicates. Rolling back changes nothing.
class NullifyBlankFellowshipGroupCodes < ActiveRecord::Migration[7.0]
  def up
    fixed = exec_update("UPDATE fellowship_groups SET group_code = NULL WHERE btrim(group_code) = ''")
    say "Set #{fixed} blank group_code value(s) to NULL"
  end

  def down
    say 'Blank group codes stay NULL.'
  end
end
