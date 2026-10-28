# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_fields_pages.
# The plugin's pages as things GK Records can write an event on (a pasted text on Copy and paste that could not be
# read is an event on that page, not on the person): one row per page, made when the first event needs it.
# No seed data. down drops the table; the events in gk_records_events are kept.
class CreateGkFieldsPages < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_fields_pages" do |t|
      t.string "key", limit: 40, null: false
      t.index ["key"], name: "index_gk_fields_pages_on_key", unique: true
    end
  end

  def down
    drop_table "gk_fields_pages"
  end
end
