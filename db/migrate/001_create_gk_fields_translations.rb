# frozen_string_literal: true

# Merged at 1.00.000: the final state of gk_fields_translations.
# The translations. No seed data.
# The first migration's down runs last at redmine:plugins:migrate NAME=gk_fields VERSION=0: it also takes away the
# plugin's row in core's settings, and makes the custom fields of the format Date and time (gk_fields_datetime) core's
# text format (string), so that the pages that show them keep working: the values stay as they are stored, in UTC as
# text ("2026-11-04 08:30:00Z"). That cannot be undone: migrating up again leaves them text fields, since they can no
# longer be told from other text fields. A saved query that compares such a field with a date (>=, <= or between),
# also as a project's default query or in a block on My page, fails once the field is text, since core compares a
# text field's >=, <= and >< as numbers: down names each such query, to be changed before or right after
# uninstalling, and changes none of them itself. The plugin keeps nothing in a person's preferences.
class CreateGkFieldsTranslations < ActiveRecord::Migration[6.1]
  def up
    create_table "gk_fields_translations" do |t|
      t.string "record_type", limit: 40, null: false
      t.integer "record_id", null: false
      t.string "attribute_name", limit: 30, null: false
      t.string "value_key"
      t.text "translations"
      t.integer "updated_by_id"
      t.timestamptz "updated_at", null: false, precision: 6
      t.index ["record_type", "record_id", "attribute_name"], name: "index_gk_fields_translations_record"
    end
  end

  def down
    ids = CustomField.where(field_format: 'gk_fields_datetime').pluck(:id)
    say_queries_comparing_dates(ids) if ids.any?
    CustomField.where(id: ids).update_all(field_format: 'string')
    drop_table "gk_fields_translations"
    Setting.where(name: 'plugin_gk_fields').delete_all
  end

  private

  # The saved queries whose filter compares one of the fields with a date (>=, <= or between), named for the person
  # who uninstalls. The type column is not read, so every query is core's Query here, also one of a plugin that is no
  # longer loaded; a query whose filters cannot be read is passed over.
  def say_queries_comparing_dates(ids)
    field = /(?:\A|\.)cf_(?:#{ids.join('|')})\z/
    Query.unscoped.select(:id, :name, :filters).find_each do |q|
      filters = q.filters.is_a?(Hash) ? q.filters : {}
      hit = filters.select do |f, o|
        f.to_s.match?(field) && o.is_a?(Hash) && %w[>= <= ><].include?((o[:operator] || o['operator']).to_s)
      end.keys
      next if hit.empty?

      say "Query ##{q.id} (#{q.name}) compares #{hit.join(', ')} with a date: change it, it fails once the field is text"
    rescue StandardError
      next
    end
  end
end
