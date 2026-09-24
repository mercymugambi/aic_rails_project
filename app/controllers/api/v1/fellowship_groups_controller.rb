module Api
  module V1
    # Fellowship groups and their membership.
    # Reading groups and managing who is in them is open to manage_fellowship_groups or manage_members
    # (the Members page needs the group list); creating, editing and deleting groups needs
    # manage_fellowship_groups.
    class FellowshipGroupsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action -> { authorize!(:manage_fellowship_groups, :manage_members) },
                    only: %i[index show add_members remove_member]
      before_action -> { authorize!(:manage_fellowship_groups) }, only: %i[create update destroy]
      before_action :set_group, except: %i[index create]

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the group details under a "fellowship_group" key' }, status: :bad_request
      end

      # GET /api/v1/fellowship_groups
      def index
        groups = FellowshipGroup.includes(:leader).order(:group_name, :id).to_a
        render json: FellowshipGroupSerializer.many(groups)
      end

      # GET /api/v1/fellowship_groups/:id
      def show
        render json: serialize(@group, include_members: true)
      end

      # POST /api/v1/fellowship_groups
      def create
        group = FellowshipGroup.new(group_params.merge(created_by: current_user))

        if group.save
          render json: { message: 'Fellowship group created', fellowship_group: serialize(group) }, status: :created
        else
          render json: { errors: group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/fellowship_groups/:id
      # Partial update; leader_member_id: null clears the leader.
      def update
        if @group.update(group_params)
          render json: { message: 'Fellowship group updated', fellowship_group: serialize(@group) }
        else
          render json: { errors: @group.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/fellowship_groups/:id
      # Removes the group and its membership rows; the members stay in the directory.
      def destroy
        @group.destroy!
        render json: { message: 'Fellowship group deleted', id: @group.id }
      end

      # POST /api/v1/fellowship_groups/:id/members  { "member_ids": [1, 2, 3] }
      # Idempotent: members already in the group are reported, not added twice.
      def add_members
        ids = Array(params[:member_ids]).compact_blank.map(&:to_i).uniq
        return render_error('Choose at least one member') if ids.empty?

        missing = ids - Member.where(id: ids).pluck(:id)
        return render_error("Member not found (id #{missing.join(', ')})") if missing.any?

        already_in_group_ids = ids & @group.members.pluck(:id)
        added_ids = ids - already_in_group_ids
        @group.members << Member.where(id: added_ids).to_a if added_ids.any?

        render json: {
          message: "#{ids.size} #{'member'.pluralize(ids.size)} added",
          added_ids: added_ids,
          already_in_group_ids: already_in_group_ids,
          fellowship_group: serialize(@group)
        }
      end

      # DELETE /api/v1/fellowship_groups/:id/members/:member_id
      # Removing the leader also clears the group's leader.
      def remove_member
        member = @group.members.find_by(id: params[:member_id])
        return render json: { error: "That member isn't in this group" }, status: :not_found unless member

        FellowshipGroup.transaction do
          @group.members.delete(member)
          @group.update_columns(leader_member_id: nil, updated_at: Time.current) if @group.leader_member_id == member.id
        end

        render json: { message: 'Member removed', fellowship_group: serialize(@group) }
      end

      private

      def set_group
        @group = FellowshipGroup.find_by(id: params[:id])
        render json: { error: 'Fellowship group not found' }, status: :not_found unless @group
      end

      def group_params
        params.require(:fellowship_group).permit(:group_name, :group_code, :description, :leader_member_id)
      end

      def serialize(group, include_members: false)
        FellowshipGroupSerializer.new(FellowshipGroup.includes(:leader).find(group.id),
                                      include_members: include_members).as_json
      end

      def render_error(message)
        render json: { error: message }, status: :unprocessable_entity
      end
    end
  end
end
