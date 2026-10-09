# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.0].define(version: 2026_10_09_090100) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "blog_post_images", force: :cascade do |t|
    t.string "token", null: false
    t.bigint "blog_post_id"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["blog_post_id"], name: "index_blog_post_images_on_blog_post_id"
    t.index ["created_at"], name: "index_blog_post_images_on_created_at"
    t.index ["created_by_id"], name: "index_blog_post_images_on_created_by_id"
    t.index ["token"], name: "index_blog_post_images_on_token", unique: true
  end

  create_table "blog_posts", force: :cascade do |t|
    t.string "title", limit: 150, null: false
    t.string "slug", limit: 80, null: false
    t.text "excerpt"
    t.jsonb "body", default: [], null: false
    t.string "category"
    t.string "tags", default: [], null: false, array: true
    t.string "status", default: "published", null: false
    t.boolean "featured", default: false, null: false
    t.date "published_on"
    t.string "author_name"
    t.string "author_role"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_blog_posts_on_created_by_id"
    t.index ["featured"], name: "index_blog_posts_on_single_featured", unique: true, where: "featured"
    t.index ["slug"], name: "index_blog_posts_on_slug", unique: true
    t.index ["status", "published_on"], name: "index_blog_posts_on_status_and_published_on"
  end

  create_table "devotions", force: :cascade do |t|
    t.string "title"
    t.text "content"
    t.date "date"
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_devotions_on_created_by_id"
  end

  create_table "event_registrations", force: :cascade do |t|
    t.bigint "event_id", null: false
    t.string "name", null: false
    t.string "phone"
    t.string "email"
    t.integer "seats", default: 1, null: false
    t.string "phone_key"
    t.string "email_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["event_id", "email_key"], name: "index_event_registrations_on_event_id_and_email_key", unique: true, where: "(email_key IS NOT NULL)"
    t.index ["event_id", "phone_key"], name: "index_event_registrations_on_event_id_and_phone_key", unique: true, where: "(phone_key IS NOT NULL)"
    t.index ["event_id"], name: "index_event_registrations_on_event_id"
  end

  create_table "events", force: :cascade do |t|
    t.string "title"
    t.text "description"
    t.date "date"
    t.bigint "created_by_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "category"
    t.string "status", default: "published", null: false
    t.boolean "featured", default: false, null: false
    t.date "end_date"
    t.time "start_time"
    t.time "end_time"
    t.string "location"
    t.string "speaker"
    t.string "speaker_role"
    t.string "audience"
    t.string "registration", default: "none", null: false
    t.string "registration_url"
    t.integer "capacity"
    t.integer "registrations_count", default: 0, null: false
    t.integer "seats_taken", default: 0, null: false
    t.index ["created_by_id"], name: "index_events_on_created_by_id"
    t.index ["featured"], name: "index_events_on_single_featured", unique: true, where: "featured"
    t.index ["status", "date"], name: "index_events_on_status_and_date"
  end

  create_table "fellowship_groups", force: :cascade do |t|
    t.string "group_name"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "group_code"
    t.text "description"
    t.bigint "leader_member_id"
    t.index "lower((group_name)::text)", name: "index_fellowship_groups_on_lower_group_name", unique: true
    t.index ["created_by_id"], name: "index_fellowship_groups_on_created_by_id"
    t.index ["group_code"], name: "index_fellowship_groups_on_group_code", unique: true
    t.index ["leader_member_id"], name: "index_fellowship_groups_on_leader_member_id"
  end

  create_table "fellowship_groups_members", id: false, force: :cascade do |t|
    t.bigint "fellowship_group_id", null: false
    t.bigint "member_id", null: false
    t.index ["fellowship_group_id", "member_id"], name: "index_fg_members_on_fg_id_and_member_id"
    t.index ["member_id", "fellowship_group_id"], name: "index_fg_members_on_member_id_and_fg_id", unique: true
  end

  create_table "gallery_images", force: :cascade do |t|
    t.string "title", limit: 150
    t.string "category"
    t.date "taken_on"
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["category"], name: "index_gallery_images_on_category"
    t.index ["created_by_id"], name: "index_gallery_images_on_created_by_id"
    t.index ["taken_on"], name: "index_gallery_images_on_taken_on"
  end

  create_table "leadership_positions", force: :cascade do |t|
    t.string "position_name"
    t.text "description"
    t.string "position_code"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "created_by_id"
    t.index ["created_by_id"], name: "index_leadership_positions_on_created_by_id"
    t.index ["position_code"], name: "index_leadership_positions_on_position_code", unique: true
  end

  create_table "members", force: :cascade do |t|
    t.string "first_name"
    t.string "middle_name"
    t.string "last_name"
    t.string "phone_number"
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.date "date_of_birth"
    t.string "place_of_residence"
  end

  create_table "members_leadership_positions", id: false, force: :cascade do |t|
    t.bigint "member_id"
    t.bigint "leadership_position_id"
    t.index ["member_id", "leadership_position_id"], name: "index_member_positions", unique: true
  end

  create_table "permissions", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_permissions_on_name", unique: true
  end

  create_table "role_permissions", force: :cascade do |t|
    t.bigint "role_id", null: false
    t.bigint "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "user_roles", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "role_id", null: false
    t.bigint "assigned_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "firstname"
    t.string "lastname"
    t.bigint "member_id"
    t.boolean "super_admin", default: false
    t.string "jti", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "blog_post_images", "blog_posts", on_delete: :nullify
  add_foreign_key "blog_post_images", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "blog_posts", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "devotions", "users", column: "created_by_id"
  add_foreign_key "event_registrations", "events", on_delete: :cascade
  add_foreign_key "events", "users", column: "created_by_id"
  add_foreign_key "fellowship_groups", "members", column: "leader_member_id", on_delete: :nullify
  add_foreign_key "fellowship_groups", "users", column: "created_by_id"
  add_foreign_key "gallery_images", "users", column: "created_by_id", on_delete: :nullify
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "user_roles", "users", column: "assigned_by_id"
  add_foreign_key "users", "members", on_delete: :nullify
end
