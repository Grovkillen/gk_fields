# frozen_string_literal: true

# One change of one text in one language, kept for everyone to read. Never changed or deleted.
class GkFieldsChange < ApplicationRecord
  self.table_name = 'gk_fields_changes'
  # an instant with its zone (timestamptz, migration 002)
  GkFieldsInstant.attributes!(self, :created_at)

  belongs_to :user, optional: true
  before_update { throw :abort }
  before_destroy { throw :abort }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
end
