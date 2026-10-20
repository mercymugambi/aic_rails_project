module Api
  module V1
    # Moderation of blog comments (manage_blog): every comment on every post, drafts included, with the
    # commenter's email. Approve, hide, reply to and delete them. Visitors use BlogPostCommentsController.
    class BlogCommentsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action -> { authorize!(:manage_blog) }
      before_action :set_comment, only: %i[update destroy]

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the comment details under a "blog_comment" key' }, status: :bad_request
      end

      # GET /api/v1/blog_comments?status=pending|approved|hidden|all&blog_post_id=3 (newest first)
      # A missing or unknown status means all.
      def index
        comments = BlogComment.includes(:blog_post).newest_first
        comments = comments.where(status: params[:status]) if BlogComment::STATUSES.include?(params[:status])
        comments = comments.where(blog_post_id: params[:blog_post_id]) if params[:blog_post_id].present?
        render json: comments.map { |comment| serialize(comment) }
      end

      # PATCH /api/v1/blog_comments/:id
      # Only the keys sent change. A blank or null reply_body removes the reply.
      def update
        fields = params.require(:blog_comment).permit(:status, :reply_body)
        @comment.status = fields[:status] if fields.key?(:status)
        @comment.reply_with(fields[:reply_body], by: current_user) if fields.key?(:reply_body)

        if @comment.save
          render json: { message: 'Comment updated', blog_comment: serialize(@comment) }
        else
          render json: { errors: @comment.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/blog_comments/:id
      def destroy
        @comment.destroy!
        render json: { message: 'Comment deleted', id: @comment.id }
      end

      private

      def set_comment
        @comment = BlogComment.find_by(id: params[:id])
        render json: { error: 'Comment not found' }, status: :not_found unless @comment
      end

      def serialize(comment)
        BlogCommentSerializer.new(comment).as_json
      end
    end
  end
end
