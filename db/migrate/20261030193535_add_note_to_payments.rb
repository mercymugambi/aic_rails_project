class AddNoteToPayments < ActiveRecord::Migration[7.0]
  def change
    add_column :payments, :note, :string
    add_index :payments, :transaction_id unless index_exists?(:payments, :transaction_id)
  end
end