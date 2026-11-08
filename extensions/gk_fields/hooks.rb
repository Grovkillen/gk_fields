# frozen_string_literal: true

module GkFields
  # The view listeners (Redmine::Hook), registered in init.rb

  # The picker: for whoever may administer texts, Alt+Shift+T and the row Show the texts that can be changed in
  # gk_gui_stuff's three-dot menu (registered in init.rb) show an icon at every text on the page that can be
  # administered; the icon leads to that text. Whoever does not get the menu's rows (no gui_stuff, or its menu off
  # for her), and a page without a three-dot menu, get a small button at the bottom right instead.
  # A text is found by its entry, never by its words: turning the picker on asks for the page again with
  # gk_fields_pick=1, and on that page each name a translated reader or a list field's label gave ends with an
  # invisible mark carrying its entry's number (Picker). This hook writes the entries' keys in the numbers' order;
  # the script takes every mark out of the page and puts the icon where a mark stood inside #main. A mark in an
  # attribute, a field's value, an option or the window's title is only taken out. Turning the picker off hides the
  # icons and takes the parameter out of the address; on again shows them.
  class PickerHooks < Redmine::Hook::ViewListener
    def view_layouts_base_body_bottom(context = {})
      return '' unless GkFields.feature?('fields.picker') && Review.any?(User.current) # A declared function

      label = ::I18n.t(:label_gk_fields_picker)
      title = ::I18n.t(:text_gk_fields_picker)
      # the row in the menu stands in for the button
      menu = defined?(::GkGuiStuff::Menu) && ::GkGuiStuff::Menu.on_for?(User.current) ? true : false
      c = context[:controller]
      asked = c && c.params[Picker::PARAM].to_s == '1' ? true : false
      # the script (assets/javascripts/gk_fields_picker.js) reads what it needs from the page; drawn at the bottom of the
      # body, it runs once the page above it is in
      config = { param: Picker::PARAM, keys: Picker.keys, taken: asked, menu: menu, label: label, title: title, find: gk_fields_find_path }
      javascript_tag("window.gkFieldsPickerConfig = #{config.to_json};") + javascript_include_tag('gk_fields_picker', plugin: :gk_fields)
    end
  end

  # The sections' small stylesheet, on the pages that may draw them (an issue, its form, the administration page)
  class LayoutHooks < Redmine::Hook::ViewListener
    def view_layouts_base_html_head(context = {})
      c = context[:controller]
      return '' unless c.is_a?(::IssuesController) || c.is_a?(::GkFieldsLayoutsController)

      stylesheet_link_tag('gk_fields_layouts', plugin: :gk_fields)
    end
  end

  # Translations reached from where the things are kept: on core's pages of trackers, statuses, roles, enumerations
  # and custom fields (the list and the edit page) a link Translations opens the tab of that sort of thing; only for
  # whoever may translate, and only while the function Translations is on. Core's pages have no hook in their button
  # row; the link stands in a button row of its own (core's class contextual, floated as core's) drawn through the hook
  # at the top of the content (view_layouts_base_content_top, gk_core_stuff's layout_hooks, step 01 of #44660), so it
  # lines up with core's buttons where the page has them. Nothing on core's page is looked for. Without the hook (no
  # gk_core_stuff, or another plugin's copy of the layout) the link is not drawn.
  class AdminLinkHooks < Redmine::Hook::ViewListener
    TABS = { 'trackers' => 'Tracker', 'issue_statuses' => 'IssueStatus', 'roles' => 'Role', 'enumerations' => 'Enumeration',
             'custom_fields' => 'CustomField' }.freeze

    def view_layouts_base_content_top(context = {})
      c = context[:controller]
      type = c && TABS[c.controller_name]
      return '' unless type && %w[index edit].include?(c.action_name)
      return '' unless GkFields.feature?('fields.translations') && Review.may?(User.current, :gk_fields_translate)

      link = link_to(sprite_icon('edit', ::I18n.t(:label_gk_fields_translations)), gk_fields_translations_path(type: type), class: 'icon gk-fields-translations-link')
      content_tag(:div, link, class: 'contextual gk-fields-translations-row')
    end
  end
end
