require 'test_helper'

class BlogCommentTest < ActiveSupport::TestCase
  setup do
    @post = BlogPost.create!(title: 'Hope', excerpt: 'A word of hope.', category: 'Youth', published_on: '2026-08-04',
                             body: [{ 'type' => 'paragraph', 'text' => 'Be strong.' }])
  end

  test 'fields are trimmed; the email is lowercased and a blank email or reply becomes nil' do
    comment = @post.comments.create!(author_name: ' Grace ', author_email: ' Grace@Example.COM ', body: " Amen \n",
                                     reply_body: '  ')
    assert_equal ['Grace', 'grace@example.com', 'Amen', nil],
                 [comment.author_name, comment.author_email, comment.body, comment.reply_body]

    comment.update!(author_email: '  ')
    assert_nil comment.author_email
  end

  test 'messages use the names visitors see on the form' do
    comment = @post.comments.new(author_name: 'G' * 81, author_email: 'grace@', body: 'x' * 2001,
                                 reply_body: 'y' * 2001, status: 'spam')
    assert_not comment.valid?
    assert_equal ['Name is too long (maximum is 80 characters)', 'Email is invalid',
                  'Comment is too long (maximum is 2000 characters)', 'Reply is too long (maximum is 2000 characters)',
                  'Status must be one of pending, approved, hidden'], comment.errors.full_messages
  end

  test 'new comments wait for approval while AUTO_APPROVE is off' do
    assert_not BlogComment::AUTO_APPROVE
    assert_equal 'pending', BlogComment.initial_status
    assert_equal 'pending', BlogComment.new.status
  end

  test 'counts_for groups by post and status in one query' do
    other = BlogPost.create!(title: 'Draft', status: 'draft')
    @post.comments.create!(author_name: 'A', body: 'One', status: 'approved')
    @post.comments.create!(author_name: 'B', body: 'Two', status: 'approved')
    other.comments.create!(author_name: 'C', body: 'Three')

    assert_equal({ [@post.id, 'approved'] => 2, [other.id, 'pending'] => 1 },
                 BlogComment.counts_for([@post.id, other.id]))
  end
end
