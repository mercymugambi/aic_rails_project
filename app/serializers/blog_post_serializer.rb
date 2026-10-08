# JSON shape of a post returned by the Blog API.
#
# Use BlogPost.with_attached_cover_image.includes(body_images: { image_attachment: :blob }) when
# serializing many posts to avoid N+1 queries.
class BlogPostSerializer
  # Absolute URL a browser can load directly, as in GalleryImageSerializer#image_url: Cloudinary's
  # public https URL (f_auto,q_auto), or the Active Storage redirect URL for locally stored files.
  def self.image_url(attached)
    return unless attached.attached?

    if attached.blob.service_name == 'cloudinary'
      attached.url(fetch_format: 'auto', quality: 'auto')
    else
      Rails.application.routes.url_helpers.rails_blob_url(attached)
    end
  end

  def initialize(post)
    @post = post
  end

  def as_json(*)
    {
      id: post.id,
      slug: post.slug,
      title: post.title,
      excerpt: post.excerpt,
      body: body,
      category: post.category,
      tags: post.tags,
      status: post.status,
      featured: post.featured,
      published_on: post.published_on,
      author_name: post.author_name,
      author_role: post.author_role,
      cover_image_url: self.class.image_url(post.cover_image),
      read_minutes: post.read_minutes,
      created_at: post.created_at,
      updated_at: post.updated_at
    }
  end

  private

  attr_reader :post

  # Image blocks get their url rebuilt from image_id on every read; no stored url is trusted.
  def body
    return post.body unless post.body.any? { |block| block['type'] == 'image' }

    images = post.body_images.index_by(&:token)
    post.body.map do |block|
      next block unless block['type'] == 'image'

      image = images[block['image_id']]
      { 'type' => 'image', 'image_id' => block['image_id'], 'url' => image && self.class.image_url(image.image),
        'caption' => block['caption'] }.compact
    end
  end
end
