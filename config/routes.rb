Rails.application.routes.draw do
  root to: redirect('/api/docs/', status: 302)
  namespace :api do
    namespace :v3 do
      namespace :private, defaults: { format: :json } do
        # Don't generate links or relationship routes for decks.
        jsonapi_resources :decks do
        end
        resources :user, only: [:index]
      end
      namespace :public, defaults: { format: :json } do
        jsonapi_resources :card_cycles, only: [:index, :show]
        jsonapi_resources :card_pools, only: [:index, :show]
        jsonapi_resources :card_set_types, only: [:index, :show]
        jsonapi_resources :card_sets, only: [:index, :show]
        jsonapi_resources :card_subtypes, only: [:index, :show]
        jsonapi_resources :card_types, only: [:index, :show]
        jsonapi_resources :cards, only: [:index, :show]
        jsonapi_resources :factions, only: [:index, :show]
        jsonapi_resources :formats, only: [:index, :show]
        jsonapi_resources :illustrators, only: [:index, :show]
        jsonapi_resources :printings, only: [:index, :show]
        jsonapi_resources :restrictions, only: [:index, :show]
        jsonapi_resources :rulings, only: [:index]
        jsonapi_resources :sides, only: [:index, :show]
        jsonapi_resources :snapshots, only: [:index, :show]
        post :validate_deck, to: 'validate_deck#index'
      end
    end
  end
end
