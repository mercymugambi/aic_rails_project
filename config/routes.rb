Rails.application.routes.draw do
  devise_for :users, skip: [:sessions]

  # JWT Auth routes - must be at devise scope for devise-jwt to intercept
  devise_scope :user do
    post '/api/v1/auth/login', to: 'api/v1/auth/sessions#create'
    delete '/api/v1/auth/logout', to: 'api/v1/auth/sessions#destroy'
  end

  root "home#index"
  resources :home, only: [:index]
  namespace :api do
    namespace :v1 do
      post '/payment', to: 'payments#create'
      post '/callback', to: 'payments#callback'

      resources :roles, only: [:index, :create]
      resources :user_roles, only: [:create, :destroy]

      resources :users, only: [:index, :create, :show]
      resources :members
      resources :devotions
      resources :leadership_positions
      resources :fellowship_groups
      resources :events
    end
  end
end
