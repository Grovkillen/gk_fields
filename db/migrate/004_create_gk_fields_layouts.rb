# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_fields_layouts.
# The layouts of an issue's head: per tracker, and per status when it needs one of its own; for the whole instance
# (project_id null) or one project; for the issue page (show) and its form (edit, which falls back on show). The
# layout itself is JSON: its sections in order, each with its title per language, its columns, folded or not, its
# level, and its fields with their width and their appearance per context.
class CreateGkFieldsLayouts < ActiveRecord::Migration[6.1]
  def change
    create_table "gk_fields_layouts" do |t|
      t.integer "tracker_id", null: false
      t.integer "status_id"
      t.integer "project_id"
      t.string "scope", limit: 10, default: "show", null: false
      t.text "layout", null: false
      t.integer "updated_by_id"
      t.timestamptz "updated_at", null: false, precision: 6
      t.index ["tracker_id", "status_id", "project_id", "scope"], name: "index_gk_fields_layouts_on_place", unique: true
    end
  end
end
