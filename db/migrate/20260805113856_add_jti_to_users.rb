class AddJtiToUsers < ActiveRecord::Migration[7.0]
  def change
    add_column :users, :jti, :string
    # Populate jti for existing users
    reversible do |dir|
      dir.up do
        User.reset_column_information
        User.find_each do |user|
          user.update_column(:jti, SecureRandom.uuid)
        end
      end
    end
    change_column_null :users, :jti, false
    add_index :users, :jti, unique: true
  end
end
