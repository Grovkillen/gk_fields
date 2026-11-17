# frozen_string_literal: true
# Depends on: gk_gui_stuff required, and gk_access required for the layouts. Without gk_gui_stuff
# the pages, the menus, what fields draws on other pages and the API are closed (GkFields.gui?, gate.rb): the settings
# page says so, and the migrations run all the same. What a layout's level hides, the levels a layout names in
# gk_access, the functions declared in gk_records and the permissions hold whatever the gate says. Without gk_access the plugin starts, only the layouts are
# off, and the configure page says what is missing and what works. Optional gk_records, gk_icons, gk_workflow_rules, gk_compat, gk_core_stuff, gk_scenarios.
# GK Fields: the custom field format Date and time; names per language for what core keeps as one string (trackers,
# statuses, enumerations, roles, issue categories, custom fields and the values of list fields), with copy and paste,
# the changes for everyone to read and proposals that a reviewer approves; Redmine's own texts corrected per language;
# and the layouts of an issue's head in sections; all of it also over REST. The core string is never touched: it is
# the key, and what is shown when no translation is there. Translation is reading only: forms, validation,
# uniqueness, API and import go on the core string.

# The gate to GK GUI Stuff, first, so that every file below may ask it
require_relative 'extensions/gk_fields/gate'
require_relative 'extensions/gk_fields/translations'
# The picker's anchors: the readers mark each name with its entry on a page that asks for it
require_relative 'extensions/gk_fields/picker'
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
# Every core patch: the protection set below whatever the gate says (Patches.protect!), the rest when the gate opens
# (Gate.start!, Patches.apply!)
require_relative 'extensions/gk_fields/patches'
# The REST API's scopes and what it answers
require_relative 'extensions/gk_fields/api'

Redmine::Plugin.register :gk_fields do
  name        'GK Fields'
  author      'Jimmy Westberg'
  description 'The custom field format Date and time, names per language for what Redmine keeps as one text, ' \
              "Redmine's own texts corrected per language, and the layouts of an issue's head"
  version     '1.02.000'
  requires_redmine version_or_higher: '6.0.0'

  settings default: { 'content_languages' => '', 'core_language' => '' }, partial: 'settings/gk_fields_settings'

  # The permissions, registered whatever the gate says, so that no role loses one while the gate is closed (core's
  # role form lists only the permissions that are registered and writes the whole list). Closed, they open nothing:
  # the controllers answer 404. Who may do what with the texts (Review): a translation is saved at once, a text as it
  # is written and a list value are proposals that a reviewer approves, and Redmine's own texts are overridden with a
  # permission of their own (an override changes Redmine's words for everyone). An administrator has them all. They
  # count in the whole instance for whoever has them through a role in any project, like core's add_project:
  # Review.may? asks allowed_to_globally?. Core's Permission has no global: option, and none is in a project module.
  # The last two are OAuth scopes only (a role grants nothing with them): reading and changing over REST (who may is
  # still the permission above, or the admin flag).
  permission :gk_fields_translate, { gk_fields_translations: %i[index update exchange review import] }, require: :loggedin
  permission :gk_fields_propose_originals, { gk_fields_translations: %i[propose] }, require: :loggedin
  permission :gk_fields_propose_list_values, { gk_fields_translations: %i[propose] }, require: :loggedin
  permission :gk_fields_review, { gk_fields_translations: %i[proposals decide] }, require: :loggedin
  permission :gk_fields_core_texts, { gk_fields_translations: %i[core core_update core_yaml] }, require: :loggedin
  permission :gk_fields_api_read, {}, require: :loggedin
  permission :gk_fields_api_manage, {}, require: :loggedin

  menu :admin_menu, :gk_fields_translations, { controller: 'gk_fields_translations', action: 'index' },
       caption: :label_gk_fields_translations, after: :custom_fields, html: { class: 'icon' },
       # a declared function, off by default; the gate is asked here, since the function answers whatever the gate says
       if: proc { GkFields.gui? && GkFields.feature?('fields.translations') },
       # the icon from gk_icons when it is in Redmine's plugin directory (it loads after fields), else core's own;
       # 'globe' was never in core's sprite
       **(File.directory?(File.join(::Redmine::Plugin.directory, 'gk_icons')) ? { icon: 'language', plugin: :gk_icons } : { icon: 'text-plain' })
  # for whoever is not an administrator but may translate, override Redmine's texts or review
  menu :top_menu, :gk_fields_translations, { controller: 'gk_fields_translations', action: 'index' }, caption: :label_gk_fields_translations,
       if: proc {
         GkFields.gui? && GkFields.feature?('fields.translations') && !User.current.admin? &&
           %i[gk_fields_translate gk_fields_core_texts].any? { |p| GkFields::Review.may?(User.current, p) }
       }
  # the layouts are a declared function, off by default, and need gk_access's levels: off, without it or with a closed
  # gate (GkFields.layouts?) the item is not there
  menu :admin_menu, :gk_fields_layouts, { controller: 'gk_fields_layouts', action: 'index' },
       caption: :label_gk_fields_layouts, after: :custom_fields, html: { class: 'icon' }, icon: 'list',
       if: proc { GkFields.layouts? }
