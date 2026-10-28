# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_fields_proposals.
# The proposals that wait for a reviewer.
# No seed data.
class CreateGkFieldsProposals < ActiveRecord::Migration[6.1]
  def change
    create_table "gk_fields_proposals" do |t|
      t.string "text_key", null: false
      t.string "kind", limit: 20, null: false
      t.string "thing"
      t.string "what"
      t.text "before_text"
      t.text "after_text", null: false
      t.text "reason"
      t.integer "proposed_by_id"
      t.string "state", limit: 10, default: "pending", null: false
      t.integer "reviewed_by_id"
      t.timestamptz "reviewed_at", precision: 6
      t.text "review_note"
      t.timestamptz "created_at", null: false, precision: 6
      t.index ["state"], name: "index_gk_fields_proposals_on_state"
    end
  end
end
