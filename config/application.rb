require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module AicRailsProject
  class Application < Rails::Application
    config.load_defaults 7.0

        # CORS settings
        config.middleware.insert_before 0, Rack::Cors do
          allow do
            origins '*' # or specify your React app's origin# The origin of your frontend app
            resource '*',
              headers: :any,
              methods: [:get, :post, :put, :patch, :delete, :options, :head],
              credentials: false
  end
end
end
end