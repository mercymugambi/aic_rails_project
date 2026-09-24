require 'test_helper'

class Api::V1::UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @super_admin = users(:super_admin)
    @church_admin = users(:church_admin)
  end

  # --- POST /api/v1/users ---

  test 'super admin creates a user with roles in one request' do
    assert_difference -> { User.count } => 1, -> { UserRole.count } => 2 do
      post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                            params: new_user_params(role_ids: [roles(:church_admin).id, roles(:treasurer).id])
    end

    assert_response :created
    body = response.parsed_body['user']
    assert_equal 'newleader@example.com', body['email']
    assert_equal false, body['super_admin']
    assert_equal %w[church_admin treasurer], body['roles'].sort
    assert_equal %w[manage_events manage_finance manage_users], body['permissions'].sort
    assert_nil body['member']

    user = User.find_by!(email: 'newleader@example.com')
    assert_equal [@super_admin], user.user_roles.map(&:assigned_by).uniq
  end

  test 'super admin can create a user without roles' do
    post '/api/v1/users', headers: auth_headers(@super_admin), as: :json, params: new_user_params

    assert_response :created
    assert_empty response.parsed_body['user']['roles']
    assert_empty response.parsed_body['user']['permissions']
  end

  test 'created user can log in and gets only their role permissions' do
    post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                          params: new_user_params(role_ids: [roles(:treasurer).id])
    assert_response :created

    post '/api/v1/auth/login', as: :json,
                               params: { user: { email: 'newleader@example.com', password: 'secret123' } }
    assert_response :ok
    assert_match(/\ABearer /, response.headers['Authorization'])
    assert_equal ['manage_finance'], response.parsed_body['user']['permissions']
  end

  test 'users who are not the super admin cannot create users, even with manage_users' do
    assert @church_admin.has_permission?(:manage_users)

    assert_no_difference -> { User.count } do
      post '/api/v1/users', headers: auth_headers(@church_admin), as: :json, params: new_user_params
    end
    assert_response :forbidden
  end

  test 'creating a user requires login' do
    post '/api/v1/users', as: :json, params: new_user_params
    assert_response :unauthorized
  end

  test 'rejects an email that already exists, ignoring case' do
    assert_no_difference -> { User.count } do
      post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                            params: new_user_params(email: 'TREASURER@example.com')
    end
    assert_response :conflict
  end

  test 'rejects unknown role ids and saves nothing' do
    assert_no_difference [-> { User.count }, -> { UserRole.count }] do
      post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                            params: new_user_params(role_ids: [roles(:treasurer).id, 999_999])
    end
    assert_response :unprocessable_entity
    assert_equal 'One or more roles do not exist', response.parsed_body['error']
  end

  test 'rejects invalid fields and saves no role assignments' do
    assert_no_difference [-> { User.count }, -> { UserRole.count }] do
      post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                            params: new_user_params(password: '123', role_ids: [roles(:treasurer).id])
    end
    assert_response :unprocessable_entity
    assert_includes response.parsed_body['errors'], 'Password is too short (minimum is 6 characters)'
  end

  test 'can optionally link the user to a member' do
    member = members(:jane)
    post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                          params: new_user_params(member_id: member.id)

    assert_response :created
    assert_equal member.id, response.parsed_body['user']['member']['id']
  end

  test 'rejects a member that does not exist or already has a user' do
    post '/api/v1/users', headers: auth_headers(@super_admin), as: :json, params: new_user_params(member_id: 999_999)
    assert_response :not_found

    @church_admin.update!(member: members(:jane))
    post '/api/v1/users', headers: auth_headers(@super_admin), as: :json,
                          params: new_user_params(member_id: members(:jane).id)
    assert_response :conflict
  end

  # --- GET /api/v1/users/me ---

  test 'me returns the logged-in user with permissions' do
    get '/api/v1/users/me', headers: auth_headers(@church_admin), as: :json

    assert_response :ok
    body = response.parsed_body
    assert_equal 'churchadmin@example.com', body['email']
    assert_equal false, body['super_admin']
    assert_equal %w[manage_events manage_users], body['permissions'].sort
  end

  test 'me gives the super admin every permission' do
    get '/api/v1/users/me', headers: auth_headers(@super_admin), as: :json

    assert_response :ok
    assert response.parsed_body['super_admin']
    assert_equal Permission.count, response.parsed_body['permissions'].size
  end

  test 'me requires login' do
    get '/api/v1/users/me', as: :json
    assert_response :unauthorized
  end

  # --- GET /api/v1/users ---

  test 'index lists users with their roles' do
    get '/api/v1/users', headers: auth_headers(@church_admin), as: :json

    assert_response :ok
    treasurer = response.parsed_body.find { |u| u['email'] == 'treasurer@example.com' }
    assert_equal ['treasurer'], treasurer['roles']
  end

  test 'self sign-up is disabled' do
    assert_not User.devise_modules.include?(:registerable)
    assert_not Rails.application.routes.named_routes.key?(:user_registration)
  end

  private

  def new_user_params(**overrides)
    { email: 'newleader@example.com', password: 'secret123', firstname: 'New', lastname: 'Leader' }.merge(overrides)
  end
end
