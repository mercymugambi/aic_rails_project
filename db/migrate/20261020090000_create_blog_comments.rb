class CreateBlogComments < ActiveRecord::Migration[7.0]
  def change
    create_table :blog_comments do |t|
      # Indexed below, as the first column of [blog_post_id, status, created_at].
      t.references :blog_post, null: false, index: false, foreign_key: { on_delete: :cascade }
      t.string :author_name, null: false, limit: 80
      t.string :author_email, limit: 254
      t.text :body, null: false
      t.string :status, null: false, default: 'pending'
      # The church's public reply (see BlogComment#reply_with).
      t.text :reply_body
      t.string :reply_author_name
      t.datetime :replied_at
      t.references :replied_by, foreign_key: { to_table: :users, on_delete: :nullify }
      # For spam review only; never serialized.
      t.string :ip_address

      t.timestamps
    end

    add_index :blog_comments, %i[blog_post_id status created_at]
    add_index :blog_comments, :status
  end
end
