class CreateEventRegistrations < ActiveRecord::Migration[7.0]
  def change
    create_table :event_registrations do |t|
      t.references :event, null: false, foreign_key: { on_delete: :cascade }
      t.string :name, null: false
      t.string :phone
      t.string :email
      t.integer :seats, null: false, default: 1
      # Normalised phone and email, so a person signs up once per event (see EventRegistration).
      t.string :phone_key
      t.string :email_key

      t.timestamps
    end

    add_index :event_registrations, %i[event_id phone_key], unique: true, where: 'phone_key IS NOT NULL'
    add_index :event_registrations, %i[event_id email_key], unique: true, where: 'email_key IS NOT NULL'
  end
end
