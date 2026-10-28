# frozen_string_literal: true

module GkFields
  # Core patches, all in one place. Each says what it assumes of core; the modules themselves stay beside the code
  # they belong to. init.rb calls apply! while Redmine prepares the application, and Redmine runs init.rb again on
  # every preparation (a reload in development), when the reloaded core classes need the patches again; each prepend is
  # guarded against a second one, so a class already patched is left as it is. A part that fails is written to the log
  # and the others are still applied.
  # * Tracker, IssueStatus, Enumeration, Role, IssueCategory, CustomField (Translations.install_reader): the readers
  #   of name and description, which core's views call to show the thing; a reader gives the translation when
  #   translation is on for the request and the record is saved, else core's value. A plugin's model registered with
  #   Translations.register_type gets the same reader.
  # * Redmine::FieldFormat::ListFormat (Translations::ListFormatPatch): possible_values_options,
  #   possible_custom_value_options and formatted_value give a list field's choices and values; only the label
  #   changes, the stored value stays the core string.
  # * ApplicationController#process_action (Translations::ControllerPatch): every action of every controller runs
  #   through it, also of controllers loaded before this plugin; translation is switched on for the request there.
  # * Mailer#process (Translations::MailerPatch): a mail is written inside it in the recipient's language.
  # * I18n.backend (CoreTexts.install!): the chain with the corrections in front of whatever backend Redmine has set
  #   up; put in again at each request and mail (CoreTexts.refresh!) if anything replaced it.
  # * Query#sql_for_custom_field and Query#quoted_time (DateTime::QueryPatch): core's date operators on a custom
  #   field write the bounds of a day through quoted_time; for the format Date and time they are written in UTC.
  # * IssuesHelper#issue_fields_rows, #render_half_width_custom_fields_rows and #render_full_width_custom_fields_rows
  #   (Layouts::ShowPatch): issues/show calls them, in that order, to draw the issue's attributes; with a layout the
  #   rows are kept and drawn in the layout's sections.
  # The view app/views/issues/_form_custom_fields.html.erb replaces core's partial of the same name (the custom fields
  # of the issue form); without a layout it is core's partial as it is in every supported series.
  module Patches
    module_function

    def apply!
      readers!
      prepend!(::Redmine::FieldFormat::ListFormat, Translations::ListFormatPatch)
      prepend!(::CustomFieldsHelper, Translations::ApiValuesPatch)
      prepend!(::ApplicationController, Translations::ControllerPatch)
      prepend!(::Mailer, Translations::MailerPatch)
      CoreTexts.install!
      prepend!(::Query, DateTime::QueryPatch)
      prepend!(::IssuesHelper, Layouts::ShowPatch)
    end

    def readers!
      Translations::TYPES.each { |type, attrs| Translations.install_reader(type, attrs) }
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] translated readers not installed: #{e.class} #{e.message}")
    end

    def prepend!(klass, mod)
      klass.prepend(mod) unless klass < mod
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] #{mod} not installed: #{e.class} #{e.message}")
    end
  end
end
