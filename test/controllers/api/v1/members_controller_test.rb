require 'test_helper'

class Api::V1::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @secretary = users(:secretary) # has manage_members through the secretary role
    @treasurer = users(:treasurer) # no manage_members
    @super_admin = users(:super_admin)
  end

  # --- Authentication and authorization ---

  test 'every action requires login' do
    get '/api/v1/members', as: :json
    assert_response :unauthorized

    post '/api/v1/members', as: :json, params: { member: valid_attributes }
    assert_response :unauthorized

    post '/api/v1/members/bulk_destroy', as: :json, params: { ids: [members(:peter).id] }
    assert_response :unauthorized
  end

  test 'users without manage_members get 403' do
    get '/api/v1/members', headers: auth_headers(@treasurer), as: :json
    assert_response :forbidden
    assert_equal 'You do not have permission to perform this action', response.parsed_body['error']

    assert_no_difference -> { Member.count } do
      delete "/api/v1/members/#{members(:peter).id}", headers: auth_headers(@treasurer), as: :json
    end
    assert_response :forbidden
  end

  test 'super admin is always allowed' do
    get '/api/v1/members', headers: auth_headers(@super_admin), as: :json
    assert_response :ok
  end

  # --- GET /members and /members/:id ---

  test 'index returns every member ordered by first and last name' do
    get '/api/v1/members', headers: auth_headers(@secretary), as: :json

    assert_response :ok
    assert_equal %w[Grace Jane Peter], response.parsed_body.pluck('first_name')
  end

  test 'member object has the documented shape' do
    grace = members(:grace)
    get "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json

    assert_response :ok
    body = response.parsed_body
    assert_equal %w[id first_name middle_name last_name phone_number email date_of_birth place_of_residence
                    fellowship_groups leadership_positions user created_at updated_at], body.keys
    assert_equal '1990-03-12', body['date_of_birth']
    assert_equal [{ 'id' => fellowship_groups(:choir).id, 'group_name' => 'Choir' },
                  { 'id' => fellowship_groups(:youth).id, 'group_name' => 'Youth' }].sort_by { |g| g['id'] },
                 body['fellowship_groups']
    assert_equal [{ 'id' => leadership_positions(:treasurer_position).id, 'position_name' => 'Treasurer' }],
                 body['leadership_positions']
    assert_equal({ 'id' => @treasurer.id, 'email' => 'treasurer@example.com', 'super_admin' => false,
                   'roles' => ['treasurer'] }, body['user'])
    assert_match(/\A\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d\.\d{3}Z\z/, body['created_at'])
  end

  test 'user is null for a member without a login account' do
    get "/api/v1/members/#{members(:peter).id}", headers: auth_headers(@secretary), as: :json
    assert_nil response.parsed_body['user']
  end

  test 'show returns 404 for an unknown id' do
    get '/api/v1/members/999999', headers: auth_headers(@secretary), as: :json

    assert_response :not_found
    assert_equal({ 'error' => 'Member not found' }, response.parsed_body)
  end

  # --- POST /members ---

  test 'create adds a member with fellowship groups' do
    assert_difference -> { Member.count } => 1 do
      post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                              params: { member: valid_attributes(fellowship_group_ids: [fellowship_groups(:youth).id]) }
    end

    assert_response :created
    assert_equal 'Member added', response.parsed_body['message']
    member = response.parsed_body['member']
    assert_equal 'Mary', member['first_name']
    assert_equal ['Youth'], member['fellowship_groups'].pluck('group_name')
    assert_empty member['leadership_positions']
    assert_nil member['user']
  end

  test 'create strips whitespace, lower-cases email and stores blanks as null' do
    post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                            params: { member: valid_attributes(first_name: '  Mary ', middle_name: '   ',
                                                               place_of_residence: '',
                                                               email: ' Mary.Njeri@Example.COM ') }

    assert_response :created
    member = Member.find(response.parsed_body['member']['id'])
    assert_equal 'Mary', member.first_name
    assert_nil member.middle_name
    assert_nil member.place_of_residence
    assert_equal 'mary.njeri@example.com', member.email
  end

  test 'create ignores fields that are not permitted' do
    post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                            params: { member: valid_attributes(id: 424_242, created_at: '2000-01-01') }

    assert_response :created
    assert_not_equal 424_242, response.parsed_body['member']['id']
  end

  test 'create returns 400 when the body has no member fields' do
    post '/api/v1/members', headers: auth_headers(@secretary), as: :json, params: { ids: [1] }
    assert_response :bad_request
    assert_equal 'Send the member details under a "member" key', response.parsed_body['error']
  end

  # --- Validation rules (exact messages shown to admins) ---

  {
    { first_name: '' } => "First name can't be blank",
    { last_name: nil } => "Last name can't be blank",
    { first_name: 'a' * 51 } => 'First name is too long (maximum is 50 characters)',
    { last_name: 'a' * 51 } => 'Last name is too long (maximum is 50 characters)',
    { middle_name: 'a' * 51 } => 'Middle name is too long (maximum is 50 characters)',
    { phone_number: '  ' } => "Phone number can't be blank",
    { phone_number: '1' * 21 } => 'Phone number is too long (maximum is 20 characters)',
    { phone_number: '0712 abc' } => 'Phone number can only contain digits, spaces and + - ( )',
    { email: 'not-an-email' } => 'Email is not a valid email address',
    { email: 'GRACE@Example.com' } => 'Email is already used by another member',
    { date_of_birth: 1.day.from_now.to_date.iso8601 } => "Date of birth can't be in the future",
    { date_of_birth: '1990-13-45' } => 'Date of birth is not a valid date',
    { place_of_residence: 'a' * 101 } => 'Place of residence is too long (maximum is 100 characters)',
    { fellowship_group_ids: [999_999] } => 'Fellowship group not found (id 999999)'
  }.each do |overrides, message|
    test "create rejects #{overrides.keys.first}: #{message}" do
      assert_no_difference -> { Member.count } do
        post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                                params: { member: valid_attributes(**overrides) }
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body['errors'], message
    end
  end

  test 'phone number may be shared by several members' do
    post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                            params: { member: valid_attributes(phone_number: members(:jane).phone_number) }
    assert_response :created
  end

  test 'accepts phone numbers with + - ( ) and spaces, and a date of birth of today' do
    post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                            params: { member: valid_attributes(phone_number: '+254 (0) 712-345',
                                                               date_of_birth: Date.current.iso8601) }
    assert_response :created
  end

  # --- PATCH /members/:id ---

  test 'update changes only the fields sent and leaves groups alone' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json,
                                         params: { member: { phone_number: '0700 111 222' } }

    assert_response :ok
    assert_equal 'Member updated', response.parsed_body['message']
    member = response.parsed_body['member']
    assert_equal '0700 111 222', member['phone_number']
    assert_equal 'Grace', member['first_name']
    assert_equal 'grace@example.com', member['email']
    assert_equal %w[Choir Youth], member['fellowship_groups'].pluck('group_name').sort
  end

  test 'update replaces fellowship groups' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json,
                                         params: { member: { fellowship_group_ids: [fellowship_groups(:youth).id] } }

    assert_response :ok
    assert_equal ['Youth'], response.parsed_body['member']['fellowship_groups'].pluck('group_name')
    assert_equal [fellowship_groups(:youth)], grace.reload.fellowship_groups.to_a
  end

  test 'update with an empty list removes every fellowship group' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json,
                                         params: { member: { fellowship_group_ids: [] } }

    assert_response :ok
    assert_empty response.parsed_body['member']['fellowship_groups']
    assert_empty grace.reload.fellowship_groups
  end

  test 'a failed update changes nothing, including groups' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json,
                                         params: { member: { first_name: '', fellowship_group_ids: [] } }

    assert_response :unprocessable_entity
    assert_equal ["First name can't be blank"], response.parsed_body['errors']
    grace.reload
    assert_equal 'Grace', grace.first_name
    assert_equal 2, grace.fellowship_groups.count
  end

  test 'update rejects unknown fellowship group ids and keeps the old groups' do
    grace = members(:grace)
    group_ids = [fellowship_groups(:youth).id, 999_999]
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json,
                                         params: { member: { fellowship_group_ids: group_ids } }

    assert_response :unprocessable_entity
    assert_equal ['Fellowship group not found (id 999999)'], response.parsed_body['errors']
    assert_equal 2, grace.reload.fellowship_groups.count
  end

  test 'a member can keep their own email with different capitalisation' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json,
                                         params: { member: { email: 'Grace@Example.com' } }

    assert_response :ok
    assert_equal 'grace@example.com', response.parsed_body['member']['email']
  end

  test 'update returns 404 for an unknown id' do
    patch '/api/v1/members/999999', headers: auth_headers(@secretary), as: :json,
                                    params: { member: { first_name: 'X' } }
    assert_response :not_found
  end

  # --- DELETE /members/:id ---

  test 'destroy deletes an unlinked member and its join rows' do
    jane = members(:jane)
    jane.leadership_positions << leadership_positions(:treasurer_position)

    assert_difference -> { Member.count } => -1 do
      delete "/api/v1/members/#{jane.id}", headers: auth_headers(@secretary), as: :json
    end

    assert_response :ok
    assert_equal({ 'message' => 'Member deleted', 'id' => jane.id }, response.parsed_body)
    assert_equal 0, join_rows('fellowship_groups_members', jane.id)
    assert_equal 0, join_rows('members_leadership_positions', jane.id)
  end

  test 'destroy refuses a member linked to a user account' do
    grace = members(:grace)

    assert_no_difference -> { Member.count } do
      delete "/api/v1/members/#{grace.id}", headers: auth_headers(@secretary), as: :json
    end

    assert_response :conflict
    assert_equal 'This member is linked to the user account treasurer@example.com. ' \
                 'Unlink or delete that account first.', response.parsed_body['error']
    assert_equal grace, @treasurer.reload.member
  end

  test 'destroy returns 404 for an unknown id' do
    delete '/api/v1/members/999999', headers: auth_headers(@secretary), as: :json
    assert_response :not_found
    assert_equal 'Member not found', response.parsed_body['error']
  end

  # --- POST /members/bulk_destroy ---

  test 'bulk destroy deletes what it can and skips linked and missing members' do
    peter_id, grace_id, jane_id = members(:peter, :grace, :jane).map(&:id)

    assert_difference -> { Member.count } => -2 do
      post '/api/v1/members/bulk_destroy', headers: auth_headers(@secretary), as: :json,
                                           params: { ids: [peter_id, grace_id, 999_999, jane_id] }
    end

    assert_response :ok
    assert_equal({
                   'message' => '2 members deleted',
                   'deleted_ids' => [peter_id, jane_id],
                   'skipped' => [
                     { 'id' => grace_id, 'reason' => 'Linked to the user account treasurer@example.com' },
                     { 'id' => 999_999, 'reason' => 'Not found' }
                   ]
                 }, response.parsed_body)
    assert Member.exists?(grace_id)
    assert_equal 0, join_rows('fellowship_groups_members', jane_id)
  end

  test 'bulk destroy uses a singular message for one member' do
    post '/api/v1/members/bulk_destroy', headers: auth_headers(@secretary), as: :json,
                                         params: { ids: [members(:peter).id] }
    assert_equal '1 member deleted', response.parsed_body['message']
  end

  test 'bulk destroy requires at least one id' do
    post '/api/v1/members/bulk_destroy', headers: auth_headers(@secretary), as: :json, params: { ids: [] }
    assert_response :unprocessable_entity
    assert_equal({ 'error' => 'Choose at least one member' }, response.parsed_body)

    post '/api/v1/members/bulk_destroy', headers: auth_headers(@secretary), as: :json, params: {}
    assert_response :unprocessable_entity
  end

  test 'bulk destroy accepts at most 500 ids' do
    assert_no_difference -> { Member.count } do
      post '/api/v1/members/bulk_destroy', headers: auth_headers(@secretary), as: :json,
                                           params: { ids: (1..501).to_a }
    end
    assert_response :unprocessable_entity
    assert_equal 'You can delete at most 500 members at a time', response.parsed_body['error']
  end

  test 'bulk destroy requires manage_members' do
    post '/api/v1/members/bulk_destroy', headers: auth_headers(@treasurer), as: :json,
                                         params: { ids: [members(:peter).id] }
    assert_response :forbidden
  end

  # --- Linking a login account (user_id) ---

  test 'create can link a login account' do
    account = users(:church_admin)
    post '/api/v1/members', headers: auth_headers(users(:registrar)), as: :json,
                            params: { member: valid_attributes(user_id: account.id) }

    assert_response :created
    member = response.parsed_body['member']
    assert_equal({ 'id' => account.id, 'email' => 'churchadmin@example.com', 'super_admin' => false,
                   'roles' => ['church_admin'] }, member['user'])
    assert_equal member['id'], account.reload.member_id
  end

  test 'update can link a login account' do
    jane = members(:jane)
    patch "/api/v1/members/#{jane.id}", headers: auth_headers(users(:registrar)), as: :json,
                                        params: { member: { user_id: @secretary.id } }

    assert_response :ok
    assert_equal 'secretary@example.com', response.parsed_body['member']['user']['email']
    assert_equal jane, @secretary.reload.member
  end

  test 'linking a new account moves the link from the old one' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(@super_admin), as: :json,
                                         params: { member: { user_id: @secretary.id } }

    assert_response :ok
    assert_equal 'secretary@example.com', response.parsed_body['member']['user']['email']
    assert_nil @treasurer.reload.member_id
    assert_equal grace, @secretary.reload.member
  end

  test 'null unlinks the current account' do
    grace = members(:grace)
    patch "/api/v1/members/#{grace.id}", headers: auth_headers(users(:registrar)), as: :json,
                                         params: { member: { user_id: nil } }

    assert_response :ok
    assert_nil response.parsed_body['member']['user']
    assert_nil @treasurer.reload.member_id
  end

  test 'leaving user_id out keeps the current link' do
    patch "/api/v1/members/#{members(:grace).id}", headers: auth_headers(@secretary), as: :json,
                                                   params: { member: { place_of_residence: 'Limuru' } }

    assert_response :ok
    assert_equal 'treasurer@example.com', response.parsed_body['member']['user']['email']
  end

  test 'unknown login account is a validation error and nothing is saved' do
    assert_no_difference -> { Member.count } do
      post '/api/v1/members', headers: auth_headers(users(:registrar)), as: :json,
                              params: { member: valid_attributes(user_id: 999_999) }
    end

    assert_response :unprocessable_entity
    assert_equal({ 'errors' => ['Login account not found'] }, response.parsed_body)
  end

  test 'an account linked to another member is refused' do
    jane = members(:jane)
    patch "/api/v1/members/#{jane.id}", headers: auth_headers(users(:registrar)), as: :json,
                                        params: { member: { first_name: 'Janet', user_id: @treasurer.id } }

    assert_response :conflict
    assert_equal({ 'error' => 'This login account is already linked to another member' }, response.parsed_body)
    assert_equal members(:grace), @treasurer.reload.member
    assert_equal 'Jane', jane.reload.first_name
  end

  test 'changing a link requires manage_users' do
    assert_not @secretary.has_permission?(:manage_users)

    patch "/api/v1/members/#{members(:jane).id}", headers: auth_headers(@secretary), as: :json,
                                                  params: { member: { user_id: users(:church_admin).id } }
    assert_response :forbidden
    assert_equal({ 'error' => 'You need permission to manage users to link login accounts' }, response.parsed_body)
    assert_nil users(:church_admin).reload.member_id

    assert_no_difference -> { Member.count } do
      post '/api/v1/members', headers: auth_headers(@secretary), as: :json,
                              params: { member: valid_attributes(user_id: users(:church_admin).id) }
    end
    assert_response :forbidden

    patch "/api/v1/members/#{members(:grace).id}", headers: auth_headers(@secretary), as: :json,
                                                   params: { member: { user_id: nil } }
    assert_response :forbidden
    assert_equal members(:grace), @treasurer.reload.member
  end

  test 'resending the current link is not a change and needs no manage_users' do
    unchanged_link = { phone_number: '0700 000 999', user_id: @treasurer.id }
    patch "/api/v1/members/#{members(:grace).id}", headers: auth_headers(@secretary), as: :json,
                                                   params: { member: unchanged_link }
    assert_response :ok

    patch "/api/v1/members/#{members(:jane).id}", headers: auth_headers(@secretary), as: :json,
                                                  params: { member: { user_id: nil } }
    assert_response :ok
  end

  test 'a failed update does not apply the link' do
    jane = members(:jane)
    patch "/api/v1/members/#{jane.id}", headers: auth_headers(users(:registrar)), as: :json,
                                        params: { member: { last_name: '', user_id: @secretary.id } }

    assert_response :unprocessable_entity
    assert_nil @secretary.reload.member_id
  end

  private

  def valid_attributes(**overrides)
    {
      first_name: 'Mary', middle_name: 'Wambui', last_name: 'Njeri', phone_number: '0712 345 678',
      email: 'mary@example.com', date_of_birth: '1985-06-01', place_of_residence: 'Kabuku'
    }.merge(overrides)
  end

  def join_rows(table, member_id)
    ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table} WHERE member_id = #{member_id.to_i}")
  end
end
