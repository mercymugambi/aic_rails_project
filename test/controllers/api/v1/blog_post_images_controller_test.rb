require 'test_helper'
require 'minitest/mock'
require 'rake'

class Api::V1::BlogPostImagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @editor = users(:blog_editor) # manage_blog only
  end

  test 'create uploads the photo straight away and returns an opaque id and absolute url' do
    assert_difference -> { BlogPostImage.count } => 1, -> { ActiveStorage::Blob.count } => 1 do
      post '/api/v1/blog_post_images', headers: auth_headers(@editor),
                                       params: { blog_post_image: { image: fixture_file_upload('photo.png') } }
    end

    assert_response :created
    assert_equal 'Photo uploaded', response.parsed_body['message']
    item = response.parsed_body['blog_post_image']
    assert_equal %w[id url], item.keys
    image = BlogPostImage.find_by!(token: item['id'])
    assert_nil image.blog_post
    assert_equal @editor, image.created_by
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/.+/photo\.png\z}, item['url']
    assert ActiveStorage::Blob.service.exist?(image.image.key)
  end

  test 'create rejects missing, non-image and oversized files' do
    assert_rejected nil, "Image can't be blank"
    assert_rejected 'not-a-file', "Image can't be blank"
    assert_rejected upload('%PDF-1.4 hello', 'flyer.jpg', 'image/jpeg'), 'Image must be a JPG, PNG or WEBP file'
    big = file_fixture('photo.png').binread + ("\x00" * 10.megabytes)
    assert_rejected upload(big, 'big.png', 'image/png'), 'Image must be 10 MB or smaller'
  end

  test 'create requires the blog_post_image key' do
    post '/api/v1/blog_post_images', headers: auth_headers(@editor), params: { image: 'x' }
    assert_response :bad_request
    assert_equal({ 'error' => 'Send the photo under a "blog_post_image" key' }, response.parsed_body)
  end

  test 'a failed upload to storage leaves nothing behind' do
    failing_upload = ->(*, **) { raise ActiveStorage::IntegrityError, 'Invalid api_key' }
    counts = [-> { BlogPostImage.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count }]

    assert_no_difference counts do
      ActiveStorage::Blob.service.stub(:upload, failing_upload) do
        post '/api/v1/blog_post_images', headers: auth_headers(@editor),
                                         params: { blog_post_image: { image: fixture_file_upload('photo.jpg') } }
      end
    end

    assert_response :bad_gateway
    assert_equal({ 'error' => "The photo couldn't be saved to storage. Please try again." }, response.parsed_body)
  end

  test 'create needs login and manage_blog' do
    params = { blog_post_image: { image: fixture_file_upload('photo.jpg') } }

    post '/api/v1/blog_post_images', headers: { 'Accept' => 'application/json' }, params: params
    assert_response :unauthorized

    post '/api/v1/blog_post_images', headers: auth_headers(users(:gallery_manager)), params: params
    assert_response :forbidden

    post '/api/v1/blog_post_images', headers: auth_headers(users(:super_admin)), params: params
    assert_response :created
  end

  test 'blog:purge_orphan_images deletes old unattached photos' do
    Rails.application.load_tasks unless Rake::Task.task_defined?('blog:purge_orphan_images')
    post '/api/v1/blog_post_images', headers: auth_headers(@editor),
                                     params: { blog_post_image: { image: fixture_file_upload('photo.jpg') } }
    image = BlogPostImage.find_by!(token: response.parsed_body['blog_post_image']['id'])
    image.update!(created_at: 2.days.ago)

    assert_output(/Deleted 1 unused blog photo/) { Rake::Task['blog:purge_orphan_images'].execute }
    assert_not BlogPostImage.exists?(image.id)
    assert_not ActiveStorage::Blob.service.exist?(image.image.key)
  end

  private

  def upload(content, filename, content_type)
    file = Tempfile.new(['upload', File.extname(filename)], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  def assert_rejected(image, message)
    assert_no_difference [-> { BlogPostImage.count }, -> { ActiveStorage::Blob.count }] do
      post '/api/v1/blog_post_images', headers: auth_headers(@editor), params: { blog_post_image: { image: image } }
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'], message
  end
end
