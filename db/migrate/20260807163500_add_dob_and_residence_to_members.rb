class AddDobAndResidenceToMembers < ActiveRecord::Migration[7.0]
  def change
    add_column :members, :date_of_birth, :date
    add_column :members, :place_of_residence, :string
  end
end
