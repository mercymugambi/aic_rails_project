class CreateAppointments < ActiveRecord::Migration[7.0]
  def change
    create_table :appointments do |t|
      t.string :name
      t.string :email
      t.string :phone
      t.string :purpose
      t.text :notes
      t.date :appointment_date
      t.string :appointment_time
      t.string :status
      t.string :token
      t.text :reschedule_note
      t.string :pastor_email

      t.timestamps
    end
  end
end
