module Api
  module V1
    # Photos for the public Gallery page. Anyone can list them; uploading, editing and deleting
    # needs manage_gallery. Files are stored with Active Storage (Cloudinary when CLOUDINARY_URL is set).
    class GalleryImagesController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!, except: :index
      before_action -> { authorize!(:manage_gallery) }, except: :index
      before_action :set_photo, only: %i[update destroy]

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the photo details under a "gallery_image" key' }, status: :bad_request
      end

      # Storage failures while uploading (e.g. Cloudinary rejects the credentials).
      rescue_from ActiveStorage::Error do |error|
        logger.error("Gallery upload failed: #{error.class}: #{error.message}")
        render json: { error: "The photo couldn't be saved to storage. Please try again." }, status: :bad_gateway
      end

      # GET /api/v1/gallery_images
      def index
        photos = GalleryImage.with_attached_image.newest_first
        render json: photos.map { |photo| GalleryImageSerializer.new(photo).as_json }
      end

      # POST /api/v1/gallery_images (multipart form data, one photo per request)
      def create
        photo = GalleryImage.new(create_params.merge(created_by: current_user))

        if photo.save_with_image
          render json: { message: 'Photo added', gallery_image: serialize(photo) }, status: :created
        else
          render json: { errors: photo.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/gallery_images/:id
      # Partial update of the details; category and taken_on can be null to clear them.
      def update
        if @photo.update(update_params)
          render json: { message: 'Photo updated', gallery_image: serialize(@photo) }
        else
          render json: { errors: @photo.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/gallery_images/:id
      # Also deletes the file from storage.
      def destroy
        @photo.destroy!
        render json: { message: 'Photo deleted', id: @photo.id }
      end

      private

      def set_photo
        @photo = GalleryImage.find_by(id: params[:id])
        render json: { error: 'Photo not found' }, status: :not_found unless @photo
      end

      # Only an uploaded file is accepted as the image (not a string such as a signed blob id).
      def create_params
        permitted = params.require(:gallery_image).permit(:image, :title, :category, :taken_on)
        permitted.delete(:image) unless permitted[:image].is_a?(ActionDispatch::Http::UploadedFile)
        permitted
      end

      def update_params
        params.require(:gallery_image).permit(:title, :category, :taken_on)
      end

      def serialize(photo)
        GalleryImageSerializer.new(photo).as_json
      end
    end
  end
end
