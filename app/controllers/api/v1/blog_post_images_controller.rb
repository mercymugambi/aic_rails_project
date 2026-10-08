module Api
  module V1
    # Photos placed inside a blog post. The editor uploads each photo as soon as it is inserted, before
    # the post is saved, and puts the returned id into the image block as image_id.
    class BlogPostImagesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action -> { authorize!(:manage_blog) }

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the photo under a "blog_post_image" key' }, status: :bad_request
      end

      # Storage failures while uploading (e.g. Cloudinary rejects the credentials).
      rescue_from ActiveStorage::Error do |error|
        logger.error("Blog photo upload failed: #{error.class}: #{error.message}")
        render json: { error: "The photo couldn't be saved to storage. Please try again." }, status: :bad_gateway
      end

      # POST /api/v1/blog_post_images (multipart form data, one photo per request)
      def create
        image = BlogPostImage.new(image: uploaded_file, created_by: current_user)

        if image.save_with_image
          render json: { message: 'Photo uploaded',
                         blog_post_image: { id: image.token, url: BlogPostSerializer.image_url(image.image) } },
                 status: :created
        else
          render json: { errors: image.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      # Only an uploaded file is accepted (not a string such as a signed blob id).
      def uploaded_file
        file = params.require(:blog_post_image).permit(:image)[:image]
        file if file.is_a?(ActionDispatch::Http::UploadedFile)
      end
    end
  end
end
