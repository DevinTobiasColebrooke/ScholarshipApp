Rails.application.routes.draw do
  root "organizations#index"

  resources :organizations, only: [ :index, :show ] do
    get "search", on: :collection
    get "potential_scholarship_grantors", on: :collection
    get "grants_and_programs", on: :member
  end

  # Outreach Routes
  resources :outreach_planner, only: [ :index, :create, :show ] do
    get "review", on: :collection
  end

  resources :outreach_contacts, only: [ :index, :show, :create ] do
    post :update_status, on: :member
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
