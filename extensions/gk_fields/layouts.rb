# frozen_string_literal: true

require 'json'
require 'yaml'

module GkFields
  # The layouts of an issue's head (gk_fields_layouts): which layout applies to an issue, whether one holds, and what
  # it shows a person. The view and the scenarios read the same sections (sections_for), so they never differ.
  #
  # A layout is JSON: { "sections": [ { "key", "title": { lang: text }, "columns": 1 | 2, "collapsed": true | false,
  # "level": "<a level's key in gk_access>", "fields": [ { "field": "<core key>" | "cf:<id>", "width": "half" |
  # "full", "appearance": { "show" | "edit" | "small": "<key>" } } ] } ] }. A field the layout does not name, and that
  # the person sees, is drawn in a folded section Other at the end, so that nothing goes missing.
  #
  # Permissions stay core's: a field the person may not see is never drawn, in any layout or appearance. The levels
  # are gk_access's, data with a rank; fields keeps none of its own. A section's level is the strictest of its
  # fields' (a custom field visible only to some roles has the first level above the lowest), and the layout may only
  # make it stricter; a section is drawn only for a person whose ceiling reaches its level (GkAccess.sees?), and one
  # above the lowest has the lock in its title. "You see" names the levels the person sees a field in on the issue.
  module Layouts
    # core's fields by key, with the class core gives each row on the issue page (issue_fields_rows)
    CORE = { 'status' => 'status', 'priority' => 'priority', 'assigned_to' => 'assigned-to', 'category' => 'category',
             'fixed_version' => 'fixed-version', 'start_date' => 'start-date', 'due_date' => 'due-date', 'done_ratio' => 'progress',
             'estimated_hours' => 'estimated-hours', 'spent_time' => 'spent-time' }.freeze
    WIDTHS = %w[half full].freeze
    CONTEXTS = %w[show edit small].freeze
    KEY = /\A[a-z0-9_]{1,40}\z/
    CF = /\Acf:(\d{1,10})\z/
    STANDARD = { 'key' => 'standard', 'name' => 'label_gk_fields_appearance_standard', 'defaults' => CONTEXTS, 'text' => false }.freeze
    OTHER = 'other'

    module_function

    # A REST body that is not { layout: { ... } } (the controller answers with core's 422)
    class BodyError < StandardError; end

    # The function is on, gk_access is there (GkFields.layouts?) and the table is made
    def ready? = GkFields.layouts? && ::GkFieldsLayout.table_exists?

    # ------------------------------------------------------------------ which layout

    # The layout that applies to an issue in a scope (show, or edit, which falls back on show), read, or nil: the
    # project's before the instance's, one for the issue's status before one for all statuses, the scope's own before
    # show's
    def for_issue(issue, scope = 'show')
      return nil unless issue&.tracker_id && ready?

      scopes = scope.to_s == 'edit' ? %w[edit show] : %w[show]
      list = ::GkFieldsLayout.where(tracker_id: issue.tracker_id, project_id: [issue.project_id, nil].uniq,
                                    status_id: [issue.status_id, nil].uniq, scope: scopes).to_a
      best = list.min_by { |l| [l.project_id ? 0 : 1, l.status_id ? 0 : 1, scopes.index(l.scope)] }
      best&.data
    end

    # ------------------------------------------------------------------ appearances

    # A field type's appearances, as the plugins register them (config/registrations.yml, appearances: { <format> =>
    # [ { key, name, defaults: [contexts], text } ] }): core's own formats have only Standard
    def registry = (@registry ||= {})

    def register_appearances(format, list)
      registry[format.to_s] = Array(list).map { |a| a.to_h.transform_keys(&:to_s) }.select { |a| a['key'].to_s.match?(KEY) }
    end

    # Every plugin's registrations.yml: its appearances, through records' one reader of the files when records is
    # there (GkRecords::Registrations.section), else read here
    def load_registrations!
      sections = if defined?(::GkRecords::Registrations)
                   ::GkRecords::Registrations.section('appearances').values
                 else
                   ::Redmine::Plugin.all.filter_map { |p| own_registrations(p)['appearances'] }
                 end
      sections.each do |appearances|
        next unless appearances.is_a?(Hash)

        appearances.each { |format, list| register_appearances(format, list) }
      end
    end

    def own_registrations(plugin)
      file = File.join(plugin.directory.to_s, 'config', 'registrations.yml')
      y = File.file?(file) ? YAML.safe_load(File.read(file, encoding: 'UTF-8')) : nil
      y.is_a?(Hash) ? y : {}
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] #{file} not read: #{e.class} #{e.message}")
      {}
    end

    def appearances_for(cf) = [STANDARD] + Array(registry[cf.field_format.to_s])

    # The appearance a field has in a context: the layout's choice, else the field type's default for the context,
    # else Standard
    def appearance(spec, cf, context)
      return 'standard' unless cf

      list = appearances_for(cf)
      # a choice that is not an object of context and appearance (a layout saved before errors refused it) is no choice
      looks = spec.is_a?(Hash) ? spec['appearance'] : nil
      chosen = looks.is_a?(Hash) ? looks[context.to_s].to_s : ''
      return chosen if list.any? { |a| a['key'] == chosen }

      (list.reject { |a| a['key'] == 'standard' }.detect { |a| Array(a['defaults']).include?(context.to_s) } || STANDARD)['key']
    end

    # ------------------------------------------------------------------ levels

    # The levels, gk_access's by rank: their keys, the lowest, a level's name and its step above the lowest
    def level_keys = ::GkAccess.levels.map(&:key)
    def lowest_key = ::GkAccess.lowest&.key.to_s
    def known_level?(key) = level_keys.include?(key.to_s)
    def level_label(key) = ::GkAccess.level(key)&.label || key.to_s
    def level_step(key) = ::GkAccess.step_of(key)
    def above_lowest?(key) = level_step(key).positive?

    # The classes a section gets for its level: its step (gk-fields-level-rank-<n>), and strict from the second step
    # up, so that a level the administrator adds has a look without a stylesheet of its own
    def level_classes(key)
      step = level_step(key)
      ["gk-fields-level-rank-#{step}", ('gk-fields-level-strict' if step >= 2)].compact.join(' ')
    end

    # A field's level from core's visibility: a custom field visible only to some roles has the first level above the
    # lowest, any other the lowest
    def field_level(cf)
      return lowest_key unless cf && !cf.visible?

      (::GkAccess.levels[1] || ::GkAccess.lowest)&.key.to_s
    end

    def stricter(a, b) = ::GkAccess.stricter(a, b)&.key.to_s

    # The levels a layout names
    def levels_in(data) = Array(data.is_a?(Hash) ? data['sections'] : nil).filter_map { |s| s['level'].presence if s.is_a?(Hash) }.map(&:to_s).uniq

    # A level a layout names is in use, so gk_access never removes it (init.rb, once every plugin is in, when gk_access
    # is there). A saved layout counts also while the function is off: it stands untouched and may be used again.
    def register_levels!
      ::GkAccess.register_user('fields.layouts') do |level|
        GkFields.access? && ::GkFieldsLayout.table_exists? && ::GkFieldsLayout.find_each.any? { |l| levels_in(l.data).include?(level.key) }
      end
    end

    # ------------------------------------------------------------------ checking

    # What does not hold in a layout, as texts for a person; [] when it holds. kept: the levels the stored layout
    # already names, which may stay although they are closed for new things.
    def errors(data, tracker: nil, kept: [])
      e = []
      return [t(:error_gk_fields_layout_json)] unless data.is_a?(Hash) && data['sections'].is_a?(Array) && data['sections'].any?

      seen_keys = []
      seen_fields = []
      data['sections'].each_with_index do |s, i|
        n = i + 1
        next e << t(:error_gk_fields_layout_section, n: n) unless s.is_a?(Hash)

        e << t(:error_gk_fields_layout_key, n: n) unless s['key'].to_s.match?(KEY) && s['key'].to_s != OTHER
        e << t(:error_gk_fields_layout_key_twice, key: s['key']) if seen_keys.include?(s['key'])
        seen_keys << s['key']
        e << t(:error_gk_fields_layout_title, n: n) unless s['title'].is_a?(Hash) && s['title'].values.any? { |v| v.to_s.strip.present? }
        e << t(:error_gk_fields_layout_columns, n: n) unless [nil, 1, 2].include?(s['columns'])
        e << t(:error_gk_fields_layout_collapsed, n: n) unless [nil, true, false].include?(s['collapsed'])
        e << t(:error_gk_fields_layout_level, n: n, levels: level_keys.join(', ')) unless s['level'].nil? || known_level?(s['level'])
        if known_level?(s['level']) && ::GkAccess.level(s['level']).closed? && !Array(kept).include?(s['level'].to_s)
          e << t(:error_gk_fields_layout_level_closed, n: n, level: level_label(s['level']))
        end
        derived = lowest_key
        section_cfs = []
        open_fields = [] # fields everyone sees (core's, and custom fields without visibility per role)
        Array(s['fields']).each do |f|
          name = f.is_a?(Hash) ? f['field'].to_s : ''
          cf = (m = CF.match(name)) && ::IssueCustomField.find_by(id: m[1].to_i)
          next e << t(:error_gk_fields_layout_field, field: name, n: n) unless CORE.key?(name) || cf
          next e << t(:error_gk_fields_layout_field_twice, field: name) if seen_fields.include?(name)

          seen_fields << name
          section_cfs << cf if cf
          e << t(:error_gk_fields_layout_not_tracker, field: cf.name) if cf && tracker && !tracker.custom_field_ids.include?(cf.id)
          e << t(:error_gk_fields_layout_width, field: name) unless f['width'].nil? || WIDTHS.include?(f['width'].to_s)
          # appearance is an object of context and appearance, or not given; anything else (a text, a number, true,
          # false, a list) is refused, never read
          looks = f['appearance']
          if looks.nil? || looks.is_a?(Hash)
            (looks || {}).each do |ctx, key|
              ok = CONTEXTS.include?(ctx.to_s) && (cf ? appearances_for(cf) : [STANDARD]).any? { |a| a['key'] == key.to_s }
              e << t(:error_gk_fields_layout_appearance, field: name, context: ctx, appearance: key) unless ok
            end
          else
            e << t(:error_gk_fields_layout_appearance_object, field: name)
          end
          derived = stricter(derived, field_level(cf))
          open_fields << (cf ? cf.name : name) if cf.nil? || cf.visible?
        end
        # A section's level hides its fields on the issue page only (gk_access does not yet hide them anywhere else);
        # REST, CSV, the history, mail and search follow each field's visibility per role. So a section stricter than its fields is
        # allowed only when every field in it is already limited per role; a field everyone sees is refused, with the
        # way to protect it (the field's visibility per role).
        if s['level'] && known_level?(s['level']) && stricter(s['level'], derived) == s['level'].to_s && s['level'].to_s != derived.to_s &&
           open_fields.any?
          e << t(:error_gk_fields_layout_level_open_field, n: n, level: level_label(s['level']), fields: open_fields.join(', '))
        end
        # the layout may make a section stricter than its fields, never less strict
        if s['level'] && known_level?(s['level']) && stricter(s['level'], derived) != s['level'].to_s
          e << t(:error_gk_fields_layout_level_lower, n: n, level: level_label(derived))
        end
        # a required field in a section above the ceiling of a role that writes the issue: that role could never
        # save the issue, so the layout is refused
        level = known_level?(s['level']) ? s['level'].to_s : derived
        required_above(section_cfs, level, tracker).each do |cf, role|
          e << t(:error_gk_fields_layout_required_above, field: cf.name, section: section_name(s, n), level: level_label(level), role: role.name)
        end
      end
      e
    end

    # The section's title in the person's language, else its key
    def section_name(s, n)
      lang = (::User.current.language.presence || ::Setting.default_language).to_s
      title = s['title'].is_a?(Hash) ? s['title'] : {}
      (title[lang].presence || title.values.find(&:present?) || s['key'].presence || n).to_s
    end

    # [[custom field, role]] for each required custom field the role edits but whose section it does not see: the
    # roles that add or edit issues of the tracker, the field required for them (required for all, or by the workflow
    # for the role and tracker) and visible to them, and their ceiling (gk_access) below the section's level
    def required_above(cfs, level, tracker)
      return [] if cfs.empty? || !above_lowest?(level)

      rank = ::GkAccess.rank_of(level).to_i
      ceilings = ::GkAccess.ceilings
      low = ::GkAccess.lowest&.rank.to_i
      writers = writing_roles(tracker)
      cfs.flat_map do |cf|
        writers.filter_map do |role|
          next unless cf.visible? || cf.role_ids.include?(role.id)
          next unless required_for?(cf, role, tracker)
          next if (ceilings[role.id] || low) >= rank

          [cf, role]
        end
      end
    end

    # The roles that add or edit issues, of the tracker when there is one (core's per-tracker permissions)
    def writing_roles(tracker)
      ::Role.sorted.to_a.select do |role|
        %i[add_issues edit_issues].any? do |perm|
          next false unless role.allowed_to?(perm)
          next true unless tracker

          role.permissions_all_trackers?(perm) || role.permissions_tracker_ids(perm).include?(tracker.id)
        end
      end
    end

    # Required for the role: for everyone (is_required), or by the workflow in any status of the tracker
    def required_for?(cf, role, tracker)
      return true if cf.is_required?

      scope = ::WorkflowPermission.where(role_id: role.id, field_name: cf.id.to_s, rule: 'required')
      scope = scope.where(tracker_id: tracker.id) if tracker
      scope.exists?
    end

    # ------------------------------------------------------------------ what a person sees

    # The sections an issue's layout shows a person, in order: [{ key, title, columns, collapsed, level, fields: [{
    # key: "status" | "cf:<id>", custom_value: (for a custom field), width, appearance }] }], with the folded section
    # Other last for what the layout does not name; only sections with a field the person sees. nil without a layout.
    # scope show: the fields the person sees (core's visible custom fields and the core fields core draws); edit: the
    # custom fields the person may edit (core draws the core fields in its own form).
    def sections_for(issue, user = ::User.current, scope: 'show', layout: nil, core_keys: nil)
      data = layout || for_issue(issue, scope)
      return nil unless data.is_a?(Hash) && data['sections'].is_a?(Array)

      context = scope.to_s == 'edit' ? 'edit' : 'show'
      values = if scope.to_s == 'edit'
                 issue.editable_custom_field_values(user)
               else
                 issue.visible_custom_field_values(user)
               end
      by_cf = values.to_h { |v| ["cf:#{v.custom_field_id}", v] }
      cores = scope.to_s == 'edit' ? [] : Array(core_keys || CORE.keys)
      used = []
      lang = ::User.current.language.presence || ::Setting.default_language
      out = data['sections'].filter_map do |s|
        fields = Array(s['fields']).filter_map do |f|
          key = f['field'].to_s
          used << key
          if (v = by_cf[key])
            { 'key' => key, 'custom_value' => v, 'width' => width_of(f, v.custom_field), 'appearance' => appearance(f, v.custom_field, context),
              'appearance_small' => context == 'show' ? appearance(f, v.custom_field, 'small') : nil }.compact
          elsif cores.include?(key)
            { 'key' => key, 'width' => f['width'].to_s == 'full' ? 'full' : 'half', 'appearance' => 'standard' }
          end
        end
        next if fields.empty?

        derived = fields.reduce(lowest_key) { |l, f| stricter(l, field_level(f['custom_value']&.custom_field)) }
        level = known_level?(s['level']) ? stricter(s['level'], derived) : derived
        # a section above the person's ceiling is not drawn at all (gk_access); narrower than core, never wider
        next unless ::GkAccess.sees?(user, level, project: issue.project)

        { 'key' => s['key'].to_s, 'title' => title_of(s['title'], lang), 'columns' => s['columns'] == 1 ? 1 : 2,
          'collapsed' => s['collapsed'] == true, 'level' => level, 'fields' => fields }
      end
      rest = (cores - used).map { |k| { 'key' => k, 'width' => 'half', 'appearance' => 'standard' } } +
             (by_cf.keys - used).map { |k| { 'key' => k, 'custom_value' => by_cf[k], 'width' => width_of({}, by_cf[k].custom_field), 'appearance' => appearance({}, by_cf[k].custom_field, context),
                                       'appearance_small' => context == 'show' ? appearance({}, by_cf[k].custom_field, 'small') : nil }.compact }
      level = rest.reduce(lowest_key) { |l, f| stricter(l, field_level(f['custom_value']&.custom_field)) }
      if rest.any? && ::GkAccess.sees?(user, level, project: issue.project)
        out << { 'key' => OTHER, 'title' => t(:label_gk_fields_layout_other), 'columns' => 2, 'collapsed' => true, 'level' => level, 'fields' => rest }
      end
      out
    end

    # The levels a person sees fields in, in order (the line "You see")
    def levels_seen(sections) = level_keys.select { |l| Array(sections).any? { |s| s['level'] == l } }

    def width_of(spec, cf)
      return spec['width'].to_s if WIDTHS.include?(spec['width'].to_s)

      cf.full_width_layout? ? 'full' : 'half'
    end

    def title_of(title, lang)
      return title.to_s unless title.is_a?(Hash)

      (title[lang.to_s].presence || title[::Setting.default_language.to_s].presence || title.values.detect(&:present?)).to_s
    end

    def t(key, **) = ::I18n.t(key, **)

    # Core's fields of an issue as label and text, as the issue page draws them, for the preview on the
    # administration page (the issue page itself keeps core's own rows): key => [label, text]
    def core_rows(issue, view)
      off = issue.disabled_core_fields
      rows = { 'status' => [view.l(:field_status), issue.status&.name.to_s] }
      rows['priority'] = [view.l(:field_priority), issue.priority&.name.to_s] unless off.include?('priority_id')
      rows['assigned_to'] = [view.l(:field_assigned_to), issue.assigned_to ? view.link_to_principal(issue.assigned_to) : '-'] unless off.include?('assigned_to_id')
      rows['category'] = [view.l(:field_category), issue.category&.name || '-'] unless off.include?('category_id')
      rows['fixed_version'] = [view.l(:field_fixed_version), issue.fixed_version&.name || '-'] unless off.include?('fixed_version_id')
      rows['start_date'] = [view.l(:field_start_date), view.format_date(issue.start_date)] unless off.include?('start_date')
      rows['due_date'] = [view.l(:field_due_date), view.format_date(issue.due_date)] unless off.include?('due_date')
      rows['done_ratio'] = [view.l(:field_done_ratio), "#{issue.done_ratio}%"] unless off.include?('done_ratio')
      rows['estimated_hours'] = [view.l(:field_estimated_hours), view.l_hours(issue.estimated_hours.to_f)] unless off.include?('estimated_hours')
      rows
    end

    # ------------------------------------------------------------------ the issue page

    # Core's rows on the issue page, kept by their class instead of drawn: the layout places them
    class Collector
      attr_reader :rows

      def initialize = (@rows = {})

      def left(*args) = add(*args)
      def right(*args) = add(*args)
      def size = @rows.size

      def add(label = nil, text = nil, options = {})
        return @rows.values if label.nil?

        key = CORE.key(options[:class].to_s.split.first) or return
        @rows[key] = [label, text]
      end
    end

    # Core patch (Patches.apply!): core's helpers for the issue page's attributes, only for the page itself
    # (issues/show) and only when the issue has a layout: core's rows are kept (issue_fields_rows), the layout's
    # sections are drawn where core draws the half width custom fields, and the full width ones are in the sections
    # already. Other views that call issue_fields_rows (meetings, verifications) and an issue without a layout get
    # core's as it is.
    module ShowPatch
      def issue_fields_rows(&block)
        return super unless @virtual_path == 'issues/show' && @gk_fields_rows.nil? && (lay = GkFields::Layouts.for_issue(@issue, 'show'))

        @gk_fields_rows = GkFields::Layouts::Collector.new
        @gk_fields_layout = lay
        block.call(@gk_fields_rows)
        ''.html_safe
      end

      def render_half_width_custom_fields_rows(issue)
        return super unless @gk_fields_layout && !@gk_fields_drawn

        @gk_fields_drawn = true
        render(partial: 'gk_fields_layouts/sections', locals: { issue: issue, rows: @gk_fields_rows.rows,
                                                                sections: GkFields::Layouts.sections_for(issue, ::User.current, layout: @gk_fields_layout, core_keys: @gk_fields_rows.rows.keys) })
      end

      def render_full_width_custom_fields_rows(issue)
        @gk_fields_drawn ? ''.html_safe : super
      end
    end
  end
end
