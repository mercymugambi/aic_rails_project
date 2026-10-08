require 'test_helper'
require 'minitest/mock'

class Api::V1::BlogPostsControllerTest < ActionDispatch::IntegrationTest
  ITEM_KEYS = %w[id slug title excerpt body category tags status featured published_on author_name author_role
                 cover_image_url read_minutes created_at updated_at].freeze
  BODY = [{ 'type' => 'paragraph', 'text' => 'Be strong and courageous.' }].freeze

  setup do
    @editor = users(:blog_editor) # manage_blog only
    @treasurer = users(:treasurer) # no manage_blog
  end

  # --- Index ---

  test 'index is public and lists only published posts, newest first, as a bare array' do
    older = create_post(title: 'Older', published_on: '2026-06-01')
    same_day = create_post(title: 'Same day', published_on: '2026-08-04', created_at: 1.day.ago)
    newest = create_post(title: 'Newest', published_on: '2026-08-04')
    create_post(title: 'Draft', status: 'draft')

    get '/api/v1/blog_posts', as: :json

    assert_response :ok
    assert_kind_of Array, response.parsed_body
    assert_equal [newest, same_day, older].map(&:id), response.parsed_body.pluck('id')
  end

  test 'items have the documented shape' do
    post = create_post(title: 'Hope', tags: ['Hope'], author_name: 'Pst. Jane', author_role: 'Youth Pastor',
                       body: [{ 'type' => 'paragraph', 'text' => 'word ' * 800 }])

    get '/api/v1/blog_posts', as: :json

    item = response.parsed_body.first
    assert_equal ITEM_KEYS, item.keys
    assert_equal({ 'id' => post.id, 'slug' => 'hope', 'title' => 'Hope', 'excerpt' => 'A word of hope.',
                   'category' => 'Youth', 'tags' => ['Hope'], 'status' => 'published', 'featured' => false,
                   'published_on' => '2026-08-04', 'author_name' => 'Pst. Jane', 'author_role' => 'Youth Pastor',
                   'cover_image_url' => nil, 'read_minutes' => 4 }, item.except('body', 'created_at', 'updated_at'))
  end

  test 'status=all includes drafts for manage_blog' do
    published = create_post
    draft = create_post(title: 'Draft', status: 'draft')

    get '/api/v1/blog_posts', params: { status: 'all' }, headers: auth_headers(@editor)

    assert_response :ok
    assert_equal [draft.id, published.id].sort, response.parsed_body.pluck('id').sort
  end

  test 'status=all needs login and manage_blog' do
    get '/api/v1/blog_posts', params: { status: 'all' }, headers: { 'Accept' => 'application/json' }
    assert_response :unauthorized

    get '/api/v1/blog_posts', params: { status: 'all' }, headers: auth_headers(@treasurer)
    assert_response :forbidden
    assert_equal({ 'error' => 'You do not have permission to perform this action' }, response.parsed_body)
  end

  test 'index loads covers and body photos without N+1 queries' do
    create_post(cover: true, body: [image_block(upload_image)])
    one_post = count_queries { get '/api/v1/blog_posts', as: :json }
    3.times { create_post(cover: true, body: [image_block(upload_image)]) }
    four_posts = count_queries { get '/api/v1/blog_posts', as: :json }

    assert_equal 4, response.parsed_body.size
    assert_equal one_post, four_posts
  end

  # --- Show ---

  test 'show finds a published post by slug' do
    post = create_post(title: 'Walking in faith')

    get '/api/v1/blog_posts/walking-in-faith', as: :json

    assert_response :ok
    assert_equal ITEM_KEYS, response.parsed_body.keys
    assert_equal post.id, response.parsed_body['id']
  end

  test 'show returns 404 for drafts, unknown slugs and numeric ids' do
    draft = create_post(title: 'Secret', status: 'draft')

    ['secret', 'no-such-post', draft.id.to_s].each do |slug|
      get "/api/v1/blog_posts/#{slug}", as: :json
      assert_response :not_found, slug
      assert_equal({ 'error' => 'Post not found' }, response.parsed_body)
    end
  end

  # --- Create ---

  test 'create accepts the multipart form the editor sends' do
    params = { title: "  God's Love ", slug: '', excerpt: 'A word of hope.', category: 'Family', status: 'published',
               published_on: '2026-08-04', author_name: '', author_role: 'Elder', featured: 'true',
               tags: ['Hope', ' hope', ''], body: BODY.to_json,
               cover_image: fixture_file_upload('photo.jpg', 'image/jpeg') }

    assert_difference -> { BlogPost.count } => 1, -> { ActiveStorage::Blob.count } => 1 do
      post '/api/v1/blog_posts', headers: auth_headers(@editor), params: { blog_post: params }
    end

    assert_response :created
    assert_equal 'Post saved', response.parsed_body['message']
    item = response.parsed_body['blog_post']
    assert_equal ITEM_KEYS, item.keys
    assert_equal ['gods-love', "God's Love", BODY, ['Hope'], true, nil, 'Elder'],
                 item.values_at('slug', 'title', 'body', 'tags', 'featured', 'author_name', 'author_role')
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/.+/photo\.jpg\z},
                 item['cover_image_url']
    created = BlogPost.find(item['id'])
    assert_equal @editor, created.created_by
    assert ActiveStorage::Blob.service.exist?(created.cover_image.key)
  end

  test 'create saves a draft with only a title; a single empty tag means no tags' do
    post '/api/v1/blog_posts', headers: auth_headers(@editor),
                               params: { blog_post: { title: 'Ideas', status: 'draft', body: '', tags: [''] } }

    assert_response :created
    assert_equal ['draft', [], [], nil], response.parsed_body['blog_post'].values_at('status', 'body', 'tags',
                                                                                     'published_on')
  end

  test 'create explains what a published post is missing' do
    assert_no_difference -> { BlogPost.count } do
      post '/api/v1/blog_posts', headers: auth_headers(@editor), params: { blog_post: { title: 'Hope', body: '[]' } }
    end

    assert_response :unprocessable_entity
    assert_equal ["Excerpt can't be blank", "Category can't be blank", "Publish date can't be blank",
                  "Content can't be blank"], response.parsed_body['errors']
  end

  test 'create rejects malformed body JSON' do
    post '/api/v1/blog_posts', headers: auth_headers(@editor),
                               params: { blog_post: { title: 'Hope', status: 'draft', body: '[{"type":' } }

    assert_response :unprocessable_entity
    assert_equal ['The post content could not be read. Please try saving again.'], response.parsed_body['errors']
  end

  test 'create rejects a bad cover image and keeps no file' do
    pdf = Rack::Test::UploadedFile.new(StringIO.new('%PDF-1.4 hello'), 'application/pdf', original_filename: 'a.pdf')

    assert_no_difference [-> { BlogPost.count }, -> { ActiveStorage::Blob.count }] do
      post '/api/v1/blog_posts', headers: auth_headers(@editor),
                                 params: { blog_post: { title: 'Hope', status: 'draft', cover_image: pdf } }
    end
    assert_response :unprocessable_entity
    assert_equal ['Cover image must be a JPG, PNG or WEBP file'], response.parsed_body['errors']
  end

  test 'a string cover_image is ignored' do
    post '/api/v1/blog_posts', headers: auth_headers(@editor),
                               params: { blog_post: { title: 'Hope', status: 'draft', cover_image: 'signed-blob-id' } }
    assert_response :created
    assert_nil response.parsed_body['blog_post']['cover_image_url']
  end

  test 'a failed cover upload leaves no post or file behind' do
    failing_upload = ->(*, **) { raise ActiveStorage::IntegrityError, 'Invalid api_key' }
    counts = [-> { BlogPost.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count }]

    assert_no_difference counts do
      ActiveStorage::Blob.service.stub(:upload, failing_upload) do
        post '/api/v1/blog_posts', headers: auth_headers(@editor),
                                   params: { blog_post: { title: 'Hope', status: 'draft',
                                                          cover_image: fixture_file_upload('photo.jpg') } }
      end
    end

    assert_response :bad_gateway
    assert_equal({ 'error' => "The photo couldn't be saved to storage. Please try again." }, response.parsed_body)
  end

  test 'create requires the blog_post key' do
    post '/api/v1/blog_posts', headers: auth_headers(@editor), params: { title: 'x' }
    assert_response :bad_request
    assert_equal({ 'error' => 'Send the post details under a "blog_post" key' }, response.parsed_body)
  end

  # --- Body photos ---

  test 'photos in the body are attached on save and get a fresh url on every read' do
    image = upload_image
    body = [*BODY, { 'type' => 'image', 'image_id' => image.token, 'url' => 'https://evil.example/x.jpg',
                     'caption' => 'Choir', 'onclick' => 'x' }]

    post '/api/v1/blog_posts', headers: auth_headers(@editor),
                               params: { blog_post: post_fields.merge(body: body.to_json) }

    assert_response :created
    block = response.parsed_body['blog_post']['body'].last
    assert_equal %w[type image_id url caption], block.keys
    assert_equal image.token, block['image_id']
    assert_equal BlogPostSerializer.image_url(image.image), block['url']
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/}, block['url']
    assert_equal response.parsed_body['blog_post']['id'], image.reload.blog_post_id
  end

  test 'a forged image_id is rejected' do
    body = [{ 'type' => 'image', 'image_id' => 'made-up', 'url' => 'https://evil.example/x.jpg' }]

    post '/api/v1/blog_posts', headers: auth_headers(@editor),
                               params: { blog_post: post_fields.merge(body: body.to_json) }

    assert_response :unprocessable_entity
    assert_equal ["A photo in the post wasn't uploaded properly. Please insert it again."],
                 response.parsed_body['errors']
  end

  test 'removing a photo from the body deletes it after the update' do
    kept = upload_image
    removed = upload_image
    blog_post = create_post(body: [image_block(kept), image_block(removed)])

    patch "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor), as: :json,
                                                params: { blog_post: { body: [image_block(kept)] } }

    assert_response :ok
    assert_equal [kept.token], response.parsed_body['blog_post']['body'].pluck('image_id')
    assert BlogPostImage.exists?(kept.id)
    assert_not BlogPostImage.exists?(removed.id)
    assert_not ActiveStorage::Blob.service.exist?(removed.image.key)
  end

  # --- Update ---

  test 'a JSON update with only featured changes nothing else and unfeatures the old post' do
    old = create_post(title: 'Old', featured: true)
    blog_post = create_post(title: 'New', tags: ['Hope'])

    patch "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor), as: :json,
                                                params: { blog_post: { featured: true } }

    assert_response :ok
    assert_equal 'Post updated', response.parsed_body['message']
    item = response.parsed_body['blog_post']
    assert_equal [true, 'New', 'new', ['Hope'], BODY], item.values_at('featured', 'title', 'slug', 'tags', 'body')
    assert_not old.reload.featured
  end

  test 'a multipart update keeps the slug when the title changes' do
    blog_post = create_post(title: 'Hope')

    patch "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor),
                                                params: { blog_post: post_fields.merge(title: 'Renewed hope', slug: '',
                                                                                       featured: 'false') }

    assert_response :ok
    assert_equal ['Renewed hope', 'hope'], response.parsed_body['blog_post'].values_at('title', 'slug')
  end

  test 'update validates and changes nothing on error' do
    blog_post = create_post(title: 'Hope')

    patch "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor), as: :json,
                                                params: { blog_post: { title: 'New', category: 'Weddings' } }

    assert_response :unprocessable_entity
    assert_equal ['Category must be one of Faith & Devotion, Church Life, Youth, Family, Outreach, Testimonies'],
                 response.parsed_body['errors']
    assert_equal 'Hope', blog_post.reload.title
  end

  test 'replacing the cover deletes the old file' do
    blog_post = create_post(cover: true)
    old_blob = blog_post.cover_image.blob

    patch "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor),
                                                params: { blog_post: { cover_image: fixture_file_upload('photo.png') } }

    assert_response :ok
    assert_match(/photo\.png\z/, response.parsed_body['blog_post']['cover_image_url'])
    assert_not ActiveStorage::Blob.exists?(old_blob.id)
    assert_not ActiveStorage::Blob.service.exist?(old_blob.key)
  end

  test 'remove_cover_image deletes the cover' do
    blog_post = create_post(cover: true)
    blob = blog_post.cover_image.blob

    assert_difference -> { ActiveStorage::Blob.count } => -1, -> { ActiveStorage::Attachment.count } => -1 do
      patch "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor),
                                                  params: { blog_post: { remove_cover_image: 'true' } }
    end

    assert_response :ok
    assert_nil response.parsed_body['blog_post']['cover_image_url']
    assert_not ActiveStorage::Blob.service.exist?(blob.key)
  end

  # --- Destroy ---

  test 'destroy deletes the post, its cover and its body photos' do
    image = upload_image
    blog_post = create_post(cover: true, body: [image_block(image)])
    keys = [blog_post.cover_image.key, image.image.key]

    assert_difference -> { BlogPost.count } => -1, -> { BlogPostImage.count } => -1,
                      -> { ActiveStorage::Blob.count } => -2 do
      delete "/api/v1/blog_posts/#{blog_post.id}", headers: auth_headers(@editor), as: :json
    end

    assert_response :ok
    assert_equal({ 'message' => 'Post deleted', 'id' => blog_post.id }, response.parsed_body)
    keys.each { |key| assert_not ActiveStorage::Blob.service.exist?(key) }
  end

  test 'unknown post id returns 404' do
    patch '/api/v1/blog_posts/999999', headers: auth_headers(@editor), as: :json,
                                       params: { blog_post: { title: 'X' } }
    assert_response :not_found
    assert_equal({ 'error' => 'Post not found' }, response.parsed_body)

    delete '/api/v1/blog_posts/999999', headers: auth_headers(@editor), as: :json
    assert_response :not_found
  end

  # --- Authentication and permissions ---

  test 'create, update and destroy require login' do
    blog_post = create_post

    post '/api/v1/blog_posts', as: :json, params: { blog_post: { title: 'X', status: 'draft' } }
    assert_response :unauthorized

    patch "/api/v1/blog_posts/#{blog_post.id}", as: :json, params: { blog_post: { title: 'X' } }
    assert_response :unauthorized

    delete "/api/v1/blog_posts/#{blog_post.id}", as: :json
    assert_response :unauthorized
    assert BlogPost.exists?(blog_post.id)
  end

  test 'users without manage_blog get 403' do
    blog_post = create_post
    headers = auth_headers(@treasurer)

    assert_no_difference -> { BlogPost.count } do
      post '/api/v1/blog_posts', headers: headers, as: :json, params: { blog_post: { title: 'X', status: 'draft' } }
    end
    assert_response :forbidden

    patch "/api/v1/blog_posts/#{blog_post.id}", headers: headers, as: :json, params: { blog_post: { title: 'X' } }
    assert_response :forbidden

    delete "/api/v1/blog_posts/#{blog_post.id}", headers: headers, as: :json
    assert_response :forbidden
    assert_equal 'Hope', blog_post.reload.title
  end

  test 'super admin is always allowed' do
    post '/api/v1/blog_posts', headers: auth_headers(users(:super_admin)), as: :json,
                               params: { blog_post: { title: 'X', status: 'draft' } }
    assert_response :created

    get '/api/v1/blog_posts', params: { status: 'all' }, headers: auth_headers(users(:super_admin))
    assert_response :ok
  end

  private

  def post_fields
    { title: 'Hope', excerpt: 'A word of hope.', category: 'Youth', published_on: '2026-08-04', body: BODY.to_json }
  end

  def create_post(cover: false, **attrs)
    blog_post = BlogPost.new({ title: 'Hope', excerpt: 'A word of hope.', category: 'Youth',
                               published_on: '2026-08-04', body: BODY }.merge(attrs))
    if cover
      blog_post.cover_image.attach(io: file_fixture('photo.jpg').open, filename: 'photo.jpg',
                                   content_type: 'image/jpeg')
    end
    blog_post.save!
    blog_post
  end

  def upload_image
    image = BlogPostImage.new
    image.image.attach(io: file_fixture('photo.jpg').open, filename: 'photo.jpg', content_type: 'image/jpeg')
    image.save!
    image
  end

  def image_block(image)
    { 'type' => 'image', 'image_id' => image.token }
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
