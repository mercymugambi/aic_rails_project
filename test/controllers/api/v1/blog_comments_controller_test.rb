require 'test_helper'

class Api::V1::BlogCommentsControllerTest < ActionDispatch::IntegrationTest
  ADMIN_KEYS = %w[id author_name author_email body status created_at updated_at reply blog_post].freeze

  setup do
    @editor = users(:blog_editor) # manage_blog only
    @treasurer = users(:treasurer) # no manage_blog
    @post = create_post(title: 'Walking in Faith')
  end

  # --- Index ---

  test 'index lists every comment newest first, with the email and the post, drafts included' do
    draft = create_post(title: 'Ideas', status: 'draft')
    oldest = add_comment(created_at: 3.hours.ago)
    hidden = add_comment(status: 'hidden', created_at: 2.hours.ago)
    on_draft = add_comment(post: draft, created_at: 1.hour.ago)

    get '/api/v1/blog_comments', headers: auth_headers(@editor)

    assert_response :ok
    assert_equal [on_draft.id, hidden.id, oldest.id], response.parsed_body.pluck('id')
    item = response.parsed_body.first
    assert_equal ADMIN_KEYS, item.keys
    assert_equal({ 'id' => on_draft.id, 'author_name' => 'Grace Wanjiru', 'author_email' => 'grace@example.com',
                   'body' => 'This blessed me so much.', 'status' => 'pending', 'reply' => nil,
                   'blog_post' => { 'id' => draft.id, 'slug' => 'ideas', 'title' => 'Ideas', 'status' => 'draft' } },
                 item.except('created_at', 'updated_at'))
  end

  test 'status filters the list; all, a missing or an unknown status lists everything' do
    pending = add_comment(created_at: 3.hours.ago)
    approved = add_comment(status: 'approved', created_at: 2.hours.ago)
    hidden = add_comment(status: 'hidden', created_at: 1.hour.ago)
    everything = [hidden.id, approved.id, pending.id]

    { 'pending' => [pending.id], 'approved' => [approved.id], 'hidden' => [hidden.id], 'all' => everything,
      'spam' => everything, nil => everything }.each do |status, ids|
      get '/api/v1/blog_comments', params: { status: status }.compact, headers: auth_headers(@editor)
      assert_equal ids, response.parsed_body.pluck('id'), status.inspect
    end
  end

  test 'blog_post_id narrows the list to one post' do
    other = create_post(title: 'Another post')
    mine = add_comment
    add_comment(post: other)

    get '/api/v1/blog_comments', params: { blog_post_id: @post.id, status: 'all' }, headers: auth_headers(@editor)

    assert_equal [mine.id], response.parsed_body.pluck('id')
  end

  test 'index loads the posts without N+1 queries' do
    add_comment
    one_comment = count_queries { get '/api/v1/blog_comments', headers: auth_headers(@editor) }
    3.times { |n| add_comment(post: create_post(title: "Post #{n}")) }
    four_comments = count_queries { get '/api/v1/blog_comments', headers: auth_headers(@editor) }

    assert_equal 4, response.parsed_body.size
    assert_equal one_comment, four_comments
  end

  # --- Update ---

  test 'approving and hiding' do
    comment = add_comment

    patch_comment comment, status: 'approved'
    assert_response :ok
    assert_equal 'Comment updated', response.parsed_body['message']
    assert_equal ADMIN_KEYS, response.parsed_body['blog_comment'].keys
    assert_equal 'approved', response.parsed_body['blog_comment']['status']

    patch_comment comment, status: 'hidden'
    assert_equal 'hidden', comment.reload.status
  end

  test 'an unknown status is refused' do
    comment = add_comment

    patch_comment comment, status: 'spam'

    assert_response :unprocessable_entity
    assert_equal({ 'errors' => ['Status must be one of pending, approved, hidden'] }, response.parsed_body)
    assert_equal 'pending', comment.reload.status
  end

  test 'a reply is signed with the name of the person replying and stamped when the text changes' do
    @editor.update!(firstname: 'Joseph', lastname: 'Kamau')
    comment = add_comment

    travel_to(Time.utc(2026, 10, 18, 10)) { patch_comment comment, reply_body: '  Thank you, Grace!  ' }

    assert_response :ok
    assert_equal({ 'body' => 'Thank you, Grace!', 'author_name' => 'Joseph Kamau',
                   'created_at' => '2026-10-18T10:00:00.000Z' }, response.parsed_body['blog_comment']['reply'])
    assert_equal ['pending', @editor], [comment.reload.status, comment.replied_by]

    travel_to(Time.utc(2026, 10, 19, 10)) { patch_comment comment, reply_body: 'Thank you, Grace!' }
    assert_equal Time.utc(2026, 10, 18, 10), comment.reload.replied_at

    travel_to(Time.utc(2026, 10, 20, 10)) { patch_comment comment, reply_body: 'Thank you, Grace! Bless you.' }
    assert_equal Time.utc(2026, 10, 20, 10), comment.reload.replied_at
  end

  test 'a reply from a user without a name is signed AIC Kabuku' do
    patch_comment add_comment, reply_body: 'Thank you!'

    assert_equal 'AIC Kabuku', response.parsed_body['blog_comment']['reply']['author_name']
  end

  test 'a blank or null reply removes the reply' do
    ['', nil].each do |blank|
      comment = add_comment(reply_body: 'Thank you!', reply_author_name: 'Pastor Joseph', replied_at: 1.day.ago,
                            replied_by: @editor)

      patch_comment comment, reply_body: blank

      assert_response :ok
      assert_nil response.parsed_body['blog_comment']['reply']
      assert_equal [nil, nil, nil, nil],
                   comment.reload.slice(:reply_body, :reply_author_name, :replied_at, :replied_by_id).values
    end
  end

  test 'reply and approve in one request' do
    comment = add_comment

    patch_comment comment, status: 'approved', reply_body: 'Thank you!'

    assert_response :ok
    assert_equal ['approved', 'Thank you!'], [comment.reload.status, comment.reply_body]
  end

  test 'a reply that is too long is refused' do
    patch_comment add_comment, reply_body: 'a' * 2001

    assert_response :unprocessable_entity
    assert_equal({ 'errors' => ['Reply is too long (maximum is 2000 characters)'] }, response.parsed_body)
  end

  test 'only the status and the reply can be changed' do
    comment = add_comment

    patch_comment comment, body: 'Edited', author_name: 'Someone else', author_email: 'x@example.com'

    assert_response :ok
    assert_equal ['This blessed me so much.', 'Grace Wanjiru', 'grace@example.com'],
                 comment.reload.slice(:body, :author_name, :author_email).values
  end

  # Sent as a form: Rails wraps a JSON body's top-level status and reply_body in blog_comment.
  test 'update requires the blog_comment key' do
    comment = add_comment

    patch "/api/v1/blog_comments/#{comment.id}", headers: auth_headers(@editor), params: { status: 'approved' }

    assert_response :bad_request
    assert_equal 'pending', comment.reload.status
    assert_equal({ 'error' => 'Send the comment details under a "blog_comment" key' }, response.parsed_body)
  end

  # --- Destroy ---

  test 'destroy deletes the comment' do
    comment = add_comment

    assert_difference -> { BlogComment.count } => -1 do
      delete "/api/v1/blog_comments/#{comment.id}", headers: auth_headers(@editor), as: :json
    end

    assert_response :ok
    assert_equal({ 'message' => 'Comment deleted', 'id' => comment.id }, response.parsed_body)
  end

  test 'unknown comment ids are not found' do
    patch '/api/v1/blog_comments/999999', headers: auth_headers(@editor), as: :json,
                                          params: { blog_comment: { status: 'approved' } }
    assert_response :not_found
    assert_equal({ 'error' => 'Comment not found' }, response.parsed_body)

    delete '/api/v1/blog_comments/999999', headers: auth_headers(@editor), as: :json
    assert_response :not_found
    assert_equal({ 'error' => 'Comment not found' }, response.parsed_body)
  end

  # --- Authentication and permissions ---

  test 'every action requires login' do
    comment = add_comment

    get '/api/v1/blog_comments', headers: { 'Accept' => 'application/json' }
    assert_response :unauthorized

    patch "/api/v1/blog_comments/#{comment.id}", as: :json, params: { blog_comment: { status: 'approved' } }
    assert_response :unauthorized

    delete "/api/v1/blog_comments/#{comment.id}", as: :json
    assert_response :unauthorized
    assert_equal 'pending', comment.reload.status
  end

  test 'users without manage_blog get 403' do
    comment = add_comment
    headers = auth_headers(@treasurer)

    get '/api/v1/blog_comments', headers: headers
    assert_response :forbidden
    assert_equal({ 'error' => 'You do not have permission to perform this action' }, response.parsed_body)

    patch "/api/v1/blog_comments/#{comment.id}", headers: headers, as: :json,
                                                 params: { blog_comment: { status: 'approved' } }
    assert_response :forbidden

    delete "/api/v1/blog_comments/#{comment.id}", headers: headers, as: :json
    assert_response :forbidden
    assert_equal 'pending', comment.reload.status
  end

  private

  def patch_comment(comment, **fields)
    patch "/api/v1/blog_comments/#{comment.id}", headers: auth_headers(@editor), as: :json,
                                                 params: { blog_comment: fields }
  end

  def create_post(**attrs)
    BlogPost.create!({ title: 'Hope', excerpt: 'A word of hope.', category: 'Youth', published_on: '2026-08-04',
                       body: [{ 'type' => 'paragraph', 'text' => 'Be strong.' }] }.merge(attrs))
  end

  def add_comment(post: @post, **attrs)
    post.comments.create!({ author_name: 'Grace Wanjiru', author_email: 'grace@example.com',
                            body: 'This blessed me so much.' }.merge(attrs))
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
