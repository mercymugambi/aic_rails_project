require 'test_helper'
require 'minitest/mock'

class Api::V1::GalleryImagesControllerTest < ActionDispatch::IntegrationTest
  ITEM_KEYS = %w[id title category taken_on image_url created_at].freeze

  setup do
    @manager = users(:gallery_manager) # manage_gallery only
    @treasurer = users(:treasurer) # no manage_gallery
  end

  # --- Index (public) ---

  test 'index is public and lists photos by month taken, newest first, undated last' do
    undated = create_photo(title: 'Undated')
    june = create_photo(title: 'June', taken_on: '2026-06-01', created_at: 2.days.ago)
    june_later = create_photo(title: 'June, added later', taken_on: '2026-06-01', created_at: 1.day.ago)
    august = create_photo(title: 'August', taken_on: '2026-08-01')

    get '/api/v1/gallery_images', as: :json

    assert_response :ok
    body = response.parsed_body
    assert_kind_of Array, body
    assert_equal [august, june_later, june, undated].map(&:id), body.pluck('id')
  end

  test 'index items have the documented shape and a loadable absolute image URL' do
    photo = create_photo(title: 'Sunday worship', category: 'Worship', taken_on: '2026-06-01')

    get '/api/v1/gallery_images', as: :json

    item = response.parsed_body.first
    assert_equal ITEM_KEYS, item.keys
    assert_equal({ 'id' => photo.id, 'title' => 'Sunday worship', 'category' => 'Worship', 'taken_on' => '2026-06-01' },
                 item.slice('id', 'title', 'category', 'taken_on'))
    assert_equal photo.created_at.as_json, item['created_at']
    assert_match %r{\Ahttp://www\.example\.com/rails/active_storage/blobs/redirect/.+/photo\.jpg\z}, item['image_url']

    get item['image_url']
    follow_redirect!
    assert_response :ok
    assert_equal file_fixture('photo.jpg').binread, response.body
  end

  test 'index loads attachments without N+1 queries' do
    create_photo
    one_photo = count_queries { get '/api/v1/gallery_images', as: :json }
    3.times { create_photo }
    four_photos = count_queries { get '/api/v1/gallery_images', as: :json }

    assert_equal 4, response.parsed_body.size
    assert_equal one_photo, four_photos
  end

  # --- Create ---

  test 'create uploads one photo, normalises fields and records the uploader' do
    assert_difference -> { GalleryImage.count } => 1, -> { ActiveStorage::Blob.count } => 1 do
      post '/api/v1/gallery_images', headers: auth_headers(@manager),
                                     params: { gallery_image: { image: fixture_file_upload('photo.jpg', 'image/jpeg'),
                                                                title: '  Sunday worship ', category: 'Worship',
                                                                taken_on: '2026-06-01' } }
    end

    assert_response :created
    assert_equal 'Photo added', response.parsed_body['message']
    item = response.parsed_body['gallery_image']
    assert_equal ITEM_KEYS, item.keys
    assert_equal ['Sunday worship', 'Worship', '2026-06-01'], item.values_at('title', 'category', 'taken_on')
    photo = GalleryImage.find(item['id'])
    assert_equal @manager, photo.created_by
    assert_equal 'image/jpeg', photo.image.blob.content_type
    assert ActiveStorage::Blob.service.exist?(photo.image.key)
  end

  test 'create accepts PNG without title, category or date' do
    post '/api/v1/gallery_images', headers: auth_headers(@manager),
                                   params: { gallery_image: { image: fixture_file_upload('photo.png', 'image/png'),
                                                              title: '', category: '' } }

    assert_response :created
    assert_equal ['', nil, nil], response.parsed_body['gallery_image'].values_at('title', 'category', 'taken_on')
  end

  test 'create rejects a missing image' do
    assert_rejected({ image: nil, title: 'No file' }, "Image can't be blank")
    assert_rejected({ image: 'not-a-file' }, "Image can't be blank")
  end

  test 'create rejects HEIC and other non JPG/PNG/WEBP files, even with a .jpg name' do
    heic = "\x00\x00\x00\x18ftypheic\x00\x00\x00\x00mif1heic".b + ("\x00" * 64)
    assert_rejected({ image: upload(heic, 'IMG_0001.HEIC', 'image/heic') }, 'Image must be a JPG, PNG or WEBP file')
    assert_rejected({ image: upload(heic, 'IMG_0001.jpg', 'image/jpeg') }, 'Image must be a JPG, PNG or WEBP file')
    assert_rejected({ image: upload('%PDF-1.4 hello', 'flyer.pdf', 'application/pdf') },
                    'Image must be a JPG, PNG or WEBP file')
  end

  test 'create rejects images over 10 MB' do
    big = file_fixture('photo.png').binread + ("\x00" * 10.megabytes)
    assert_rejected({ image: upload(big, 'big.png', 'image/png') }, 'Image must be 10 MB or smaller')
  end

  test 'create rejects an unknown category and a long title' do
    assert_rejected({ category: 'Weddings' }, 'Category must be one of Worship, Community, Prayer, Children, Outreach')
    assert_rejected({ title: 'a' * 151 }, 'Title is too long (maximum is 150 characters)')
  end

  test 'create requires the gallery_image key' do
    post '/api/v1/gallery_images', headers: auth_headers(@manager), params: { title: 'x' }
    assert_response :bad_request
    assert_equal({ 'error' => 'Send the photo details under a "gallery_image" key' }, response.parsed_body)
  end

  test 'a failed upload to storage leaves no photo behind' do
    failing_upload = ->(*, **) { raise ActiveStorage::IntegrityError, 'Invalid api_key' }
    counts = [-> { GalleryImage.count }, -> { ActiveStorage::Blob.count }, -> { ActiveStorage::Attachment.count }]

    assert_no_difference counts do
      ActiveStorage::Blob.service.stub(:upload, failing_upload) do
        post '/api/v1/gallery_images', headers: auth_headers(@manager),
                                       params: { gallery_image: { image: fixture_file_upload('photo.jpg') } }
      end
    end

    assert_response :bad_gateway
    assert_equal({ 'error' => "The photo couldn't be saved to storage. Please try again." }, response.parsed_body)
  end

  # --- Update ---

  test 'update is partial and null clears category and date' do
    photo = create_photo(title: 'Choir', category: 'Worship', taken_on: '2026-06-01')
    image_url = GalleryImageSerializer.new(photo).as_json[:image_url]

    patch "/api/v1/gallery_images/#{photo.id}", headers: auth_headers(@manager), as: :json,
                                                params: { gallery_image: { category: nil, taken_on: nil } }

    assert_response :ok
    assert_equal 'Photo updated', response.parsed_body['message']
    item = response.parsed_body['gallery_image']
    assert_equal ['Choir', nil, nil, image_url], item.values_at('title', 'category', 'taken_on', 'image_url')
    assert_nil photo.reload.category
  end

  test 'update validates and changes nothing on error' do
    photo = create_photo(category: 'Worship')

    patch "/api/v1/gallery_images/#{photo.id}", headers: auth_headers(@manager), as: :json,
                                                params: { gallery_image: { title: 'New', category: 'Weddings' } }

    assert_response :unprocessable_entity
    assert_equal ['Category must be one of Worship, Community, Prayer, Children, Outreach'],
                 response.parsed_body['errors']
    assert_equal 'Photo', photo.reload.title
  end

  # --- Destroy ---

  test 'destroy deletes the record, the blob and the stored file' do
    photo = create_photo
    blob = photo.image.blob

    assert_difference -> { GalleryImage.count } => -1, -> { ActiveStorage::Blob.count } => -1,
                      -> { ActiveStorage::Attachment.count } => -1 do
      delete "/api/v1/gallery_images/#{photo.id}", headers: auth_headers(@manager), as: :json
    end

    assert_response :ok
    assert_equal({ 'message' => 'Photo deleted', 'id' => photo.id }, response.parsed_body)
    assert_not ActiveStorage::Blob.exists?(blob.id)
    assert_not ActiveStorage::Blob.service.exist?(blob.key)
  end

  test 'unknown photo returns 404' do
    patch '/api/v1/gallery_images/999999', headers: auth_headers(@manager), as: :json,
                                           params: { gallery_image: { title: 'X' } }
    assert_response :not_found
    assert_equal({ 'error' => 'Photo not found' }, response.parsed_body)

    delete '/api/v1/gallery_images/999999', headers: auth_headers(@manager), as: :json
    assert_response :not_found
  end

  # --- Authentication and permissions ---

  test 'create, update and destroy require login' do
    photo = create_photo

    post '/api/v1/gallery_images', headers: { 'Accept' => 'application/json' },
                                   params: { gallery_image: { image: fixture_file_upload('photo.jpg') } }
    assert_response :unauthorized

    patch "/api/v1/gallery_images/#{photo.id}", as: :json, params: { gallery_image: { title: 'X' } }
    assert_response :unauthorized

    delete "/api/v1/gallery_images/#{photo.id}", as: :json
    assert_response :unauthorized
    assert GalleryImage.exists?(photo.id)
  end

  test 'users without manage_gallery get 403' do
    photo = create_photo
    headers = auth_headers(@treasurer)

    assert_no_difference -> { GalleryImage.count } do
      post '/api/v1/gallery_images', headers: headers,
                                     params: { gallery_image: { image: fixture_file_upload('photo.jpg') } }
    end
    assert_response :forbidden
    assert_equal({ 'error' => 'You do not have permission to perform this action' }, response.parsed_body)

    patch "/api/v1/gallery_images/#{photo.id}", headers: headers, as: :json, params: { gallery_image: { title: 'X' } }
    assert_response :forbidden

    delete "/api/v1/gallery_images/#{photo.id}", headers: headers, as: :json
    assert_response :forbidden
    assert_equal 'Photo', photo.reload.title
  end

  test 'super admin is always allowed' do
    post '/api/v1/gallery_images', headers: auth_headers(users(:super_admin)),
                                   params: { gallery_image: { image: fixture_file_upload('photo.jpg') } }
    assert_response :created
  end

  # --- CORS ---

  test 'the frontend origin may upload, edit and delete' do
    { '/api/v1/gallery_images' => 'POST', '/api/v1/gallery_images/1' => 'PATCH',
      '/api/v1/gallery_images/2' => 'DELETE' }.each do |path, method|
      options path, headers: { 'Origin' => 'http://localhost:3001', 'Access-Control-Request-Method' => method,
                               'Access-Control-Request-Headers' => 'authorization,content-type' }

      assert_equal 'http://localhost:3001', response.headers['Access-Control-Allow-Origin'], method
      assert_includes response.headers['Access-Control-Allow-Methods'], method
      assert_includes response.headers['Access-Control-Allow-Headers'].downcase, 'authorization'
    end
  end

  private

  def create_photo(title: 'Photo', **attrs)
    photo = GalleryImage.new(title: title, **attrs)
    photo.image.attach(io: file_fixture('photo.jpg').open, filename: 'photo.jpg', content_type: 'image/jpeg')
    photo.save!
    photo
  end

  def upload(content, filename, content_type)
    file = Tempfile.new(['upload', File.extname(filename)], binmode: true)
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, content_type, true, original_filename: filename)
  end

  def assert_rejected(overrides, message)
    params = { image: fixture_file_upload('photo.jpg', 'image/jpeg') }.merge(overrides)

    assert_no_difference [-> { GalleryImage.count }, -> { ActiveStorage::Blob.count }] do
      post '/api/v1/gallery_images', headers: auth_headers(@manager), params: { gallery_image: params }
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'], message
  end

  def count_queries(&)
    count = 0
    counter = ->(*, payload) { count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name]) }
    ActiveSupport::Notifications.subscribed(counter, 'sql.active_record', &)
    count
  end
end
