module Api
  module V1
    # Church members. Every action requires login and the manage_members permission, except the
    # list, which fellowship-group managers can also read so they can pick members for a group.
    class MembersController < ApplicationController
      MAX_BULK_DESTROY = 500

      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!
      before_action -> { authorize!(:manage_members, :manage_fellowship_groups) }, only: :index
      before_action -> { authorize!(:manage_members) }, except: :index
      before_action :set_member, only: %i[show update destroy]

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the member details under a "member" key' }, status: :bad_request
      end

      # GET /api/v1/members
      def index
        members = Member.includes(*MemberSerializer::PRELOAD).order(:first_name, :last_name, :id)
        render json: members.map { |member| MemberSerializer.new(member).as_json }
      end

      # GET /api/v1/members/:id
      def show
        render json: serialize(@member)
      end

      # POST /api/v1/members
      def create
        member = Member.new(member_params)
        return if user_link_refused?(member)

        if member.save
          render json: { message: 'Member added', member: serialize(member) }, status: :created
        else
          render json: { errors: member.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # PATCH /api/v1/members/:id
      # Partial update. Sending fellowship_group_ids replaces the member's groups ([] removes all);
      # sending user_id links a login account (null unlinks).
      def update
        @member.assign_attributes(member_params)
        return if user_link_refused?(@member)

        if @member.save
          render json: { message: 'Member updated', member: serialize(@member) }
        else
          render json: { errors: @member.errors.full_messages }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/members/:id
      def destroy
        if @member.user
          return render json: {
            error: "This member is linked to the user account #{@member.user.email}. " \
                   'Unlink or delete that account first.'
          }, status: :conflict
        end

        @member.destroy!
        render json: { message: 'Member deleted', id: @member.id }
      end

      # POST /api/v1/members/bulk_destroy  { "ids": [1, 2, 3] }
      # Deletes every member that can be deleted and reports the rest as skipped.
      def bulk_destroy
        ids = Array(params[:ids]).compact_blank.map(&:to_i).uniq
        return render_error('Choose at least one member') if ids.empty?
        if ids.size > MAX_BULK_DESTROY
          return render_error("You can delete at most #{MAX_BULK_DESTROY} members at a time")
        end

        deleted_ids, skipped = destroy_members(ids)
        render json: {
          message: "#{deleted_ids.size} #{'member'.pluralize(deleted_ids.size)} deleted",
          deleted_ids: deleted_ids,
          skipped: skipped
        }
      end

      private

      def set_member
        @member = Member.includes(*MemberSerializer::PRELOAD).find_by(id: params[:id])
        render json: { error: 'Member not found' }, status: :not_found unless @member
      end

      def member_params
        params.require(:member).permit(:first_name, :middle_name, :last_name, :phone_number, :email,
                                       :date_of_birth, :place_of_residence, :user_id, fellowship_group_ids: [])
      end

      # Changing which login account a member is linked to needs manage_users as well.
      # Renders 403/409 and returns true when the requested link can't be made.
      def user_link_refused?(member)
        return false unless member.user_link_change?

        unless current_user.has_permission?(:manage_users)
          render json: { error: 'You need permission to manage users to link login accounts' }, status: :forbidden
          return true
        end
        return false unless member.requested_user_linked_elsewhere?

        render json: { error: 'This login account is already linked to another member' }, status: :conflict
        true
      end

      def serialize(member)
        MemberSerializer.new(Member.includes(*MemberSerializer::PRELOAD).find(member.id)).as_json
      end

      def render_error(message)
        render json: { error: message }, status: :unprocessable_entity
      end

      # Returns [deleted_ids, skipped] and deletes in a single transaction.
      def destroy_members(ids)
        members = Member.includes(:user).where(id: ids).index_by(&:id)
        deleted_ids = []
        skipped = []

        Member.transaction do
          ids.each do |id|
            member = members[id]
            if member.nil?
              skipped << { id: id, reason: 'Not found' }
            elsif member.user
              skipped << { id: id, reason: "Linked to the user account #{member.user.email}" }
            else
              member.destroy!
              deleted_ids << id
            end
          end
        end

        [deleted_ids, skipped]
      end
    end
  end
end
