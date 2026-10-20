require 'test_helper'
require 'minitest/mock'

class Api::V1::BlogPostCommentsControllerTest < ActionDispatch::IntegrationTest
  PUBLIC_KEYS = %w[id author_name body created_at reply].freeze
  RECEIVED_KEYS = %w[id author_name body created_at status].freeze
  URL = '/api/v1/blog_posts/walking-in-faith/comments'.freeze

  setup do
    @post = create_post(title: 'Walking in Faith')
  end

  # --- Reading ---

  test 'index lists only approved comments on the post, oldest first, without email, IP or status' do
    newer = add_comment(body: 'Amen!', created_at: 1.hour.ago)
    older = add_comment(body: 'This blessed me so much.', created_at: 2.hours.ago)
    add_comment(status: 'pending')
    add_comment(status: 'hidden')
    add_comment(post: create_post(title: 'Another post'))

    get URL, as: :json

    assert_response :ok
    assert_equal [older.id, newer.id], response.parsed_body.pluck('id')
    response.parsed_body.each { |item| assert_equal PUBLIC_KEYS, item.keys }
    assert_equal({ 'id' => older.id, 'author_name' => 'Grace Wanjiru', 'body' => 'This blessed me so much.',
                   'reply' => nil }, response.parsed_body.first.except('created_at'))
  end

  test 'a reply is shown with who wrote it and when' do
    add_comment(created_at: Time.utc(2026, 10, 18, 9), reply_body: 'Thank you, Grace!',
                reply_author_name: 'Pastor Joseph', replied_at: Time.utc(2026, 10, 18, 10))

    get URL, as: :json

    item = response.parsed_body.first
    assert_equal '2026-10-18T09:00:00.000Z', item['created_at']
    assert_equal({ 'body' => 'Thank you, Grace!', 'author_name' => 'Pastor Joseph',
                   'created_at' => '2026-10-18T10:00:00.000Z' }, item['reply'])
  end

  test 'unknown slugs and drafts are not found' do
    draft = create_post(title: 'Secret', status: 'draft')
    add_comment(post: draft)

    ['/api/v1/blog_posts/no-such-post/comments', '/api/v1/blog_posts/secret/comments',
     "/api/v1/blog_posts/#{@post.id}/comments"].each do |url|
      get url, as: :json
      assert_response :not_found, url
      assert_equal({ 'error' => 'Post not found' }, response.parsed_body)
    end

    assert_no_difference -> { BlogComment.count } do
      post '/api/v1/blog_posts/secret/comments', as: :json, params: { comment: valid_fields }
    end
    assert_response :not_found
  end

  # --- Posting ---

  test 'a comment is saved as pending with the IP address and answered without the email' do
    assert_difference -> { @post.comments.count } => 1 do
      post_comment author_name: ' Grace Wanjiru ', author_email: ' Grace@Example.com ',
                   body: ' This blessed me so much. ', website: ''
    end

    assert_response :created
    saved = BlogComment.last
    assert_equal 'Comment received', response.parsed_body['message']
    assert_equal RECEIVED_KEYS, response.parsed_body['comment'].keys
    assert_equal [saved.id, 'Grace Wanjiru', 'This blessed me so much.', 'pending'],
                 response.parsed_body['comment'].values_at('id', 'author_name', 'body', 'status')
    assert_equal ['grace@example.com', '127.0.0.1'], [saved.author_email, saved.ip_address]
  end

  test 'the email is optional' do
    post_comment author_name: 'Grace', author_email: '', body: 'Amen'

    assert_response :created
    assert_nil BlogComment.last.author_email
  end

  test 'with auto-approval on, new comments are approved at once' do
    BlogComment.stub(:initial_status, 'approved') { post_comment(**valid_fields) }

    assert_response :created
    assert_equal 'approved', response.parsed_body['comment']['status']
    assert_equal 'approved', BlogComment.last.status
  end

  test 'invalid comments are explained' do
    assert_no_difference -> { BlogComment.count } do
      post_comment author_name: '  ', author_email: 'not-an-email', body: ' '
    end
    assert_response :unprocessable_entity
    assert_equal ["Name can't be blank", 'Email is invalid', "Comment can't be blank"],
                 response.parsed_body['errors']

    post_comment author_name: 'Grace', body: 'a' * 2001
    assert_response :unprocessable_entity
    assert_equal({ 'errors' => ['Comment is too long (maximum is 2000 characters)'] }, response.parsed_body)
  end

  test 'a filled-in honeypot looks like success but saves nothing' do
    assert_no_difference -> { BlogComment.count } do
      post_comment author_name: 'Bot', body: 'Cheap pills', website: 'http://spam.example'
    end

    assert_response :created
    assert_equal 'Comment received', response.parsed_body['message']
    assert_equal RECEIVED_KEYS, response.parsed_body['comment'].keys
    assert_equal [nil, 'pending'], response.parsed_body['comment'].values_at('id', 'status')
  end

  test 'more than 5 comments from one connection in 10 minutes get 429' do
    travel_to Time.utc(2026, 10, 20, 6)
    Rails.stub(:cache, ActiveSupport::Cache::MemoryStore.new) do
      5.times { |n| post_comment author_name: "Person #{n}", body: 'Amen' }
      assert_response :created

      assert_no_difference -> { BlogComment.count } do
        post_comment author_name: 'Person 6', body: 'Amen'
      end
      assert_response :too_many_requests
      assert_equal({ 'error' => 'Too many comments from this connection. Please try again in a few minutes.' },
                   response.parsed_body)

      travel 10.minutes
      post_comment author_name: 'Person 7', body: 'Amen'
      assert_response :created
    end
  end

  test 'visitors cannot set the status, a reply or the IP address' do
    post_comment(**valid_fields, status: 'approved', reply_body: 'Official reply', reply_author_name: 'Pastor',
                                 ip_address: '10.0.0.1')

    assert_response :created
    saved = BlogComment.last
    assert_equal ['pending', nil, nil, '127.0.0.1'],
                 [saved.status, saved.reply_body, saved.reply_author_name, saved.ip_address]
  end

  test 'create requires the comment key' do
    assert_no_difference -> { BlogComment.count } do
      post URL, as: :json, params: valid_fields
    end
    assert_response :bad_request
    assert_equal({ 'error' => 'Send the comment under a "comment" key' }, response.parsed_body)
  end

  private

  def valid_fields
    { author_name: 'Grace Wanjiru', author_email: 'grace@example.com', body: 'This blessed me so much.' }
  end

  def post_comment(**fields)
    post URL, as: :json, params: { comment: fields }
  end

  def create_post(**attrs)
    BlogPost.create!({ title: 'Hope', excerpt: 'A word of hope.', category: 'Youth', published_on: '2026-08-04',
                       body: [{ 'type' => 'paragraph', 'text' => 'Be strong.' }] }.merge(attrs))
  end

  def add_comment(post: @post, **attrs)
    post.comments.create!({ author_name: 'Grace Wanjiru', author_email: 'grace@example.com',
                            body: 'This blessed me so much.', status: 'approved', ip_address: '10.0.0.9' }.merge(attrs))
  end
end
