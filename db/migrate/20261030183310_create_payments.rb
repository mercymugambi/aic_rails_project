class CreatePayments < ActiveRecord::Migration[7.0]
  def change
    create_table :payments do |t|
      t.string  :phone_number,    null: false
      t.decimal :amount,          null: false, precision: 10, scale: 2
      t.string  :transaction_id
      t.string  :merchant_request_id
      t.string  :checkout_request_id
      t.string  :contribution_type, null: false, default: 'donation'
      t.string  :status,            null: false, default: 'pending'
      t.text    :result_description

      t.timestamps
    end

    add_index :payments, :transaction_id, unique: true, where: "transaction_id IS NOT NULL"
    add_index :payments, :checkout_request_id
    add_index :payments, :status
    add_index :payments, :contribution_type
  end
end
