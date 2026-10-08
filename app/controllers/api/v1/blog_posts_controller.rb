module Api
  module V1
    # Posts for the public Blog page. Anyone can read published posts (show looks them up by slug);
    # listing drafts (?status=all), writing, editing and deleting needs manage_blog.
    class BlogPostsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!, except: %i[index show]
      before_action -> { authorize!(:manage_blog) }, except: %i[index show]
      before_action :authorize_all_statuses!, only: :index, if: -> { params[:status] == 'all' }
      before_action :set_post, only: %i[update destroy]

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the post details under a "blog_post" key' }, status: :bad_request
      end

      # Storage failures while uploading the cover image (e.g. Cloudinary rejects the credentials).
      rescue_from ActiveStorage::Error do |error|
        logger.error("Blog cover upload failed: #{error.class}: #{error.message}")
        render json: { error: "The photo couldn't be saved to storage. Please try again." }, status: :bad_gateway
      end

      # GET /api/v1/blog_posts            published posts, newest first
      # GET /api/v1/blog_posts?status=all drafts too (manage_blog)
      def index
        posts = BlogPost.with_attached_cover_image.includes(body_images: { image_attachment: :blob }).newest_first
        posts = posts.published unless params[:status] == 'all'
        render json: posts.map { |post| serialize(post) }
      end

      # GET /api/v1/blog_posts/:slug
      def show
        post = BlogPost.published.find_by(slug: params[:id])
        return render json: { error: 'Post not found' }, status: :not_found unless post

        render json: serialize(post)
      end

      # POST /api/v1/blog_posts (multipart form data; body is a JSON string of blocks)
      def create
        post = BlogPost.new(post_params.merge(created_by: current_user))

        if post.save_with_uploads
          render json: { message: 'Post saved', blog_post: serialize(post.reload) }, status: :created
        else
          render json: { errors: post.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/blog_posts/:id
      # Multipart or JSON; only the keys sent are changed. remove_cover_image=true deletes the cover.
      def update
        @post.assign_attributes(post_params)
        @post.cover_image = nil if remove_cover_image? && !post_params.key?(:cover_image)

        if @post.save_with_uploads
          render json: { message: 'Post updated', blog_post: serialize(@post.reload) }
        else
          render json: { errors: @post.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/blog_posts/:id
      # Also deletes the cover image and the photos in the body from storage.
      def destroy
        @post.destroy!
        render json: { message: 'Post deleted', id: @post.id }
      end

      private

      def authorize_all_statuses!
        authenticate_user!
        authorize!(:manage_blog)
      end

      def set_post
        @post = BlogPost.find_by(id: params[:id])
        render json: { error: 'Post not found' }, status: :not_found unless @post
      end

      # Only an uploaded file is accepted as the cover (not a string such as a signed blob id). body is
      # passed through as sent (JSON string or array); BlogPost keeps only the documented block keys.
      def post_params
        @post_params ||= begin
          fields = params.require(:blog_post)
          permitted = fields.permit(:title, :slug, :excerpt, :category, :status, :featured, :published_on,
                                    :author_name, :author_role, :cover_image, tags: [])
          permitted.delete(:cover_image) unless permitted[:cover_image].is_a?(ActionDispatch::Http::UploadedFile)
          permitted[:body] = plain(fields[:body]) if fields.key?(:body)
          permitted
        end
      end

      def plain(value)
        case value
        when Array then value.map { |item| plain(item) }
        when ActionController::Parameters then value.to_unsafe_h
        else value
        end
      end

      def remove_cover_image?
        ActiveModel::Type::Boolean.new.cast(params.require(:blog_post)[:remove_cover_image]) == true
      end

      def serialize(post)
        BlogPostSerializer.new(post).as_json
      end
    end
  end
end
