# frozen_string_literal: true

# One of Redmine's own texts in one language as this instance shows it (GkFields::CoreTexts): the text instead of
# core's, or the mark that core's text is right as it is. Core's locale files are never changed.
class GkFieldsCoreText < ApplicationRecord
  self.table_name = 'gk_fields_core_texts'
  # an instant with its zone (timestamptz, migration 005)
  GkFieldsInstant.attributes!(self, :updated_at)

  belongs_to :updated_by, class_name: 'User', optional: true

  validates :locale, :text_key, presence: true
  validates :text_key, uniqueness: { scope: :locale }

  def display = "#{locale}: #{text_key}"
end
