Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  resources :organizations, only: [:index, :show] do
    collection do
      get "search"
      get "potential_scholarship_grantors"
    end
    member do
      get "grants_and_programs"
    end
  end

  resource :outreach_planner, only: [:index, :show], controller: 'outreach_planner'

  resources :outreach_contacts, only: [:index, :show, :create] do
    collection do
      # POST to index is for starting the OutreachCampaignJob
    end
    member do
      post :update_status
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Defines the root path route ("/")
  root "organizations#index"
end
