# frozen_string_literal: true

# One text of a core thing in the other languages: { "en" => "Assessed" }. The core string itself is not here.
class GkFieldsTranslation < ApplicationRecord
  self.table_name = 'gk_fields_translations'
  # an instant with its zone (timestamptz, migration 001)
  GkFieldsInstant.attributes!(self, :updated_at)

  belongs_to :updated_by, class_name: 'User', optional: true

  validates :record_type, inclusion: { in: ->(_) { GkFields::Translations.all_types.keys } }
  validates :record_id, presence: true
  validates :attribute_name, inclusion: { in: %w[name description possible_value] }

  def translations_hash
    h = JSON.parse(translations.presence || '{}')
    h.is_a?(Hash) ? h : {}
  rescue JSON::ParserError
    {}
  end

  def record = record_type.safe_constantize&.find_by(id: record_id)

  # "Status: Assessed" or "Custom field: Kind of risk: Supplier", by the core strings
  def display
    o = record
    core = o ? o.read_attribute(:name).to_s : "##{record_id}"
    [record_type.constantize.model_name.human, core, value_key.presence].compact.join(': ')
  end
end
