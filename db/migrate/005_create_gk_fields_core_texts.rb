# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_fields_core_texts.
# Redmine's own texts corrected in this instance: one row per locale and core locale key. value is the text shown
# instead of core's (empty: core's text is shown); confirmed says that core's text is right as it is, also when it is
# the same as the English. english_text and core_text are core's texts when the row was saved, so a page can say that
# core has changed them since. Every change of value is also a row in gk_fields_changes.
# No seed data. down drops the table and with it every correction; the rows in gk_fields_changes are kept.
class CreateGkFieldsCoreTexts < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_fields_core_texts" do |t|
      t.string "locale", limit: 10, null: false
      t.string "text_key", null: false
      t.text "value"
      t.boolean "confirmed", default: false, null: false
      t.text "english_text"
      t.text "core_text"
      t.integer "updated_by_id"
      t.timestamptz "updated_at", null: false, precision: 6
      t.index ["locale", "text_key"], name: "index_gk_fields_core_texts_on_key", unique: true
    end
  end

  def down
    drop_table "gk_fields_core_texts"
  end
end
