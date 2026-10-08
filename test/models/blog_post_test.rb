require 'test_helper'

class BlogPostTest < ActiveSupport::TestCase
  PUBLISHED = { title: 'Hope for today', excerpt: 'A short word of hope.', category: 'Youth',
                published_on: '2026-08-04', body: [{ 'type' => 'paragraph', 'text' => 'Be strong.' }] }.freeze

  # --- Draft vs published ---

  test 'a draft needs only a title' do
    post = BlogPost.new(title: 'Ideas', status: 'draft')
    assert post.save, post.errors.full_messages.to_sentence
    assert_equal [], post.body
    assert_equal [], post.tags
    assert_not post.featured
  end

  test 'a title is always required' do
    post = BlogPost.new(title: '  ', status: 'draft')
    assert_not post.valid?
    assert_includes post.errors.full_messages, "Title can't be blank"
  end

  test 'a published post needs an excerpt, content, a category and a publish date' do
    post = BlogPost.new(title: 'Hope')
    assert_equal 'published', post.status
    assert_not post.valid?
    assert_equal ["Excerpt can't be blank", "Category can't be blank", "Publish date can't be blank",
                  "Content can't be blank"], post.errors.full_messages
  end

  test 'a complete published post saves' do
    assert BlogPost.new(PUBLISHED).save
  end

  test 'status, category and lengths are checked' do
    post = BlogPost.new(PUBLISHED.merge(status: 'archived', category: 'Weddings', title: 'a' * 151,
                                        excerpt: 'a' * 221))
    assert_not post.valid?
    assert_includes post.errors.full_messages, 'Status must be published or draft'
    assert_includes post.errors.full_messages,
                    'Category must be one of Faith & Devotion, Church Life, Youth, Family, Outreach, Testimonies'
    assert_includes post.errors.full_messages, 'Title is too long (maximum is 150 characters)'
    assert_includes post.errors.full_messages, 'Excerpt is too long (maximum is 220 characters)'
  end

  test 'blank strings become nil' do
    post = BlogPost.create!(title: ' Ideas ', status: 'draft', category: ' ', excerpt: '', author_name: '  ',
                            author_role: '', published_on: '')
    assert_equal 'Ideas', post.title
    assert_nil post.category
    assert_nil post.excerpt
    assert_nil post.author_name
    assert_nil post.author_role
    assert_nil post.published_on
  end

  # --- Slug ---

  test 'a blank slug is made from the title' do
    assert_equal 'gods-love-for-families', create_post(title: "  God's Love for Families! ").slug
    assert_equal 'post', create_post(title: '!!!').slug
  end

  test 'a long title makes a slug of at most 80 characters without a trailing hyphen' do
    slug = create_post(title: "#{'word ' * 15}end").slug
    assert_operator slug.length, :<=, 80
    assert_match BlogPost::SLUG_FORMAT, slug
  end

  test 'a taken slug gets -2, -3 appended instead of failing' do
    assert_equal 'hope', create_post(title: 'Hope').slug
    assert_equal 'hope-2', create_post(title: 'Hope').slug
    assert_equal 'hope-3', create_post(title: 'Something else', slug: 'hope').slug
  end

  test "outer hyphens are trimmed from a sent slug (the editor's 80-character cut can end on one)" do
    assert_equal 'hope-for', create_post(slug: '-hope-for-').slug
    assert_equal 'hope', create_post(title: 'Hope', slug: '-').slug
  end

  test 'a suffixed slug still fits in 80 characters' do
    create_post(slug: 'a' * 80)
    assert_equal "#{'a' * 78}-2", create_post(slug: 'a' * 80).slug
  end

  test 'the slug never changes on update unless a different one is sent' do
    post = create_post(title: 'Hope')

    post.update!(title: 'A new title')
    assert_equal 'hope', post.slug
    post.update!(slug: '')
    assert_equal 'hope', post.reload.slug
    post.update!(slug: 'hope')
    assert_equal 'hope', post.slug

    create_post(slug: 'taken')
    post.update!(slug: 'taken')
    assert_equal 'taken-2', post.slug
  end

  test 'a malformed slug is rejected' do
    ['Hope Today', 'hope--today', 'hope_today', 'a' * 81].each do |slug|
      post = BlogPost.new(PUBLISHED.merge(slug: slug))
      assert_not post.valid?, slug
    end
    post = BlogPost.new(PUBLISHED.merge(slug: 'Hope Today'))
    post.valid?
    assert_includes post.errors.full_messages, 'Slug can only contain lowercase letters, numbers and single hyphens'
  end

  # --- Featured ---

  test 'only one post is featured; featuring a post clears the others' do
    first = create_post(featured: true)
    second = create_post(featured: true)
    assert_not first.reload.featured
    assert second.reload.featured

    first.update!(featured: true)
    assert_equal [first.id], BlogPost.where(featured: true).pluck(:id)
  end

  test 'saving another post does not clear the featured one' do
    featured = create_post(featured: true)
    create_post(featured: false).update!(title: 'Changed')
    assert featured.reload.featured
  end

  # --- Tags ---

  test 'tags are trimmed, blanks dropped, deduplicated case-insensitively and capped at 10' do
    post = create_post(tags: [' Hope ', '', 'hope', 'Faith', ' ', 'FAITH', *('a'..'k').to_a])
    assert_equal ['Hope', 'Faith', *('a'..'h').to_a], post.tags
  end

  # --- Body ---

  test 'the body may be a JSON string' do
    post = create_post(body: '[{"type":"heading","text":"Intro"},{"type":"list","items":[" one ","","two"]}]')
    assert_equal [{ 'type' => 'heading', 'text' => 'Intro' }, { 'type' => 'list', 'items' => %w[one two] }], post.body
  end

  test 'unknown keys are stripped and optional blanks dropped' do
    post = create_post(body: [{ 'type' => 'quote', 'text' => ' Love ', 'cite' => ' ', 'style' => 'big' },
                              { type: 'paragraph', text: 'x', html: '<b>' }])
    assert_equal [{ 'type' => 'quote', 'text' => 'Love' }, { 'type' => 'paragraph', 'text' => 'x' }], post.body
  end

  test 'malformed JSON, a non-array body and bad blocks are rejected with readable messages' do
    assert_body_error 'not json', 'The post content could not be read. Please try saving again.'
    assert_body_error '{"type":"paragraph"}',
                      'The post content must be a list of paragraphs, headings, quotes, lists and photos'
    assert_body_error [{ 'type' => 'video', 'src' => 'x' }],
                      "Part 1 of the post isn't a paragraph, heading, quote, list or photo"
    assert_body_error ['just text'], "Part 1 of the post isn't a paragraph, heading, quote, list or photo"
    assert_body_error [{ 'type' => 'paragraph', 'text' => 'ok' }, { 'type' => 'heading', 'text' => ' ' }],
                      'The heading in part 2 of the post is empty'
    assert_body_error [{ 'type' => 'quote', 'cite' => 'John 3:16' }], 'The quote in part 1 of the post is empty'
    assert_body_error [{ 'type' => 'list', 'items' => ['', ' '] }], 'The list in part 1 of the post has no items'
    assert_body_error [{ 'type' => 'list', 'items' => 'one' }], 'The list in part 1 of the post has no items'
    assert_body_error [{ 'type' => 'list', 'items' => [1, 2] }], 'The list in part 1 of the post has no items'
  end

  test 'malformed JSON keeps the stored body' do
    post = create_post
    post.body = '[{'
    assert_not post.save
    assert_equal PUBLISHED[:body], post.reload.body
  end

  test 'an image block must refer to an uploaded photo' do
    assert_body_error [{ 'type' => 'image' }], BlogPostBody::PHOTO_ERROR
    assert_body_error [{ 'type' => 'image', 'image_id' => 'forged-id' }], BlogPostBody::PHOTO_ERROR
  end

  test "a photo attached to another post can't be reused" do
    image = upload_image
    create_post(body: [image_block(image)])

    assert_body_error [image_block(image)], BlogPostBody::PHOTO_ERROR
  end

  test 'saving attaches the photos and drops their stored url' do
    image = upload_image
    post = create_post(body: [{ 'type' => 'image', 'image_id' => image.token, 'url' => 'https://evil.example/x.jpg',
                                'caption' => ' Choir ' }])

    assert_equal [{ 'type' => 'image', 'image_id' => image.token, 'caption' => 'Choir' }], post.body
    assert_equal post, image.reload.blog_post
  end

  test 'photos removed from the body are deleted with their files after the save' do
    kept = upload_image
    removed = upload_image
    post = create_post(body: [image_block(kept), image_block(removed)])
    blob = removed.image.blob

    post.update!(body: [image_block(kept)])

    assert BlogPostImage.exists?(kept.id)
    assert_not BlogPostImage.exists?(removed.id)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(blob.key)
  end

  test 'a failed save leaves the photos unattached' do
    image = upload_image
    post = BlogPost.new(title: '', status: 'draft', body: [image_block(image)])

    assert_not post.save
    assert_nil image.reload.blog_post_id
  end

  # --- Reading time ---

  test 'read_minutes counts words in text, citations and list items at 200 a minute, minimum 1' do
    assert_equal 1, BlogPost.new(body: []).read_minutes
    body = [{ 'type' => 'paragraph', 'text' => 'word ' * 500 }, { 'type' => 'quote', 'text' => 'a b', 'cite' => 'c d' },
            { 'type' => 'list', 'items' => ['e f'] }, { 'type' => 'image', 'image_id' => 'x', 'caption' => 'g ' * 300 }]
    assert_equal 3, BlogPost.new(body: body).read_minutes # 506 words
    assert_equal 1, BlogPost.new(body: [{ 'type' => 'paragraph', 'text' => 'w ' * 299 }]).read_minutes
    assert_equal 2, BlogPost.new(body: [{ 'type' => 'paragraph', 'text' => 'w ' * 300 }]).read_minutes
  end

  # --- Orphaned photos ---

  test 'purge_orphans deletes unattached photos older than 24 hours, with their files' do
    old_orphan = upload_image(created_at: 25.hours.ago)
    new_orphan = upload_image(created_at: 23.hours.ago)
    old_attached = upload_image(created_at: 3.days.ago)
    create_post(body: [image_block(old_attached)])
    blob = old_orphan.image.blob

    assert_equal 1, BlogPostImage.purge_orphans

    assert_not BlogPostImage.exists?(old_orphan.id)
    assert_not ActiveStorage::Blob.service.exist?(blob.key)
    assert BlogPostImage.exists?(new_orphan.id)
    assert BlogPostImage.exists?(old_attached.id)
  end

  private

  def create_post(**attrs)
    BlogPost.create!(PUBLISHED.merge(attrs))
  end

  def upload_image(**attrs)
    image = BlogPostImage.new(**attrs)
    image.image.attach(io: file_fixture('photo.jpg').open, filename: 'photo.jpg', content_type: 'image/jpeg')
    image.save!
    image
  end

  def image_block(image)
    { 'type' => 'image', 'image_id' => image.token }
  end

  def assert_body_error(body, message)
    post = BlogPost.new(PUBLISHED.merge(body: body))
    assert_not post.valid?, "expected #{body.inspect} to be rejected"
    assert_includes post.errors.full_messages, message
  end
end
