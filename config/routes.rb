Rails.application.routes.draw do
  devise_for :users, skip: [:sessions]

  # JWT auth routes - must be inside the devise scope for devise-jwt to intercept them
  devise_scope :user do
    post '/api/v1/auth/login', to: 'api/v1/auth/sessions#create'
    delete '/api/v1/auth/logout', to: 'api/v1/auth/sessions#destroy'
  end

  root 'home#index'
  resources :home, only: [:index]

  namespace :api do
    namespace :v1 do
      # M-Pesa payments
      post '/payment', to: 'payments#create'
      post '/callback', to: 'payments#callback'

      # Access control (RBAC)
      resources :roles, only: %i[index create]
      resources :user_roles, only: %i[create destroy]
      resources :users, only: %i[index create show] do
        get :me, on: :collection
      end

      # Church management
      resources :members, only: %i[index show create update destroy] do
        post :bulk_destroy, on: :collection
      end
      resources :devotions, only: %i[index create]
      resources :leadership_positions, only: %i[index create]
      resources :fellowship_groups, only: %i[index show create update destroy] do
        member do
          post :members, action: :add_members
          delete 'members/:member_id', action: :remove_member, as: :remove_member
        end
      end
      resources :events, only: %i[index create]
    end
  end
end
