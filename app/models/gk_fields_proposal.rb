# frozen_string_literal: true

# A proposed change of a text as it is written, or of a list value: it changes nothing until a reviewer approves.
class GkFieldsProposal < ApplicationRecord
  self.table_name = 'gk_fields_proposals'
  # instants with their zone (timestamptz, migration 003)
  GkFieldsInstant.attributes!(self, :created_at, :reviewed_at)

  KINDS = %w[original list_value].freeze
  STATES = %w[pending approved rejected].freeze

  belongs_to :proposed_by, class_name: 'User', optional: true
  belongs_to :reviewed_by, class_name: 'User', optional: true
  validates :text_key, :after_text, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :state, inclusion: { in: STATES }
  # The reason is required while the place fields.proposal in gk_records requires it (its default); always without
  # records, as before
  validates :reason, presence: true, if: :reason_required?
  before_destroy { throw :abort }

  scope :pending, -> { where(state: 'pending') }
  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  def reason_required?
    defined?(::GkRecords::Reasons) && ::GkRecords::Reasons.find('fields.proposal') ? ::GkRecords::Reasons.required?('fields.proposal') : true
  end
end
