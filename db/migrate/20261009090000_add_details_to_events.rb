class AddDetailsToEvents < ActiveRecord::Migration[7.0]
  def change
    # events.image (a pasted link) is replaced by an uploaded cover photo. Stop rather than lose links.
    reversible do |direction|
      direction.up do
        linked = select_value("SELECT COUNT(*) FROM events WHERE COALESCE(TRIM(image), '') <> ''").to_i
        if linked.positive?
          raise "#{linked} event(s) still have a link in events.image, which this migration drops. " \
                'Copy those links somewhere first, or clear them if they are not needed, then migrate again.'
        end
      end
    end

    change_table :events, bulk: true do |t|
      t.string :category
      # Existing rows become published.
      t.string :status, null: false, default: 'published'
      t.boolean :featured, null: false, default: false
      t.date :end_date
      t.time :start_time
      t.time :end_time
      t.string :location
      t.string :speaker
      t.string :speaker_role
      t.string :audience
      t.string :registration, null: false, default: 'none'
      t.string :registration_url
      t.integer :capacity
      t.integer :registrations_count, null: false, default: 0
      t.integer :seats_taken, null: false, default: 0
    end

    remove_column :events, :image, :string

    add_index :events, %i[status date]
    # At most one featured event; the model clears the old one before setting a new one.
    add_index :events, :featured, unique: true, where: 'featured', name: 'index_events_on_single_featured'
  end
end
