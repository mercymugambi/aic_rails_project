class CreateUserRoles < ActiveRecord::Migration[7.0]
  def change
    create_table :user_roles do |t|
      t.references :user, null: false, foreign_key: true
      t.references :role, null: false, foreign_key: true
      t.bigint :assigned_by_id

      t.timestamps
    end
    add_index :user_roles, [:user_id, :role_id], unique: true
    add_foreign_key :user_roles, :users, column: :assigned_by_id
  end
end
