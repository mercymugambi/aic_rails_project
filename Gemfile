source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

ruby '3.2.2'

gem 'json', '< 3.0'
gem 'rails', '~> 7.0.7'

# The original asset pipeline for Rails [https://github.com/rails/sprockets-rails]
gem 'sprockets-rails'

# Use PostgreSQL as the database for Active Record
gem 'pg'

# Use the Puma web server [https://github.com/puma/puma]
gem 'puma', '~> 5.0'

# Use JavaScript with ESM import maps [https://github.com/rails/importmap-rails]
gem 'importmap-rails'

# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem 'turbo-rails'

# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem 'stimulus-rails'

# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem 'jbuilder'

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem 'tzinfo-data', platforms: %i[mingw mswin x64_mingw jruby]

# Reduces boot times through caching; required in config/boot.rb
gem 'bootsnap', require: false

# Authentication (Devise + JWT tokens for the API)
gem 'devise'
gem 'devise-jwt'

# Cross-origin requests from the frontend
gem 'rack-cors'

# Load environment variables from .env in development and test
gem 'dotenv-rails', groups: %i[development test]

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem 'web-console'

  # Ruby linter/formatter; configured in .rubocop.yml
  gem 'rubocop', '>= 1.0', '< 2.0', require: false
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem 'capybara'
  gem 'selenium-webdriver'
  gem 'webdrivers'
  # Rails 7.0's test runner is incompatible with minitest 5.25+/6.x
  gem 'minitest', '< 5.25'
  # childprocess (used by selenium-webdriver) requires ffi on Windows but doesn't declare it
  gem 'ffi', platforms: %i[mingw x64_mingw mswin]
end
