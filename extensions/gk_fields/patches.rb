# frozen_string_literal: true

module GkFields
  # Core patches, all in one place, in two layers. Each says what it assumes of core; the modules themselves stay
  # beside the code they belong to. Redmine runs init.rb again on every preparation (a reload in development), when
  # the reloaded core classes need the patches again; each prepend is guarded against a second one, so a class already
  # patched is left as it is. A part that fails is written to the log and the others are still applied.
  #
  # The protection (protect!), set by init.rb whatever the gate says, and once more at the end of each preparation
  # (Gate::Boot) in case it failed there. Set in init.rb it lies inside a patch that a plugin loaded later puts on the
  # same three methods; assumed: no other plugin patches them (none of the GK plugins does), so the order has no
  # effect. The patch:
  # * IssuesHelper#issue_fields_rows, #render_half_width_custom_fields_rows and #render_full_width_custom_fields_rows
  #   (Layouts::ShowPatch): issues/show calls them, in that order, to draw the issue's attributes. With an open gate
  #   and a layout the rows are kept and drawn in the layout's sections. With a closed gate core draws them, without
  #   what the layout's level hides from the person. Assumes, the same in every supported series: issue_fields_rows
  #   yields a collector whose left and right take (label, text, class: ...), with the class of core's field first;
  #   the two helpers for the custom fields take the issue and ask it visible_custom_field_values and nothing else.
  #
  # The interface (apply!), set when the gate opens (Gate.start!):
  # * Tracker, IssueStatus, Enumeration, Role, IssueCategory, CustomField (Translations.install_reader): the readers
  #   of name and description, which core's views call to show the thing; a reader gives the translation when
  #   translation is on for the request and the record is saved, else core's value. A plugin's model registered with
  #   Translations.register_type gets the same reader.
  # * Redmine::FieldFormat::ListFormat (Translations::ListFormatPatch): possible_values_options,
  #   possible_custom_value_options and formatted_value give a list field's choices and values; only the label
  #   changes, the stored value stays the core string.
  # * ApplicationController#process_action (Translations::ControllerPatch): every action of every controller runs
  #   through it, also of controllers loaded before this plugin; translation is switched on for the request there,
  #   and the picker's marks (Picker) when the page asks for them.
  # * Redmine::Views::Builders::Json#output (Translations::ApiBuilderPatch): core's API views write a structure into
  #   the builder, which output turns into JSON; with lang= each name a reader gave as an ApiName is written as name
  #   (the core string) and name_lang (the translation) first.
  # * Mailer#process (Translations::MailerPatch): a mail is written inside it in the recipient's language.
  # * I18n.backend (CoreTexts.install!): the chain with the corrections in front of whatever backend Redmine has set
  #   up; put in again at each request and mail (CoreTexts.refresh!) if anything replaced it.
  # * Query#sql_for_custom_field and Query#quoted_time (DateTime::QueryPatch): core's date operators on a custom
  #   field write the bounds of a day through quoted_time; for the format Date and time they are written in UTC.
  # The view app/views/issues/_form_custom_fields.html.erb replaces core's partial of the same name (the custom fields
  # of the issue form); without a layout it is core's partial as it is in every supported series, and with a closed
  # gate without the fields the layout's level hides from the person.
  module Patches
    module_function

    def protect!
      prepend!(::IssuesHelper, Layouts::ShowPatch)
    end

    def apply!
      readers!
      prepend!(::Redmine::FieldFormat::ListFormat, Translations::ListFormatPatch)
      prepend!(::CustomFieldsHelper, Translations::ApiValuesPatch)
      prepend!(::ApplicationController, Translations::ControllerPatch)
      prepend!(::Redmine::Views::Builders::Json, Translations::ApiBuilderPatch)
      prepend!(::Mailer, Translations::MailerPatch)
      CoreTexts.install!
      prepend!(::Query, DateTime::QueryPatch)
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
