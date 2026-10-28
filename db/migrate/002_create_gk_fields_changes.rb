# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_fields_changes.
# The changes everyone may read.
# No seed data.
class CreateGkFieldsChanges < ActiveRecord::Migration[6.1]
  def change
    create_table "gk_fields_changes" do |t|
      t.string "text_key", null: false
      t.string "thing"
      t.string "what"
      t.string "lang", limit: 10, null: false
      t.text "before_text"
      t.text "after_text"
      t.integer "user_id"
      t.string "origin", limit: 20, default: "human", null: false
      t.integer "proposal_id"
      t.timestamptz "created_at", null: false, precision: 6
      t.index ["text_key", "created_at"], name: "index_gk_fields_changes_key"
    end
  end
end
