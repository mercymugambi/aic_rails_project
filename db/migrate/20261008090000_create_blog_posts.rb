class CreateBlogPosts < ActiveRecord::Migration[7.0]
  def change
    create_table :blog_posts do |t|
      t.string :title, null: false, limit: 150
      t.string :slug, null: false, limit: 80
      t.text :excerpt
      t.jsonb :body, null: false, default: []
      t.string :category
      t.string :tags, array: true, null: false, default: []
      t.string :status, null: false, default: 'published'
      t.boolean :featured, null: false, default: false
      t.date :published_on
      t.string :author_name
      t.string :author_role
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :blog_posts, :slug, unique: true
    add_index :blog_posts, %i[status published_on]
    # At most one featured post; the model clears the old one before setting a new one.
    add_index :blog_posts, :featured, unique: true, where: 'featured', name: 'index_blog_posts_on_single_featured'

    # Photos placed inside a post's body. Uploaded before the post is saved, so blog_post_id is null
    # until a post that references the photo is saved (see BlogPostImage.purge_orphans).
    create_table :blog_post_images do |t|
      t.string :token, null: false
      t.references :blog_post, foreign_key: { on_delete: :nullify }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }

      t.timestamps
    end

    add_index :blog_post_images, :token, unique: true
    add_index :blog_post_images, :created_at
  end
end
