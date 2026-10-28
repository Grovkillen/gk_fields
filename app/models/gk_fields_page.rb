# frozen_string_literal: true

# One of the plugin's pages as a thing GK Records writes events on (GkFields.paste_refused!: Copy and paste). KEYS
# names each page, its label and its address.
class GkFieldsPage < ApplicationRecord
  self.table_name = 'gk_fields_pages'

  KEYS = {
    'exchange' => { label: :label_gk_fields_exchange, url: { controller: 'gk_fields_translations', action: 'exchange' } }
  }.freeze

  validates :key, presence: true, inclusion: { in: KEYS.keys }

  def self.for(key) = find_or_create_by!(key: key.to_s)

  def label = "#{::I18n.t(:label_gk_fields_translations)}: #{::I18n.t(KEYS.dig(key, :label))}"
  def url = KEYS.dig(key, :url)
end
