require 'test_helper'

class Api::V1::FellowshipGroupsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @group_manager = users(:group_manager) # manage_fellowship_groups only
    @secretary = users(:secretary) # manage_members only
    @treasurer = users(:treasurer) # neither
    @super_admin = users(:super_admin)
    @choir = fellowship_groups(:choir)
  end

  # --- Authentication and permissions ---

  test 'every action requires login' do
    get '/api/v1/fellowship_groups', as: :json
    assert_response :unauthorized

    post '/api/v1/fellowship_groups', as: :json, params: { fellowship_group: { group_name: 'X' } }
    assert_response :unauthorized

    post "/api/v1/fellowship_groups/#{@choir.id}/members", as: :json, params: { member_ids: [members(:peter).id] }
    assert_response :unauthorized
  end

  test 'users without either permission get 403 everywhere' do
    get '/api/v1/fellowship_groups', headers: auth_headers(@treasurer), as: :json
    assert_response :forbidden
    assert_equal({ 'error' => 'You do not have permission to perform this action' }, response.parsed_body)

    get "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@treasurer), as: :json
    assert_response :forbidden

    post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@treasurer), as: :json,
                                                           params: { member_ids: [members(:peter).id] }
    assert_response :forbidden
  end

  test 'manage_members can read groups and manage their members' do
    get '/api/v1/fellowship_groups', headers: auth_headers(@secretary), as: :json
    assert_response :ok

    get "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@secretary), as: :json
    assert_response :ok

    post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@secretary), as: :json,
                                                           params: { member_ids: [members(:peter).id] }
    assert_response :ok

    delete "/api/v1/fellowship_groups/#{@choir.id}/members/#{members(:peter).id}", headers: auth_headers(@secretary),
                                                                                   as: :json
    assert_response :ok
  end

  test 'manage_members cannot create, edit or delete groups' do
    headers = auth_headers(@secretary)

    post '/api/v1/fellowship_groups', headers: headers, as: :json,
                                      params: { fellowship_group: { group_name: 'Ushers' } }
    assert_response :forbidden

    patch "/api/v1/fellowship_groups/#{@choir.id}", headers: headers, as: :json,
                                                    params: { fellowship_group: { group_name: 'Choir 2' } }
    assert_response :forbidden

    delete "/api/v1/fellowship_groups/#{@choir.id}", headers: headers, as: :json
    assert_response :forbidden
    assert FellowshipGroup.exists?(@choir.id)
  end

  test 'manage_fellowship_groups can read the member list but not change members' do
    get '/api/v1/members', headers: auth_headers(@group_manager), as: :json
    assert_response :ok

    get "/api/v1/members/#{members(:jane).id}", headers: auth_headers(@group_manager), as: :json
    assert_response :forbidden

    patch "/api/v1/members/#{members(:jane).id}", headers: auth_headers(@group_manager), as: :json,
                                                  params: { member: { first_name: 'X' } }
    assert_response :forbidden

    post '/api/v1/members', headers: auth_headers(@group_manager), as: :json,
                            params: { member: { first_name: 'X', last_name: 'Y', phone_number: '0700' } }
    assert_response :forbidden

    delete "/api/v1/members/#{members(:peter).id}", headers: auth_headers(@group_manager), as: :json
    assert_response :forbidden
  end

  test 'super admin is always allowed' do
    post '/api/v1/fellowship_groups', headers: auth_headers(@super_admin), as: :json,
                                      params: { fellowship_group: { group_name: 'Ushers' } }
    assert_response :created
  end

  # --- Index and show ---

  test 'index lists groups by name with leader and member count' do
    get '/api/v1/fellowship_groups', headers: auth_headers(@group_manager), as: :json

    assert_response :ok
    body = response.parsed_body
    assert_equal ['Choir', 'Prayer Warriors', 'Youth'], body.pluck('group_name')
    assert_equal [2, 0, 1], body.pluck('member_count')

    choir = body.first
    assert_equal %w[id group_name group_code description leader member_count created_at updated_at], choir.keys
    assert_equal({ 'id' => members(:jane).id, 'first_name' => 'Jane', 'last_name' => 'Wanjiku' }, choir['leader'])
    assert_equal 'Leads worship every Sunday.', choir['description']
    assert_nil body.second['leader']
    assert_nil body.second['group_code']
  end

  test 'show includes members ordered by name' do
    get "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json

    assert_response :ok
    body = response.parsed_body
    assert_equal 2, body['member_count']
    assert_equal [{ 'id' => members(:grace).id, 'first_name' => 'Grace', 'last_name' => 'Kamau',
                    'phone_number' => '+254 712 345 678' },
                  { 'id' => members(:jane).id, 'first_name' => 'Jane', 'last_name' => 'Wanjiku',
                    'phone_number' => '254712345678' }], body['members']
  end

  test 'unknown group returns 404' do
    get '/api/v1/fellowship_groups/999999', headers: auth_headers(@group_manager), as: :json
    assert_response :not_found
    assert_equal({ 'error' => 'Fellowship group not found' }, response.parsed_body)

    patch '/api/v1/fellowship_groups/999999', headers: auth_headers(@group_manager), as: :json,
                                              params: { fellowship_group: { group_name: 'X' } }
    assert_response :not_found
  end

  # --- Create ---

  test 'create adds a group, normalises fields and records the creator' do
    assert_difference -> { FellowshipGroup.count } => 1 do
      post '/api/v1/fellowship_groups', headers: auth_headers(@group_manager), as: :json,
                                        params: { fellowship_group: { group_name: '  Ushers ', group_code: ' ush-1 ',
                                                                      description: '  Welcome people.  ' } }
    end

    assert_response :created
    assert_equal 'Fellowship group created', response.parsed_body['message']
    group = response.parsed_body['fellowship_group']
    assert_equal 'Ushers', group['group_name']
    assert_equal 'USH-1', group['group_code']
    assert_equal 'Welcome people.', group['description']
    assert_nil group['leader']
    assert_equal 0, group['member_count']
    assert_equal @group_manager, FellowshipGroup.find(group['id']).created_by
  end

  test 'blank codes are stored as NULL, so several groups can have no code' do
    post '/api/v1/fellowship_groups', headers: auth_headers(@group_manager), as: :json,
                                      params: { fellowship_group: { group_name: 'Ushers', group_code: '   ' } }

    assert_response :created
    assert_nil response.parsed_body['fellowship_group']['group_code']
    assert_nil FellowshipGroup.find(response.parsed_body['fellowship_group']['id']).group_code
    assert_nil fellowship_groups(:prayer).group_code
  end

  test 'a leader set on create is added to the group' do
    peter = members(:peter)
    post '/api/v1/fellowship_groups', headers: auth_headers(@group_manager), as: :json,
                                      params: { fellowship_group: { group_name: 'Ushers', leader_member_id: peter.id } }

    assert_response :created
    group = response.parsed_body['fellowship_group']
    assert_equal peter.id, group['leader']['id']
    assert_equal 1, group['member_count']
    assert_includes FellowshipGroup.find(group['id']).members, peter
  end

  test 'create requires the fellowship_group key' do
    post '/api/v1/fellowship_groups', headers: auth_headers(@group_manager), as: :json, params: { member_ids: [1] }
    assert_response :bad_request
  end

  # --- Validation rules (exact messages shown to admins) ---

  {
    { group_name: '  ' } => "Group name can't be blank",
    { group_name: 'a' * 61 } => 'Group name is too long (maximum is 60 characters)',
    { group_name: 'cHoIr' } => 'Group name has already been taken',
    { group_code: 'choir' } => 'Group code has already been taken',
    { group_code: 'ABCDEFGHIJK' } => 'Group code is too long (maximum is 10 characters)',
    { group_code: 'AB CD' } => 'Group code can only contain letters A-Z, numbers and -',
    { group_code: 'AB_1' } => 'Group code can only contain letters A-Z, numbers and -',
    { description: 'a' * 501 } => 'Description is too long (maximum is 500 characters)',
    { leader_member_id: 999_999 } => 'Leader must be a member in the directory'
  }.each do |overrides, message|
    test "create rejects #{overrides.first.first}=#{overrides.first.last.to_s[0, 12].inspect}: #{message}" do
      assert_no_difference -> { FellowshipGroup.count } do
        post '/api/v1/fellowship_groups', headers: auth_headers(@group_manager), as: :json,
                                          params: { fellowship_group: { group_name: 'Ushers' }.merge(overrides) }
      end

      assert_response :unprocessable_entity
      assert_includes response.parsed_body['errors'], message
    end
  end

  # --- Update ---

  test 'update is partial' do
    patch "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json,
                                                    params: { fellowship_group: { description: 'New description' } }

    assert_response :ok
    assert_equal 'Fellowship group updated', response.parsed_body['message']
    group = response.parsed_body['fellowship_group']
    assert_equal 'New description', group['description']
    assert_equal 'Choir', group['group_name']
    assert_equal 'CHOIR', group['group_code']
    assert_equal members(:jane).id, group['leader']['id']
  end

  test 'a group can keep its own name with different capitalisation' do
    patch "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json,
                                                    params: { fellowship_group: { group_name: 'CHOIR' } }
    assert_response :ok
  end

  test 'setting a new leader adds them to the group' do
    peter = members(:peter)
    patch "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json,
                                                    params: { fellowship_group: { leader_member_id: peter.id } }

    assert_response :ok
    assert_equal peter.id, response.parsed_body['fellowship_group']['leader']['id']
    assert_equal 3, response.parsed_body['fellowship_group']['member_count']
  end

  test 'null clears the leader and keeps them as a member' do
    patch "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json,
                                                    params: { fellowship_group: { leader_member_id: nil } }

    assert_response :ok
    assert_nil response.parsed_body['fellowship_group']['leader']
    assert_includes @choir.reload.members, members(:jane)
  end

  test 'update rejects an unknown leader and changes nothing' do
    patch "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json,
                                                    params: { fellowship_group: { group_name: 'Renamed',
                                                                                  leader_member_id: 999_999 } }

    assert_response :unprocessable_entity
    assert_equal ['Leader must be a member in the directory'], response.parsed_body['errors']
    assert_equal 'Choir', @choir.reload.group_name
  end

  # --- Destroy ---

  test 'deleting a group keeps its members in the directory' do
    member_ids = @choir.member_ids

    assert_difference -> { FellowshipGroup.count } => -1, -> { Member.count } => 0 do
      delete "/api/v1/fellowship_groups/#{@choir.id}", headers: auth_headers(@group_manager), as: :json
    end

    assert_response :ok
    assert_equal({ 'message' => 'Fellowship group deleted', 'id' => @choir.id }, response.parsed_body)
    assert_equal 0, ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM fellowship_groups_members WHERE fellowship_group_id = #{@choir.id.to_i}"
    )
    assert_equal member_ids.size, Member.where(id: member_ids).count
  end

  test 'deleting a member who leads a group leaves the group without a leader' do
    delete "/api/v1/members/#{members(:jane).id}", headers: auth_headers(@secretary), as: :json

    assert_response :ok
    assert_nil @choir.reload.leader_member_id
  end

  test 'removing a leader from their groups on the member form also clears the leadership' do
    jane = members(:jane)
    patch "/api/v1/members/#{jane.id}", headers: auth_headers(@secretary), as: :json,
                                        params: { member: { fellowship_group_ids: [fellowship_groups(:youth).id] } }

    assert_response :ok
    assert_nil @choir.reload.leader_member_id
  end

  # --- Add members ---

  test 'add members adds new ones and reports those already in the group' do
    peter = members(:peter)
    jane = members(:jane)
    post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@group_manager), as: :json,
                                                           params: { member_ids: [peter.id, jane.id] }

    assert_response :ok
    body = response.parsed_body
    assert_equal '2 members added', body['message']
    assert_equal [peter.id], body['added_ids']
    assert_equal [jane.id], body['already_in_group_ids']
    assert_equal 3, body['fellowship_group']['member_count']
  end

  test 'adding members twice is harmless' do
    2.times do
      post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@group_manager), as: :json,
                                                             params: { member_ids: [members(:peter).id] }
      assert_response :ok
    end
    assert_equal '1 member added', response.parsed_body['message']
    assert_equal [members(:peter).id], response.parsed_body['already_in_group_ids']
    assert_equal 3, @choir.reload.members.count
  end

  test 'an unknown member id adds nothing' do
    post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@group_manager), as: :json,
                                                           params: { member_ids: [members(:peter).id, 999_999] }

    assert_response :unprocessable_entity
    assert_equal({ 'error' => 'Member not found (id 999999)' }, response.parsed_body)
    assert_equal 2, @choir.reload.members.count
  end

  test 'add members requires at least one id' do
    post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@group_manager), as: :json,
                                                           params: { member_ids: [] }
    assert_response :unprocessable_entity
    assert_equal({ 'error' => 'Choose at least one member' }, response.parsed_body)

    post "/api/v1/fellowship_groups/#{@choir.id}/members", headers: auth_headers(@group_manager), as: :json,
                                                           params: {}
    assert_response :unprocessable_entity
  end

  # --- Remove member ---

  test 'remove member takes them out of the group' do
    grace = members(:grace)
    delete "/api/v1/fellowship_groups/#{@choir.id}/members/#{grace.id}", headers: auth_headers(@group_manager),
                                                                         as: :json

    assert_response :ok
    assert_equal 'Member removed', response.parsed_body['message']
    assert_equal 1, response.parsed_body['fellowship_group']['member_count']
    assert Member.exists?(grace.id)
  end

  test 'removing the leader clears the leader' do
    delete "/api/v1/fellowship_groups/#{@choir.id}/members/#{members(:jane).id}",
           headers: auth_headers(@group_manager), as: :json

    assert_response :ok
    assert_nil response.parsed_body['fellowship_group']['leader']
    assert_nil @choir.reload.leader_member_id
  end

  test 'removing someone who is not in the group returns 404' do
    delete "/api/v1/fellowship_groups/#{@choir.id}/members/#{members(:peter).id}",
           headers: auth_headers(@group_manager), as: :json

    assert_response :not_found
    assert_equal({ 'error' => "That member isn't in this group" }, response.parsed_body)
  end
end
