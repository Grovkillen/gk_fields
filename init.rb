# frozen_string_literal: true
# Depends on: gk_access required (the layouts); without it the plugin starts, only the layouts are off, and the
# configure page says what is missing and what works. Optional gk_records, gk_gui_stuff, gk_icons, gk_workflow_rules,
# gk_compat, gk_scenarios.
# GK Fields: the custom field format Date and time; names per language for what core keeps as one string (trackers,
# statuses, enumerations, roles, issue categories, custom fields and the values of list fields), with copy and paste,
# the changes for everyone to read and proposals that a reviewer approves; Redmine's own texts corrected per language;
# and the layouts of an issue's head in sections; all of it also over REST. The core string is never touched: it is
# the key, and what is shown when no translation is there. Translation is reading only: forms, validation,
# uniqueness, API and import go on the core string. Without gk_access the plugin starts and does everything but the
# layouts.

require_relative 'extensions/gk_fields/translations'
# Redmine's own texts corrected in this instance, shown through an I18n backend in front of core's
require_relative 'extensions/gk_fields/core_texts'
require_relative 'extensions/gk_fields/exchange'
require_relative 'extensions/gk_fields/review'
# The custom field format Date and time (gk_fields_datetime), stored in UTC, shown in the viewer's time zone
require_relative 'extensions/gk_fields/datetime'
# The layouts of an issue's head: sections, levels and appearances per tracker, status and project
require_relative 'extensions/gk_fields/layouts'
# The view listeners: the picker, and the layouts' stylesheet
require_relative 'extensions/gk_fields/hooks'
# Every core patch, applied below
require_relative 'extensions/gk_fields/patches'
# The REST API's scopes and what it answers
require_relative 'extensions/gk_fields/api'

Redmine::Plugin.register :gk_fields do
  name        'GK Fields'
  author      'Jimmy Westberg'
  description 'The custom field format Date and time, names per language for what Redmine keeps as one text, ' \
              "Redmine's own texts corrected per language, and the layouts of an issue's head"
  version     '1.00.000'
  requires_redmine version_or_higher: '6.0.0'

  settings default: { 'content_languages' => '', 'core_language' => '' }, partial: 'settings/gk_fields_settings'

  # Who may do what with the texts: a translation is saved at once, a text as it is written and a list value are
  # proposals that a reviewer approves, and Redmine's own texts are overridden with a permission of their own (an
  # override changes Redmine's words for everyone). An administrator has them all. They count in the whole instance
  # for whoever has them through a role in any project, like core's add_project: Review.may? asks
  # allowed_to_globally?. Core's Permission has no global: option, and none is in a project module.
  permission :gk_fields_translate, { gk_fields_translations: %i[index update exchange review import] }, require: :loggedin
  permission :gk_fields_propose_originals, { gk_fields_translations: %i[propose] }, require: :loggedin
  permission :gk_fields_propose_list_values, { gk_fields_translations: %i[propose] }, require: :loggedin
  permission :gk_fields_review, { gk_fields_translations: %i[proposals decide] }, require: :loggedin
  permission :gk_fields_core_texts, { gk_fields_translations: %i[core core_update core_yaml] }, require: :loggedin
  # OAuth scopes only (a role grants nothing with them): reading and changing over REST (who may is still the
  # permission above, or the admin flag)
  permission :gk_fields_api_read, {}, require: :loggedin
  permission :gk_fields_api_manage, {}, require: :loggedin

  menu :admin_menu, :gk_fields_translations, { controller: 'gk_fields_translations', action: 'index' },
       caption: :label_gk_fields_translations, after: :custom_fields, html: { class: 'icon' },
       if: proc { GkFields.feature?('fields.translations') }, # A declared function, off by default
       # the icon from gk_icons when it is in Redmine's plugin directory (it loads after fields), else core's own;
       # 'globe' was never in core's sprite
       **(File.directory?(File.join(::Redmine::Plugin.directory, 'gk_icons')) ? { icon: 'language', plugin: :gk_icons } : { icon: 'text-plain' })
  # for whoever is not an administrator but may translate, override Redmine's texts or review
  menu :top_menu, :gk_fields_translations, { controller: 'gk_fields_translations', action: 'index' }, caption: :label_gk_fields_translations,
       if: proc {
         GkFields.feature?('fields.translations') && !User.current.admin? &&
           %i[gk_fields_translate gk_fields_core_texts].any? { |p| GkFields::Review.may?(User.current, p) }
       }
  # The notice to the reviewer: the number of proposals that wait for her stands in the menu on every page, and
  # the item is there for an administrator too as long as something waits
  menu :top_menu, :gk_fields_proposals, { controller: 'gk_fields_translations', action: 'proposals' },
       caption: proc { GkFields::Review.menu_caption(User.current) },
       if: proc { !defined?(::GkGuiStuff::Personal) && GkFields.feature?('fields.translations') && GkFields::Review.menu?(User.current) }
  # the layouts are a declared function, off by default, and need gk_access's levels: off or without it the item is
  # not there
  menu :admin_menu, :gk_fields_layouts, { controller: 'gk_fields_layouts', action: 'index' },
       caption: :label_gk_fields_layouts, after: :custom_fields, html: { class: 'icon' }, icon: 'list',
       if: proc { GkFields.layouts? }
