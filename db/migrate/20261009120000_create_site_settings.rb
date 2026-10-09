class CreateSiteSettings < ActiveRecord::Migration[7.0]
  def change
    # Settings shown across the public website, as one JSON document (see SiteSettingsDocument).
    create_table :site_settings do |t|
      t.jsonb :data, null: false, default: {}
      t.references :updated_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    # One row for the whole site: a unique index on a constant allows only one.
    add_index :site_settings, '(true)', unique: true, name: 'index_site_settings_singleton'
  end
end
