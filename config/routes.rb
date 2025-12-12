Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  root "organizations#index"

  resources :organizations, only: [ :index, :show ] do
    get "search", on: :collection
    get "potential_scholarship_grantors", on: :collection
    get "grants_and_programs", on: :member
  end

  # Outreach
  resources :outreach_planner, only: [ :index, :create, :show ], controller: "outreach_planner"
  resources :outreach_contacts, only: [ :index, :show, :create ] do
    post :update_status, on: :member
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
end
