# JSON shapes of a blog comment. as_json is for moderation (manage_blog) and includes the commenter's email,
# the status and the post. public_json and received_json are what visitors see: never the email or IP address.
#
# Use BlogComment.includes(:blog_post) when serializing many comments with as_json to avoid N+1 queries.
class BlogCommentSerializer
  def initialize(comment)
    @comment = comment
  end

  def as_json(*)
    {
      id: comment.id,
      author_name: comment.author_name,
      author_email: comment.author_email,
      body: comment.body,
      status: comment.status,
      created_at: comment.created_at,
      updated_at: comment.updated_at,
      reply: reply,
      blog_post: comment.blog_post.slice(:id, :slug, :title, :status)
    }
  end

  # An approved comment on the public post page.
  def public_json
    { id: comment.id, author_name: comment.author_name, body: comment.body, created_at: comment.created_at,
      reply: reply }
  end

  # The answer to the visitor who just posted the comment; status says whether it waits for approval.
  def received_json
    { id: comment.id, author_name: comment.author_name, body: comment.body, created_at: comment.created_at,
      status: comment.status }
  end

  private

  attr_reader :comment

  def reply
    return unless comment.reply_body

    { body: comment.reply_body, author_name: comment.reply_author_name, created_at: comment.replied_at }
  end
end
