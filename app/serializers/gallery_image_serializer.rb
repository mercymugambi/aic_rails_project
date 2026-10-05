# JSON shape of a photo returned by the Gallery API.
#
# Use GalleryImage.with_attached_image when serializing many photos to avoid N+1 queries.
class GalleryImageSerializer
  def initialize(photo)
    @photo = photo
  end

  def as_json(*)
    {
      id: photo.id,
      title: photo.title,
      category: photo.category,
      taken_on: photo.taken_on,
      image_url: image_url,
      created_at: photo.created_at
    }
  end

  private

  attr_reader :photo

  # Absolute URL a browser can load directly. Each photo keeps the service it was uploaded to, so
  # photos stored locally before CLOUDINARY_URL was set still work.
  def image_url
    return unless photo.image.attached?

    if photo.image.blob.service_name == 'cloudinary'
      # Public, permanent https delivery URL; f_auto,q_auto serves a smaller format/quality per browser
      # without changing the stored original.
      photo.image.url(fetch_format: 'auto', quality: 'auto')
    else
      Rails.application.routes.url_helpers.rails_blob_url(photo.image)
    end
  end
end
