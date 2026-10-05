class CreateGalleryImages < ActiveRecord::Migration[7.0]
  def change
    create_table :gallery_images do |t|
      t.string :title, limit: 150
      t.string :category
      t.date :taken_on
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :gallery_images, :category
    add_index :gallery_images, :taken_on
  end
end
