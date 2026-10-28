# frozen_string_literal: true

# A layout of an issue's head (GkFields::Layouts reads, checks and draws it). layout is the JSON as written; data is it
# read. A layout that does not hold (GkFields::Layouts.errors) is never saved.
class GkFieldsLayout < ApplicationRecord
  self.table_name = 'gk_fields_layouts'
  # an instant with its zone (timestamptz, migration 004)
  GkFieldsInstant.attributes!(self, :updated_at)

  SCOPES = %w[show edit].freeze

  belongs_to :tracker
  belongs_to :status, class_name: 'IssueStatus', optional: true
  belongs_to :project, optional: true

  validates :scope, inclusion: { in: SCOPES }
  # one layout per place (the index cannot say it where status or project is null)
  validates :tracker_id, uniqueness: { scope: %i[status_id project_id scope] }
  validate :layout_holds

  before_save { self.updated_at = Time.current }

  def data
    JSON.parse(layout.to_s)
  rescue JSON::ParserError
    nil
  end

  # Where it applies, for a person: "Meeting, all statuses, the whole instance, the issue page"
  def place_text
    [tracker&.name, status&.name || ::I18n.t(:label_gk_fields_layout_all_statuses),
     project&.name || ::I18n.t(:label_gk_fields_layout_instance), ::I18n.t(:"label_gk_fields_layout_scope_#{scope}")].join(', ')
  end

  private

  # a level closed for new things may stay where the stored layout already names it
  def layout_holds
    stored = persisted? ? (JSON.parse(layout_in_database.to_s) rescue nil) : nil
    GkFields::Layouts.errors(data, tracker: tracker, kept: GkFields::Layouts.levels_in(stored)).each { |m| errors.add(:layout, m) }
  end
end