end

# Core patches (extensions/gk_fields/patches.rb): applied here, while Redmine prepares the application, and again
# each time this file runs (Redmine runs it on every preparation, a reload in development included); each is guarded
# against a second prepend. Redmine's texts are put in front of I18n again at each request and mail as well
# (CoreTexts.refresh!), so no to_prepare block is needed.
GkFields::Patches.apply!
# The picker: a view listener, registered again after a reload (Redmine::Hook lives in core's lib/)
Redmine::Hook.add_listener(GkFields::PickerHooks) unless Redmine::Hook.listeners.any?(GkFields::PickerHooks)
Redmine::Hook.add_listener(GkFields::LayoutHooks) unless Redmine::Hook.listeners.any?(GkFields::LayoutHooks)
Redmine::Hook.add_listener(GkFields::AdminLinkHooks) unless Redmine::Hook.listeners.any?(GkFields::AdminLinkHooks)
# The appearances other plugins declare in their config/registrations.yml (they may load after this plugin), and the
# levels a layout names are in use in gk_access (access loads before fields, but is tested once every plugin is in)
Rails.configuration.after_initialize do
  GkFields::Layouts.load_registrations!
  GkFields::Layouts.register_levels! if GkFields.access?
end
# Declared functions in records' register, off for a new installation; records loads after fields
Rails.configuration.after_initialize do
  if defined?(::GkRecords::Features) && ::GkRecords::Features.respond_to?(:register)
    ::GkRecords::Features.register('fields.translations', plugin: :gk_fields,
                                                           label: :label_gk_feature_fields_translations, help: :text_gk_feature_fields_translations)
    ::GkRecords::Features.register('fields.picker', plugin: :gk_fields,
                                                     label: :label_gk_feature_fields_picker, help: :text_gk_feature_fields_picker)
    ::GkRecords::Features.register('fields.layouts', plugin: :gk_fields,
                                                      label: :label_gk_feature_fields_layouts, help: :text_gk_feature_fields_layouts)
  end
  # The Texts button as a row in the three-dot menu, on every page that has the menu; the picker draws its own button
  # only for whoever does not get the menu's rows (GkGuiStuff::Menu.on_for?, hooks.rb)
  if defined?(::GkGuiStuff::Menu)
    ::GkGuiStuff::Menu.register('fields_picker', section: :show, context: %i[issue issue_list project wiki_page version other],
                                                 label: :label_gk_fields_picker_menu, title: :text_gk_fields_picker, plugin: :gk_fields,
                                                 kind: :action, action: :fields_picker, order: 90, icon: 'edit',
                                                 condition: ->(_page) { GkFields.feature?('fields.picker') && GkFields::Review.any?(::User.current) })
  end
end
# The reason places in gk_records (records may load after this plugin): a proposed text, and a layout saved by an
# administrator (removing one asks for no reason)
Rails.configuration.after_initialize do
  if defined?(::GkRecords::Reasons)
    ::GkRecords::Reasons.register('fields.proposal', plugin: :gk_fields, label: :label_gk_reason_fields_proposal, default: :required)
    ::GkRecords::Reasons.register('fields.layout', plugin: :gk_fields, label: :label_gk_reason_fields_layout, default: :optional, admin: true)
  end
end
Rails.configuration.after_initialize do
  next unless defined?(::GkGuiStuff::Personal)

  ::GkGuiStuff::Personal.register('fields.proposals', plugin: :gk_fields, label: :label_gk_fields_proposals, order: 40,
                                    url: { controller: 'gk_fields_translations', action: 'proposals' },
                                    if: ->(u) { GkFields.feature?('fields.translations') && GkFields::Review.menu?(u) },
                                    count: ->(u) { GkFields::Review.waiting_for(u) }, waits: true)
end
# registrations.yml read through records' one reader: a label the file names that no locale has is written to the
# log at start
Rails.configuration.after_initialize { ::GkRecords::Registrations.check!(:gk_fields) if defined?(::GkRecords::Registrations) }
