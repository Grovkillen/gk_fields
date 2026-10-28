# frozen_string_literal: true

module GkFields
  # The view listeners (Redmine::Hook), registered in init.rb

  # The picker: for whoever may administer texts, Alt+Shift+T and the row Show the texts that can be changed in
  # gk_gui_stuff's three-dot menu (registered in init.rb) show an icon at every text on the page that can be
  # administered; the icon leads to that text. Whoever does not get the menu's rows (no gui_stuff, or its menu off
  # for her), and a page without a three-dot menu, get a small button at the bottom right instead. The texts are
  # matched in the browser against the list of what can be administered, so no page of core's is rewritten.
  class PickerHooks < Redmine::Hook::ViewListener
    def view_layouts_base_body_bottom(_context = {})
      return '' unless GkFields.feature?('fields.picker') && Review.any?(User.current) # A declared function

      label = ::I18n.t(:label_gk_fields_picker)
      title = ::I18n.t(:text_gk_fields_picker)
      # the row in the menu stands in for the button
      menu = defined?(::GkGuiStuff::Menu) && ::GkGuiStuff::Menu.on_for?(User.current) ? true : false
      javascript_tag(<<~JS)
        (function () {
          var gk = window.gkFields = window.gkFields || {};
          if (gk.picker) return;
          var on = false, texts = null, menu = #{menu}, btn = null;
          // the button at the bottom right, for whoever has no row in a three-dot menu on this page
          function button() {
            btn = document.createElement('a');
            btn.href = '#'; btn.id = 'gk-fields-picker'; btn.textContent = #{label.to_json}; btn.title = #{title.to_json};
            btn.setAttribute('role', 'button'); btn.setAttribute('aria-pressed', on ? 'true' : 'false'); btn.setAttribute('aria-label', #{title.to_json});
            btn.style.cssText = 'position:fixed;inset-block-end:8px;inset-inline-end:8px;z-index:50;padding:3px 8px;font-size:0.85em;border:1px solid var(--oc-gray-5,#adb5bd);border-radius:3px;background:var(--oc-gray-0,#f8f9fa);';
            btn.addEventListener('click', function (e) { e.preventDefault(); toggle(); });
            document.body.appendChild(btn);
          }
          function clear() { document.querySelectorAll('a.gk-fields-pick').forEach(function (a) { a.remove(); }); }
          function mark() {
            var root = document.getElementById('main') || document.body;
            var w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT), nodes = [], n;
            while ((n = w.nextNode())) {
              var p = n.parentElement; if (!p) continue;
              if (/^(SCRIPT|STYLE|OPTION|TEXTAREA|TITLE)$/.test(p.tagName) || p.closest('#gk-fields-picker, a.gk-fields-pick')) continue;
              var t = n.nodeValue.trim(); if (!t) continue;
              // a text alone, or a tracker before an issue's number as in the issue page's heading ("Möte #20")
              var m = texts[t] ? null : t.match(/^(.+?) #\\d+:?$/);
              if (texts[t]) nodes.push([n, t]); else if (m && texts[m[1]]) nodes.push([n, m[1]]);
            }
            nodes.forEach(function (x) {
              var a = document.createElement('a'); a.className = 'gk-fields-pick';
              if (window.GkGui && GkGui.icon) a.appendChild(GkGui.icon('edit', '\\u270E', 12)); else a.textContent = '\\u270E';
              a.href = #{gk_fields_find_path.to_json} + '?text=' + encodeURIComponent(x[1]); a.title = #{title.to_json};
              // in the middle of the text's line wherever the text is (a value, a cell, a title), and as big as the text
              a.style.cssText = 'margin-inline-start:3px;font-size:0.8em;text-decoration:none;display:inline-flex;align-items:center;vertical-align:middle;line-height:1;';
              var svg = a.querySelector('svg'); if (svg) { svg.style.inlineSize = '1em'; svg.style.blockSize = '1em'; }
              x[0].parentNode.insertBefore(a, x[0].nextSibling);
            });
          }
          function toggle() {
            on = !on;
            if (btn) { btn.style.fontWeight = on ? 'bold' : ''; btn.setAttribute('aria-pressed', on ? 'true' : 'false'); }
            if (!on) { clear(); return; }
            if (texts) { mark(); return; }
            fetch(#{gk_fields_texts_path.to_json}, { headers: { 'Accept': 'application/json' }, credentials: 'same-origin' })
              .then(function (r) { return r.json(); })
              .then(function (d) { texts = {}; (d.texts || []).forEach(function (t) { texts[t] = true; }); if (on) mark(); });
          }
          document.addEventListener('keydown', function (e) { if (e.altKey && e.shiftKey && (e.key === 'T' || e.key === 't')) { e.preventDefault(); toggle(); } });
          // the menu's row (gk_gui_stuff runs it as an action; its script is in the page's head). A page without a
          // three-dot menu has no row once the page is in, and gets the button.
          if (window.GkGui && window.GkGui.actions) window.GkGui.actions.fields_picker = function () { toggle(); };
          if (!menu) button();
          else window.addEventListener('load', function () { if (!document.querySelector('[data-gk-gui-stuff-menu-key="fields_picker"]')) button(); });
          gk.picker = { toggle: toggle };
        })();
      JS
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
  # and custom fields (the list and the edit page) a link Translations in the page's button row opens the tab of that
  # sort of thing. Core's pages have no hook in their button row, so the link is put in when the page is drawn; only
  # for whoever may translate, and only while the function Translations is on.
  class AdminLinkHooks < Redmine::Hook::ViewListener
    TABS = { 'trackers' => 'Tracker', 'issue_statuses' => 'IssueStatus', 'roles' => 'Role', 'enumerations' => 'Enumeration',
             'custom_fields' => 'CustomField' }.freeze

    def view_layouts_base_body_bottom(context = {})
      c = context[:controller]
      type = c && TABS[c.controller_name]
      return '' unless type && %w[index edit].include?(c.action_name)
      return '' unless GkFields.feature?('fields.translations') && Review.may?(User.current, :gk_fields_translate)

      link = link_to(sprite_icon('edit', ::I18n.t(:label_gk_fields_translations)), gk_fields_translations_path(type: type), class: 'icon gk-fields-translations-link')
      javascript_tag(<<~JS)
        (function () {
          var content = document.getElementById('content');
          if (!content || content.querySelector('a.gk-fields-translations-link')) return;
          var row = content.querySelector(':scope > div.contextual');
          if (!row) { row = document.createElement('div'); row.className = 'contextual'; content.insertBefore(row, content.firstChild); }
          row.insertAdjacentHTML('beforeend', #{link.to_str.to_json});
        })();
      JS
    end
  end
end
