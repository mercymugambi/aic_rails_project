module Api
  module V1
    # Settings shown across the public website. Anyone can read them (the site loads them on every page);
    # saving needs manage_settings. Both actions answer with the settings document itself, not wrapped.
    class SiteSettingsController < ApplicationController
      skip_before_action :verify_authenticity_token
      before_action :authenticate_user!, only: :update
      before_action -> { authorize!(:manage_settings) }, only: :update

      rescue_from ActionController::ParameterMissing do
        render json: { error: 'Send the settings under a "site_settings" key' }, status: :bad_request
      end

      # GET /api/v1/site_settings
      # {} until something is saved: the frontend fills in its own defaults. Never 404, which the admin page
      # reads as "API not built yet".
      def show
        render json: SiteSetting.document
      end

      # PATCH /api/v1/site_settings  { "site_settings": { "notice": {...}, "seo": {...}, ... } }
      # Each section sent replaces the stored one; sections not sent are kept.
      def update
        sections = params.require(:site_settings)
        unless sections.is_a?(ActionController::Parameters)
          return render json: { errors: ['Settings must be a group of sections'] }, status: :unprocessable_entity
        end

        setting, saved = SiteSetting.save_sections(sections.to_unsafe_h, current_user)
        if saved
          render json: setting.data
        else
          render json: { errors: setting.errors.full_messages }, status: :unprocessable_entity
        end
      end
    end
  end
end
