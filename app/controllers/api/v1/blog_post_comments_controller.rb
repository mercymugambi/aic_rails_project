module Api
  module V1
    # Comments on a published post, for visitors (no login); the post is looked up by slug. Anyone can read
    # the approved comments and post one, which waits for approval unless BlogComment::AUTO_APPROVE is on.
    # Moderation is in BlogCommentsController.
    class BlogPostCommentsController < ApplicationController
      # Comments allowed from one IP address per window, counted in Rails.cache (off with a null store).
      COMMENT_LIMIT = 5
      COMMENT_WINDOW = 10.minutes

      skip_before_action :verify_authenticity_token
      before_action :throttle_comments!, only: :create
      before_action :set_post

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the comment under a "comment" key' }, status: :bad_request
      end

      # GET /api/v1/blog_posts/:slug/comments (approved only, oldest first)
      def index
        comments = @post.comments.approved.oldest_first
        render json: comments.map { |comment| BlogCommentSerializer.new(comment).public_json }
      end

      # POST /api/v1/blog_posts/:slug/comments
      # `website` is a field people never see: a bot that fills it in is told it worked, and nothing is saved.
      def create
        fields = params.require(:comment).permit(:author_name, :author_email, :body, :website)
        if fields[:website].present?
          decoy = BlogComment.new(fields.except(:website).merge(status: 'pending', created_at: Time.current))
          return render_received(decoy)
        end

        attributes = fields.except(:website).merge(status: BlogComment.initial_status, ip_address: request.remote_ip)
        comment = @post.comments.new(attributes)
        if comment.save
          render_received(comment)
        else
          render json: { errors: comment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      # Drafts look like missing posts, as in BlogPostsController#show.
      def set_post
        @post = BlogPost.published.find_by(slug: params[:blog_post_id])
        render json: { error: 'Post not found' }, status: :not_found unless @post
      end

      # Counts attempts in fixed windows per IP address, as EventRegistrationsController#throttle_sign_ups! does.
      def throttle_comments!
        return if Rails.cache.is_a?(ActiveSupport::Cache::NullStore)

        key = "blog-comments/#{request.remote_ip}/#{Time.current.to_i / COMMENT_WINDOW.to_i}"
        count = Rails.cache.increment(key, 1, expires_in: COMMENT_WINDOW)
        count ||= Rails.cache.write(key, 1, expires_in: COMMENT_WINDOW, raw: true) && 1
        return if count <= COMMENT_LIMIT

        render json: { error: 'Too many comments from this connection. Please try again in a few minutes.' },
               status: :too_many_requests
      end

      def render_received(comment)
        render json: { message: 'Comment received', comment: BlogCommentSerializer.new(comment).received_json },
               status: :created
      end
    end
  end
end
