# frozen_string_literal: true

# The pages and their REST resources (.json) are the same routes; PUT on translations and on Redmine's texts, POST on
# proposals and GET on one layout are for REST (the pages post, and edit a layout on its own page).
get  'gk_fields/translations', to: 'gk_fields_translations#index', as: 'gk_fields_translations'
post 'gk_fields/translations', to: 'gk_fields_translations#update'
put  'gk_fields/translations', to: 'gk_fields_translations#update'
# Redmine's texts: core's own locale keys corrected in this instance
get  'gk_fields/translations/core', to: 'gk_fields_translations#core', as: 'gk_fields_core_texts'
post 'gk_fields/translations/core', to: 'gk_fields_translations#core_update'
put  'gk_fields/translations/core', to: 'gk_fields_translations#core_update'
get  'gk_fields/translations/core/yaml', to: 'gk_fields_translations#core_yaml', as: 'gk_fields_core_texts_yaml'
get  'gk_fields/translations/exchange',to: 'gk_fields_translations#exchange', as: 'gk_fields_exchange'
post 'gk_fields/translations/exchange/review', to: 'gk_fields_translations#review', as: 'gk_fields_exchange_review'
get  'gk_fields/translations/texts', to: 'gk_fields_translations#texts', as: 'gk_fields_texts'
get  'gk_fields/translations/find', to: 'gk_fields_translations#find', as: 'gk_fields_find'
get  'gk_fields/translations/changes', to: 'gk_fields_translations#changes', as: 'gk_fields_changes'
match 'gk_fields/translations/propose', to: 'gk_fields_translations#propose', as: 'gk_fields_propose', via: %i[get post]
get  'gk_fields/translations/proposals', to: 'gk_fields_translations#proposals', as: 'gk_fields_proposals'
post 'gk_fields/translations/proposals', to: 'gk_fields_translations#propose'
post 'gk_fields/translations/proposals/:id/decide', to: 'gk_fields_translations#decide', as: 'gk_fields_decide'
post 'gk_fields/translations/exchange/import', to: 'gk_fields_translations#import', as: 'gk_fields_exchange_import'
# the layouts of an issue's head (Administration, Layouts); issues: the issues a preview can use (administrators)
get    'gk_fields/layouts/issues', to: 'gk_fields_layouts#issues', as: 'gk_fields_layouts_issues'
get    'gk_fields/layouts', to: 'gk_fields_layouts#index', as: 'gk_fields_layouts'
post   'gk_fields/layouts', to: 'gk_fields_layouts#create'
get    'gk_fields/layouts/new', to: 'gk_fields_layouts#new', as: 'new_gk_fields_layout'
get    'gk_fields/layouts/:id/edit', to: 'gk_fields_layouts#edit', as: 'edit_gk_fields_layout'
get    'gk_fields/layouts/:id', to: 'gk_fields_layouts#show', as: 'gk_fields_layout'
patch  'gk_fields/layouts/:id', to: 'gk_fields_layouts#update'
put    'gk_fields/layouts/:id', to: 'gk_fields_layouts#update'
delete 'gk_fields/layouts/:id', to: 'gk_fields_layouts#destroy'
