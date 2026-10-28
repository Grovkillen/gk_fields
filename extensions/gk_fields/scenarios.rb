# frozen_string_literal: true

module GkFields
  # A scenario carries its translations as data: the names of its statuses, priorities,
  # trackers, roles, custom fields and list values are in every locale file of the scenario, so what the scenario
  # made in the language it was run in gets its name in the scenario's other languages here. Only what is empty is
  # filled: a translation a person wrote is never overwritten.
  module Scenarios
    KINDS = { 'statuses' => [:status, 'IssueStatus'], 'priorities' => [:priority, 'Enumeration'], 'trackers' => [:tracker, 'Tracker'],
              'roles' => [:role, 'Role'], 'custom_fields' => [:custom_field, 'CustomField'] }.freeze
    FINDERS = { 'status' => ['statuses', ::IssueStatus], 'priority' => ['priorities', ::IssuePriority], 'tracker' => ['trackers', ::Tracker],
                'role' => ['roles', ::Role], 'custom_field' => ['custom_fields', ::IssueCustomField] }.freeze

    module_function

    # { "en" => texts } for the scenario's locale files other than the one it is run in
    def others(scenario)
      Dir[File.join(scenario.dir, 'locales', '*.yml')].sort.each_with_object({}) do |file, h|
        lang = File.basename(file, '.yml')
        next if lang == scenario.locale

        h[lang] = (YAML.safe_load(File.read(file, encoding: 'UTF-8')) || {})[lang] || {}
      end
    end

    def texts(others, *path)
      others.each_with_object({}) do |(lang, all), h|
        v = path.map(&:to_s).reduce(all) { |x, k| x.is_a?(Hash) ? x[k] : nil }
        h[lang] = v.to_s if v.is_a?(String) || v.is_a?(Numeric)
      end
    end

    # A scenario layout as the JSON GkFields::Layouts reads: a custom field by its scenario key becomes cf:<id> (the
    # block finds it), a section title is the scenario text in each of its languages
    def layout_data(scenario, others, item)
      sections = Array(item['sections']).map do |s|
        title = { scenario.locale.to_s => scenario.t(:fields, :layouts, item['key'], s['key']) }.merge(texts(others, :fields, :layouts, item['key'], s['key']))
        fields = Array(s['fields']).map do |f|
          f = f.is_a?(Hash) ? f.transform_keys(&:to_s) : { 'field' => f.to_s }
          name = f['field'].to_s
          f.merge('field' => Layouts::CORE.key?(name) ? name : "cf:#{yield(name).id}")
        end
        s.to_h.transform_keys(&:to_s).merge('title' => title, 'fields' => fields)
      end
      { 'sections' => sections }
    end

    # The people of the check fields_flow, made inside its transaction so that nothing is kept: a proposer whose own
    # role has only gk_fields_propose_list_values, a reviewer whose own role has only gk_fields_review, both members of
    # a project, and an outsider without a role
    def flow_people
      stamp = "#{::Time.current.to_i}#{rand(1000)}"
      project = ::Project.active.order(:id).first
      make = lambda do |key, permissions|
        user = ::User.new(firstname: 'Fields', lastname: key.capitalize, mail: "gk_fields_#{key}_#{stamp}@example.invalid")
        user.login = "gk_fields_#{key}_#{stamp}"
        user.save!
        if permissions
          role = ::Role.create!(name: "gk_fields #{key} #{stamp}", permissions: permissions)
          ::Member.create!(project: project, principal: user, role_ids: [role.id])
        end
        user
      end
      { 'proposer' => make.call('proposer', %i[gk_fields_propose_list_values]),
        'reviewer' => make.call('reviewer', %i[gk_fields_review]), 'outsider' => make.call('outsider', nil) }
    end

    def register!
      return unless defined?(::GkScenarios::Steps)

      ::GkScenarios::Steps.register('translations', plugin: :gk_fields, order: 400) do |ctx|
        sc = ctx.scenario
        other = others(sc)
        KINDS.each do |section, (kind, type)|
          sc.list(section).each do |item|
            obj = ctx.made[kind.to_s][item['key'].to_s] or next
            row = Translations.store(type, obj.id, 'name', nil, texts(other, section, item['key']), merge: true)
            ctx.note(:translation, "#{type}:#{obj.id}:name", row || obj, !row.nil?)
            next unless section == 'custom_fields'

            Array(item['value_keys']).each do |vk|
              core = sc.t(:custom_field_values, item['key'], vk)
              row = Translations.store(type, obj.id, Translations::VALUE, core, texts(other, :custom_field_values, item['key'], vk), merge: true)
              ctx.note(:translation, "#{type}:#{obj.id}:#{vk}", row || obj, !row.nil?)
            end
          end
        end
      end

      # fields: permissions: in the scenario gives its roles the text permissions (translate, propose_originals,
      # propose_list_values, review), so the scenario's people can be used to prove who may do what
      ::GkScenarios::Steps.register('field_permissions', plugin: :gk_fields, order: 60) do |ctx|
        Array((ctx.scenario.data['fields'] || {})['permissions']).each do |item|
          role = ctx.get(:role, item['role'])
          wanted = Array(item['may']).map { |p| :"gk_fields_#{p}" }
          lacking = wanted - role.permissions
          role.add_permission!(*lacking) if lacking.any?
          ctx.note(:field_permission, item['role'], role, lacking.any?)
        end
      end

      # fields: layouts: in the scenario gives a tracker (and maybe a status and a project) a layout of the issue's
      # head. A field is a core key or the key of one of the scenario's custom fields; a section's title is the
      # scenario's text fields.layouts.<layout>.<section> in each of its languages. Run again, the layout is written over. A layout
      # with plugin: is left out where that plugin is not installed.
      ::GkScenarios::Steps.register('field_layouts', plugin: :gk_fields, order: 410) do |ctx|
        sc = ctx.scenario
        other = others(sc)
        Array((sc.data['fields'] || {})['layouts']).each do |item|
          # plugin: the plugin whose fields the layout names (gis): without it the layout is not made, as an expectation with
          # plugin: is skipped
          next if ::GkScenarios::Expect.plugin_missing?(item)

          # a custom field the scenario made, also through another plugin's step (gis notes its place fields as its own)
          data = layout_data(sc, other, item) do |k|
            ctx.made['custom_field'][k.to_s] || ctx.made.each_value.map { |h| h[k.to_s] }.detect { |o| o.is_a?(::IssueCustomField) } ||
              ctx.get(:custom_field, k)
          end
          row = ::GkFieldsLayout.find_or_initialize_by(tracker_id: ctx.get(:tracker, item['tracker']).id,
                                                       status_id: item['status'] && ctx.get(:status, item['status']).id,
                                                       project_id: item['project'] && ctx.get(:project, item['project']).id,
                                                       scope: (item['scope'] || 'show').to_s)
          row.layout = JSON.generate(data)
          changed = row.new_record? || row.layout_changed?
          row.save!
          ctx.note(:field_layout, item['key'], row, changed)
        end
      end

      # fields_layout: <issue>, as: <person>: the sections the issue's layout shows the person, in order (sections:
      # [keys], the folded Other last) and the levels of the line "You see" (levels:); scope: edit for the form's
      # sections. The same sections_for draws the page.
      ::GkScenarios::Expect.register('fields_layout') do |ctx, e|
        user = ::User.find_by_login(::GkScenarios::Expect.login(ctx, e['as']))
        issue = ::GkScenarios::Expect.issue_for(ctx, e['fields_layout'])
        next({ 'ok' => false, 'want' => 'user and issue', 'got' => '-' }) unless user && issue

        sections = ctx.as(user) { Layouts.sections_for(issue, user, scope: (e['scope'] || 'show').to_s) }
        got = { 'sections' => Array(sections).map { |s| s['key'] }, 'levels' => Layouts.levels_seen(sections) }
        want = { 'sections' => Array(e['sections']).map(&:to_s), 'levels' => Array(e['levels'] || got['levels']).map(&:to_s) }
        { 'ok' => got == want, 'want' => want.to_s, 'got' => got.to_s }
      end

      # fields_appearance: <issue>, as: <person>, field: <the name's path in the scenario's texts, custom_fields.<key>
      # when no dot>: the section the field is drawn in for the person and its appearance on the page (show:) and on a
      # small screen (small:); absent: true when the field is never drawn for the person.
      ::GkScenarios::Expect.register('fields_appearance') do |ctx, e|
        user = ::User.find_by_login(::GkScenarios::Expect.login(ctx, e['as']))
        issue = ::GkScenarios::Expect.issue_for(ctx, e['fields_appearance'])
        path = e['field'].to_s.include?('.') ? e['field'].to_s.split('.') : ['custom_fields', e['field'].to_s]
        cf = ::IssueCustomField.find_by(name: ctx.scenario.t(*path))
        next({ 'ok' => false, 'want' => 'user, issue and field', 'got' => '-' }) unless user && issue && cf

        sections = ctx.as(user) { Layouts.sections_for(issue, user) }
        hit = Array(sections).each_with_object([]) do |s, a|
          f = s['fields'].detect { |x| x['key'] == "cf:#{cf.id}" }
          a << { 'section' => s['key'], 'show' => f['appearance'], 'small' => f['appearance_small'] } if f
        end.first
        want = e['absent'] ? nil : { 'section' => e['section'].to_s, 'show' => e['show'].to_s, 'small' => (e['small'] || e['show']).to_s }
        { 'ok' => hit == want, 'want' => want.to_s, 'got' => hit.to_s }
      end

      # fields_api: <issue>, as: <person>, field: <key or text path>, sees: true or false: whether the field's value
      # is among those REST and the issue's .json give the person (core's visible_custom_field_values, the same list
      # the API, CSV and the history use). A section's level hides only on the page; this is the real protection.
      ::GkScenarios::Expect.register('fields_api') do |ctx, e|
        user = ::User.find_by_login(::GkScenarios::Expect.login(ctx, e['as']))
        issue = ::GkScenarios::Expect.issue_for(ctx, e['fields_api'])
        path = e['field'].to_s.include?('.') ? e['field'].to_s.split('.') : ['custom_fields', e['field'].to_s]
        cf = ::IssueCustomField.find_by(name: ctx.scenario.t(*path))
        next({ 'ok' => false, 'want' => 'user, issue and field', 'got' => '-' }) unless user && issue && cf

        got = issue.visible_custom_field_values(user).any? { |v| v.custom_field_id == cf.id }
        want = e['sees'] != false
        { 'ok' => got == want, 'want' => want.to_s, 'got' => got.to_s }
      end

      # fields_layout_rules: <tracker>: what a layout must hold, proved on the tracker and rolled back. A text that is
      # not a layout, an unknown field, a field named twice, an appearance that is not an object, collapsed that is not
      # true or false and a second layout for the same place are refused; a
      # section may be made stricter than its fields only when every field in it is limited per role, and never less
      # strict than a field visible only to some roles; a
      # field the person may not see is never drawn, and Other gathers the fields the layout does not name.
      ::GkScenarios::Expect.register('fields_layout_rules') do |ctx, e|
        failed = []
        tracker = ::Tracker.find_by(name: ctx.scenario.t(:trackers, e['fields_layout_rules']))
        user = ::User.find_by_login(::GkScenarios::Expect.login(ctx, e['as']))
        issue = ::GkScenarios::Expect.issue_for(ctx, e['issue'])
        next({ 'ok' => false, 'want' => 'tracker, user and issue', 'got' => '-' }) unless tracker && user && issue

        ::ActiveRecord::Base.transaction do
          ::GkFieldsLayout.where(tracker_id: [tracker.id, issue.tracker_id]).delete_all
          role = ::Role.givable.detect { |r| !user.roles_for_project(issue.project).include?(r) }
          hidden = ::IssueCustomField.create!(name: "gk_fields layout #{::Time.current.to_i}", field_format: 'string', is_for_all: true,
                                              visible: false, role_ids: [role.id], trackers: [tracker, issue.tracker].uniq)
          section = ->(level, *fields) { { 'key' => 's', 'title' => { 'en' => 'S' }, 'level' => level, 'fields' => fields.map { |f| { 'field' => f } } }.compact }
          refused = lambda do |name, data|
            row = ::GkFieldsLayout.new(tracker: tracker, scope: 'show', layout: data.is_a?(String) ? data : JSON.generate(data))
            failed << name if row.valid?
          end
          refused.call('not_json', '{ sections: ')
          refused.call('no_sections', { 'sections' => [] })
          refused.call('unknown_field', { 'sections' => [section.call(nil, 'cf:0')] })
          refused.call('field_twice', { 'sections' => [section.call(nil, 'status'), section.call(nil, 'status').merge('key' => 't')] })
          refused.call('bad_width', { 'sections' => [section.call(nil).merge('fields' => [{ 'field' => 'status', 'width' => 'wide' }])] })
          refused.call('bad_appearance', { 'sections' => [section.call(nil).merge('fields' => [{ 'field' => "cf:#{hidden.id}", 'appearance' => { 'show' => 'nope' } }])] })
          # an appearance that is not an object, and collapsed that is not true or false, are refused, never read
          refused.call('appearance_not_object', { 'sections' => [section.call(nil).merge('fields' => [{ 'field' => 'status', 'appearance' => 'standard' }])] })
          refused.call('appearance_false', { 'sections' => [section.call(nil).merge('fields' => [{ 'field' => 'status', 'appearance' => false }])] })
          refused.call('collapsed_text', { 'sections' => [section.call(nil, 'status').merge('collapsed' => 'true')] })
          refused.call('level_lower', { 'sections' => [section.call('open', "cf:#{hidden.id}")] })
          # a required field in a section above the ceiling of a role that writes issues
          required = ::IssueCustomField.create!(name: "gk_fields required #{::Time.current.to_i}", field_format: 'string', is_for_all: true,
                                                is_required: true, visible: true, trackers: [tracker])
          tracker.reload # the tracker's custom fields, with the one just made
          low = ::GkAccess.lowest&.rank.to_i
          writer = ::Role.givable.detect { |r| r.allowed_to?(:add_issues) && (::GkAccess.ceilings[r.id] || low) < ::GkAccess.rank_of('sensitive').to_i }
          if writer
            above = ::GkFieldsLayout.new(tracker: tracker, scope: 'show', layout: JSON.generate({ 'sections' => [section.call('sensitive', "cf:#{required.id}")] }))
            above.valid?
            # refused for this reason, not for another
            failed << "required_above (#{above.errors.full_messages.join('; ')})" unless above.errors.full_messages.any? { |m| m.include?(required.name) && m.include?(writer.name) }
            open = ::GkFieldsLayout.new(tracker: tracker, scope: 'show', layout: JSON.generate({ 'sections' => [section.call('open', "cf:#{required.id}")] }))
            failed << "required_open_allowed (#{open.errors.full_messages.join('; ')})" unless open.valid?
          else
            failed << 'no_writer_below_sensitive'
          end
          # a section stricter than its fields: refused when a field in it is one everyone sees (core's status), as the
          # level hides only on the page; allowed when every field in it is limited per role
          open_stricter = ::GkFieldsLayout.new(tracker: tracker, scope: 'show', layout: JSON.generate({ 'sections' => [section.call('sensitive', 'status')] }))
          failed << 'stricter_open_field_allowed' if open_stricter.valid?
          stricter = ::GkFieldsLayout.new(tracker: tracker, scope: 'show', layout: JSON.generate({ 'sections' => [section.call('sensitive', "cf:#{hidden.id}")] }))
          failed << "stricter_allowed (#{stricter.errors.full_messages.join('; ')})" unless stricter.valid?
          stricter.save!
          failed << 'place_twice' if ::GkFieldsLayout.new(tracker: tracker, scope: 'show', layout: stricter.layout).valid?

          own = ::GkFieldsLayout.create!(tracker: issue.tracker, project: issue.project, scope: 'show',
                                         layout: JSON.generate({ 'sections' => [section.call('internal', 'status', "cf:#{hidden.id}")] }))
          seen = ctx.as(user) { Layouts.sections_for(issue, user) }
          keys = Array(seen).flat_map { |s| s['fields'].map { |f| f['key'] } }
          failed << 'hidden_drawn' if keys.include?("cf:#{hidden.id}")
          failed << "section_level (#{seen&.first&.dig('level')})" unless seen&.first&.dig('level') == 'internal'
          failed << 'other_last' unless seen&.last&.dig('key') == Layouts::OTHER && seen.last['collapsed']
          failed << 'project_first' unless Layouts.for_issue(issue) == own.data
          raise ::ActiveRecord::Rollback
        end
        { 'ok' => failed.empty?, 'want' => 'layouts hold', 'got' => failed.empty? ? 'layouts hold' : "not: #{failed.join(', ')}" }
      end

      # fields_may: one of the scenario's people may (or may not) do a thing with the texts. It proves the scenario's own
      # set up (the step field_permissions and the roles), not the plugin's rules, which fields_flow proves with
      # people of its own.
      ::GkScenarios::Expect.register('fields_may') do |ctx, e|
        user = ::User.find_by_login(::GkScenarios::Expect.login(ctx, e['fields_may']))
        got = user ? Review.may?(user, :"gk_fields_#{e['can']}") : nil
        { 'ok' => got == (e['equals'] != false), 'want' => (e['equals'] != false).to_s, 'got' => got.to_s }
      end

      # fields_flow: the whole way for a list value, with accounts and roles the check makes itself (a scenario's role
      # may have every permission, as basic's management has), and nothing of it kept (rolled back): the proposer saves
      # a translation at once and it is logged in her name; with only the permission to propose list values she may
      # not propose an original text but may propose the list value; she cannot approve her own; an outsider without a
      # role may nothing; the reviewer approves, and the value is renamed in the field, on everything stored and as the
      # key of its translations.
      ::GkScenarios::Expect.register('fields_flow') do |ctx, e|
        sc = ctx.scenario
        field = ::IssueCustomField.find_by(name: sc.t(:custom_fields, e['fields_flow']))
        old = e['value'].to_s
        new = "#{old} (scenario)"
        failed = []
        next({ 'ok' => false, 'want' => 'the field and a project', 'got' => '-' }) unless field && ::Project.active.exists?

        ::ActiveRecord::Base.transaction do
          people = flow_people
          index = Exchange.index
          value_entry = index["CustomField:#{field.id}:#{Translations::VALUE}:#{old}"]&.last
          name_entry = index["CustomField:#{field.id}:name"]&.last
          failed << 'entries' unless value_entry && name_entry
          raise ::ActiveRecord::Rollback if failed.any?

          lang = Translations.languages.first
          failed << 'translate_saves' unless Translations.save_entry(value_entry, { lang => "#{old} (#{lang})" }, people['proposer'], nil)
          change = ::GkFieldsChange.where(text_key: value_entry.key, lang: lang).order(:id).last
          failed << 'translate_logged' unless change && change.user_id == people['proposer'].id && change.after_text == "#{old} (#{lang})"
          failed << 'outsider_translates' if Review.may?(people['outsider'], :gk_fields_translate)
          failed << 'outsider_proposes' if Review.may_propose?(people['outsider'], value_entry)
          failed << 'proposer_originals' if Review.may_propose?(people['proposer'], name_entry)
          failed << 'proposer_list_value' unless Review.may_propose?(people['proposer'], value_entry)
          stored = ::CustomValue.where(custom_field_id: field.id, value: old).count
          proposal = Review.propose(value_entry, new, 'scenario', people['proposer'])
          failed << 'proposal_saved' unless proposal.persisted? && proposal.state == 'pending' && proposal.kind == 'list_value'
          failed << 'nothing_changed_yet' unless ::CustomField.find(field.id).read_attribute(:possible_values).include?(old)
          ok, = Review.approve(proposal, value_entry, people['proposer'], nil)
          failed << 'own_approval_refused' if ok
          ok, message = Review.approve(proposal, value_entry, people['reviewer'], 'scenario')
          failed << "approved (#{message})" unless ok
          values = ::CustomField.find(field.id).read_attribute(:possible_values)
          failed << 'renamed_in_field' unless values.include?(new) && !values.include?(old)
          failed << 'renamed_where_stored' unless ::CustomValue.where(custom_field_id: field.id, value: new).count == stored &&
                                                  ::CustomValue.where(custom_field_id: field.id, value: old).count.zero?
          failed << 'translation_follows' unless ::GkFieldsTranslation.exists?(record_type: 'CustomField', record_id: field.id,
                                                                             attribute_name: Translations::VALUE, value_key: new)
          failed << 'change_logged' unless ::GkFieldsChange.exists?(proposal_id: proposal.id, before_text: old, after_text: new)
          raise ::ActiveRecord::Rollback
        end
        failed << 'rolled_back' unless ::CustomField.find(field.id).read_attribute(:possible_values).include?(old)
        { 'ok' => failed.empty?, 'want' => 'the whole way', 'got' => failed.empty? ? 'the whole way' : "not: #{failed.join(', ')}" }
      end

      # fields_core_text: <core locale key>, lang: <language> (the first content language that is not English when not
      # given): one of Redmine's own texts corrected under Redmine's texts, and nothing of it kept (rolled back). The
      # correction is what I18n gives in the language, also through the backend's lookup without fallbacks, and is
      # logged before and after; core's English and the other languages are unchanged; a variable core's text does not
      # have, HTML from someone who is not an administrator, and one of Redmine's settings from someone who is not an
      # administrator or with a value Redmine cannot use are refused; an empty text gives core's text back.
      ::GkScenarios::Expect.register('fields_core_text') do |_ctx, e|
        c = CoreTexts
        key = (e['fields_core_text'] || 'field_is_in_roadmap').to_s
        lang = (e['lang'] || c.default_language(c.languages)).to_s
        admin = ::User.active.where(admin: true).order(:id).first
        english = c.core_texts('en')[key]
        core = c.core_texts(lang)[key] || english
        next({ 'ok' => false, 'want' => "#{key} in #{lang}", 'got' => '-' }) unless admin && english && c.languages.include?(lang) && lang != 'en'

        failed = []
        failed << 'chain' unless ::I18n.backend.is_a?(c::Chain)
        text = "#{core} (scenario)"
        ::ActiveRecord::Base.transaction do
          saved, errors = c.save(lang, [{ key: key, value: text }], admin)
          failed << "saved (#{errors.join(' ')})" unless saved == 1 && errors.empty?
          failed << 'shown' unless ::I18n.t(key, locale: lang) == text
          failed << 'lookup' unless ::I18n.backend.send(:lookup, lang.to_sym, key) == text
          failed << 'english_kept' unless ::I18n.t(key, locale: :en) == english
          change = ::GkFieldsChange.where(text_key: "core:#{key}", lang: lang).order(:id).last
          failed << 'logged' unless change && change.before_text == core && change.after_text == text && change.user_id == admin.id
          _n, errors = c.save(lang, [{ key: key, value: "#{core} %{gk_scenario_nothing}" }], admin)
          failed << 'variable_refused' if errors.empty?
          _n, errors = c.save(lang, [{ key: key, value: "<b>#{core}</b>" }], ::User.anonymous)
          failed << 'html_refused' if errors.empty?
          # one of Redmine's settings among its texts: only an administrator, and only a value Redmine can use
          _n, errors = c.save(lang, [{ key: 'general_csv_encoding', value: 'x' }], admin)
          failed << 'setting_value_refused' if errors.empty?
          _n, errors = c.save(lang, [{ key: 'general_csv_separator', value: ';' }], ::User.anonymous)
          failed << 'setting_refused' if errors.empty?
          failed << 'kept_after_refusals' unless ::I18n.t(key, locale: lang) == text
          c.save(lang, [{ key: key, value: '' }], admin)
          failed << 'core_back' unless ::I18n.t(key, locale: lang) == core
          raise ::ActiveRecord::Rollback
        end
        c.refresh!
        failed << 'rolled_back' unless ::I18n.t(key, locale: lang) == core
        { 'ok' => failed.empty?, 'want' => 'core text corrected', 'got' => failed.empty? ? 'core text corrected' : "not: #{failed.join(', ')}" }
      end

      # fields_translated: one of the scenario's things has its name in another language, as that locale file says:
      # { fields_translated: { status: assessed }, lang: en }; a list value: { custom_field: risk_kind }, value: supplier
      ::GkScenarios::Expect.register('fields_translated') do |ctx, e|
        sc = ctx.scenario
        kind, key = e['fields_translated'].to_a.first
        section, klass = FINDERS[kind.to_s]
        obj = klass&.find_by(name: sc.t(section, key))
        next({ 'ok' => false, 'want' => kind.to_s, 'got' => '-' }) unless obj

        lang = e['lang'].to_s
        other = others(sc).slice(lang)
        type = KINDS[section].last
        if e['value']
          want = texts(other, :custom_field_values, key, e['value'])[lang]
          row = ::GkFieldsTranslation.find_by(record_type: type, record_id: obj.id, attribute_name: Translations::VALUE, value_key: sc.t(:custom_field_values, key, e['value']))
        else
          want = texts(other, section, key)[lang]
          row = ::GkFieldsTranslation.find_by(record_type: type, record_id: obj.id, attribute_name: 'name', value_key: nil)
        end
        got = row&.translations_hash&.dig(lang)
        { 'ok' => want.present? && got == want, 'want' => want.to_s, 'got' => got.to_s }
      end

      # fields_registered: [type, ...]: each of the plugins' types is offered under Translations (register_type) with
      # its reader in place, so its names are translated where a page is drawn; a type of a plugin that is not in the
      # instance counts as missing
      # sources: [key, ...] in the same expectation: texts a plugin keeps itself and offers under Translations
      # (register_source), each giving its entries without an error
      ::GkScenarios::Expect.register('fields_registered') do |_ctx, e|
        want = Array(e['fields_registered']).map(&:to_s)
        got = want.select do |type|
          next false unless Translations.extra_types.key?(type)

          klass = type.safe_constantize
          klass && klass.ancestors.any? { |m| m.instance_variable_get(:@gk_fields_marker) == "GkFieldsReader#{type}" }
        end
        sources = Array(e['sources']).map(&:to_s)
        sources_ok = sources.select do |key|
          src = Translations.sources[key]
          src && (begin
            Array(src[:entries].call)
            true
          rescue StandardError
            false
          end)
        end
        want += sources
        got += sources_ok
        missing = want - got
        { 'ok' => missing.empty?, 'want' => "#{want.size} types", 'got' => missing.empty? ? "#{got.size} types" : "missing: #{missing.join(', ')}" }
      end

      # fields_datetime: the format Date and time on one of the scenario's issues, as one of its people with a time
      # zone, and nothing of it kept (rolled back): { fields_datetime: s1, as: tova, zone: Stockholm }; any zone, the
      # wanted values are counted from it. A time typed in the form (10:30) is stored in UTC (Stockholm in summer:
      # 08:30Z), shown and put back in the form as 10:30,
      # a stored value is kept as it is, an impossible date and a text are refused, empty is allowed, and core's date
      # filter finds the issue on the person's day, also for a time after midnight that is the day before in UTC.
      ::GkScenarios::Expect.register('fields_datetime') do |ctx, e|
        failed = []
        user = ::User.find_by_login(::GkScenarios::Expect.login(ctx, e['as']))
        issue = ::GkScenarios::Expect.issue_for(ctx, e['fields_datetime'])
        next({ 'ok' => false, 'want' => 'user and issue', 'got' => '-' }) unless user && issue

        dt = DateTime
        zone = ::ActiveSupport::TimeZone[(e['zone'] || 'Stockholm').to_s]
        next({ 'ok' => false, 'want' => 'a time zone', 'got' => e['zone'].to_s }) unless zone

        ::ActiveRecord::Base.transaction do
          pref = user.pref
          pref.time_zone = zone.name
          pref.save!
          user = ::User.find(user.id) # the time zone is read once per object
          cf = ::IssueCustomField.create!(name: "gk_fields scenario #{::Time.current.to_i}", field_format: dt::FORMAT, is_for_all: true,
                                          is_filter: true, visible: true, trackers: [issue.tracker])
          ctx.as(user) do
            # 10:30 in the person's zone, in UTC as stored (Stockholm in summer: 08:30Z)
            at = zone.local(2026, 7, 1, 10, 30).utc
            stored = dt.set(issue, cf, '2026-07-01T10:30')
            failed << "stored_utc (#{stored})" unless stored == dt.dump(at)
            failed << 'get' unless dt.get(issue, cf) == at
            failed << "shown_local (#{dt.text(stored, user)})" unless dt.text(stored, user).include?('10:30')
            failed << 'form_local' unless dt.to_input(stored, user) == '2026-07-01T10:30'
            failed << 'stored_kept' unless dt.normalize(at.strftime('%Y-%m-%dT%H:%M:00Z'), user) == stored
            failed << 'format_registered' unless ::Redmine::FieldFormat.find(dt::FORMAT).is_a?(dt::Format)
            fmt = cf.format
            failed << 'bad_date_refused' if fmt.validate_single_value(cf, dt.normalize('2026-02-30T10:00', user)).empty?
            failed << 'text_refused' if fmt.validate_single_value(cf, dt.normalize('i morgon', user)).empty?
            failed << 'empty_allowed' unless dt.normalize('', user) == '' && fmt.validate_custom_value(::CustomFieldValue.new(custom_field: cf, value: '')).empty?
            ::CustomValue.create!(custom_field: cf, customized: issue, value: stored)
            q = ::IssueQuery.new(name: 'gk_fields scenario', project: issue.project)
            q.filters = {}
            q.add_filter("cf_#{cf.id}", '=', ['2026-07-01'])
            failed << 'filter_day' unless q.issue_ids.include?(issue.id)
            q.filters = {}
            q.add_filter("cf_#{cf.id}", '=', ['2026-07-02'])
            failed << 'filter_other_day' if q.issue_ids.include?(issue.id)
            # 00:30 on 2 July in the person's zone (Stockholm in summer: 22:30Z on 1 July): the reader's day is the 2nd
            late = dt.normalize('2026-07-02T00:30', user)
            ::CustomValue.find_by(custom_field_id: cf.id, customized: issue).update!(value: late)
            q.filters = {}
            q.add_filter("cf_#{cf.id}", '=', ['2026-07-02'])
            failed << "filter_after_midnight (#{late})" unless q.issue_ids.include?(issue.id)
            q.filters = {}
            q.add_filter("cf_#{cf.id}", '=', ['2026-07-01'])
            failed << 'filter_after_midnight_day_before' if q.issue_ids.include?(issue.id)
          end
          raise ::ActiveRecord::Rollback
        end
        { 'ok' => failed.empty?, 'want' => 'utc stored, local shown', 'got' => failed.empty? ? 'utc stored, local shown' : "not: #{failed.join(', ')}" }
      end
    end
  end

  def self.register_scenarios! = Scenarios.register!
end