end

# The protection, whatever the gate says (a gate never closes a protection): the core patch that leaves out what a
# layout's level hides on the issue page (patches.rb, Patches.protect!), set here and again on every reload; the
# listener at the end of each preparation sets it once more, in case it failed here (Gate::Boot)
GkFields::Patches.protect!

# The rest of fields at work starts at the end of each preparation, once every plugin's init.rb has run
# (GkFields::Gate::Boot, core's hook after_plugins_loaded): with GK GUI Stuff the core patches that draw and translate
# (extensions/gk_fields/patches.rb, Patches.apply!, each guarded against a second prepend), the readers of the plugins'
# registered models and the field format Date and time. Redmine runs this file on every preparation, a reload in
# development included, and the hook follows each time. Redmine's texts are put in front of I18n again at each request
# and mail as well (CoreTexts.refresh!), so no to_prepare block is needed. Without GK GUI Stuff none of that.
# The view listeners: registered when their classes are defined, again after a reload (Redmine::Hook lives in core's
# lib/); each answers no hook without GK GUI Stuff (Gate::Listener)
Redmine::Hook.add_listener(GkFields::Gate::Boot) unless Redmine::Hook.listeners.any?(GkFields::Gate::Boot)
Redmine::Hook.add_listener(GkFields::PickerHooks) unless Redmine::Hook.listeners.any?(GkFields::PickerHooks)
Redmine::Hook.add_listener(GkFields::LayoutHooks) unless Redmine::Hook.listeners.any?(GkFields::LayoutHooks)
Redmine::Hook.add_listener(GkFields::AdminLinkHooks) unless Redmine::Hook.listeners.any?(GkFields::AdminLinkHooks)
# Everything below runs once every plugin is in
# The levels a layout names are in use in gk_access (access loads before fields, but is tested once every plugin is
# in), whatever the gate says: gk_access answers with a closed gate too, and a level a stored layout needs must not be
# removed meanwhile. Then, only with GK GUI Stuff (GkFields.gui?, gate.rb), the appearances other plugins declare in
# their config/registrations.yml (they may load after this plugin)
Rails.configuration.after_initialize do
  GkFields::Layouts.register_levels! if GkFields.access?
  next unless GkFields.gui?

  GkFields::Layouts.load_registrations!
end
# Declared functions in records' register, off for a new installation; records loads after fields. Whatever the gate
# says: records answers off for a function that is not declared, and what a layout's level hides hangs on the function
# Layouts (Layouts.hiding?), so a function declared only behind the gate would let the protection fall with it. The
# page that switches the functions is closed with the gate, and what draws for one asks the gate itself.
Rails.configuration.after_initialize do
  if defined?(::GkRecords::Features) && ::GkRecords::Features.respond_to?(:register)
    ::GkRecords::Features.register('fields.translations', plugin: :gk_fields,
                                                           label: :label_gk_feature_fields_translations, help: :text_gk_feature_fields_translations)
    ::GkRecords::Features.register('fields.picker', plugin: :gk_fields,
                                                     label: :label_gk_feature_fields_picker, help: :text_gk_feature_fields_picker)
    ::GkRecords::Features.register('fields.layouts', plugin: :gk_fields,
                                                      label: :label_gk_feature_fields_layouts, help: :text_gk_feature_fields_layouts)
  end
end
# Everything below only with GK GUI Stuff
# The Texts button as a row in the three-dot menu, on every page that has the menu; the picker draws its own button
# only for whoever does not get the menu's rows (GkGuiStuff::Menu.on_for?, hooks.rb)
Rails.configuration.after_initialize do
  next unless GkFields.gui?

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
  next unless GkFields.gui?

  if defined?(::GkRecords::Reasons)
    ::GkRecords::Reasons.register('fields.proposal', plugin: :gk_fields, label: :label_gk_reason_fields_proposal, default: :required)
    ::GkRecords::Reasons.register('fields.layout', plugin: :gk_fields, label: :label_gk_reason_fields_layout, default: :optional, admin: true)
  end
end
# What waits for the person (proposals to review, her own decided ones) under Mitt, with its count
Rails.configuration.after_initialize do
  next unless GkFields.gui? && defined?(::GkGuiStuff::Personal)

  ::GkGuiStuff::Personal.register('fields.proposals', plugin: :gk_fields, label: :label_gk_fields_proposals, order: 40,
                                    url: { controller: 'gk_fields_translations', action: 'proposals' },
                                    if: ->(u) { GkFields.feature?('fields.translations') && GkFields::Review.menu?(u) },
                                    count: ->(u) { GkFields::Review.waiting_for(u) }, waits: true)
end
# registrations.yml read through records' one reader: a label the file names that no locale has is written to the
# log at start
Rails.configuration.after_initialize { ::GkRecords::Registrations.check!(:gk_fields) if GkFields.gui? && defined?(::GkRecords::Registrations) }
