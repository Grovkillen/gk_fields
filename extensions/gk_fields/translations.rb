# frozen_string_literal: true

module GkFields
  # A declared function in records' register ('fields.translations', 'fields.picker'); off until switched on, and
  # off when records is not there. Only the pages, menus and the picker ask: translations already stored
  # apply whatever the switch says.
  def self.feature?(key) = defined?(::GkRecords::Features) ? ::GkRecords::Features.on?(key) : false

  # gk_access is there, with its levels: the layouts need it (required in IDENTITY.yml for the layouts; the code guards
  # itself without it). Without it
  # the plugin starts and does everything else; the layouts' menu item, pages and sections are not there.
  def self.access? = defined?(::GkAccess) && ::GkAccess.respond_to?(:levels) ? true : false

  # The layouts are there: the declared function 'fields.layouts' is on and gk_access is installed. Off, saved
  # layouts stay untouched and an issue is drawn as in core.
  def self.layouts? = access? && feature?('fields.layouts')

  # The content languages of every GK plugin, in one place (fields' setting Languages to offer): the language what is
  # set up is written in first, then the others, as language codes (["sv", "en"]). A plugin asks
  # GkFields.content_languages when fields is installed (defined?(::GkFields.content_languages)); without fields it
  # uses [Setting.default_language, 'en'] (uniq), the same as fields gives when its setting is empty.
  def self.content_languages = Translations.content_languages

  # The language what is set up is written in (the first of content_languages)
  def self.core_language = Translations.core_language

  # translations. Core keeps one string as the name of a tracker, a status, a priority, a role, a category, a
  # custom field and each value of a list field. Here they get a name per language.
  #
  # The core string is the key and is never changed: it is what is stored, validated, imported and sent by the
  # API, and what is shown when a language has no translation. Translation is reading only, and only where it is
  # switched on: in a page shown to a person, and in a mail (in the recipient's language). It is off in the pages
  # where the names themselves are edited (so a form never saves a translation back as the core string), in the
  # API unless the request says lang=, in scenarios, and everywhere outside a request (rake, console, jobs).
  module Translations
    # record_type => the attributes that can be translated
    TYPES = {
      'Tracker' => %w[name description], 'IssueStatus' => %w[name description], 'Enumeration' => %w[name],
      'Role' => %w[name], 'IssueCategory' => %w[name], 'CustomField' => %w[name description]
    }.freeze
    VALUE = 'possible_value'
    # where the core strings are edited or used as keys: never translated there
    OFF_CONTROLLERS = %w[trackers issue_statuses enumerations custom_fields roles issue_categories gk_fields_translations
                         gk_scenarios imports].freeze

    module_function

    # One text that can be translated, wherever it is kept: key (which text, stable), thing and what (shown to
    # the person and sent as context), core (as it is written), translations ({ lang => text }), history (the
    # records target its changes are logged on) and saver (texts, user, origin) -> true when something changed.
    # original (optional): (new text, user) changes the text as it is written; only through an approved proposal.
    Entry = Struct.new(:key, :thing, :what, :core, :translations, :history, :saver, :original, keyword_init: true)
    # A tab on the page Translations: a sort of thing, core's or a plugin's
    Group = Struct.new(:key, :label, :entries, keyword_init: true)

    # A plugin's model with single texts (a name, a description): fields keeps the other languages and translates
    # the readers, exactly as for core's models. off_controllers: where the plugin edits the names.
    def extra_types = (@extra_types ||= {})
    # A plugin that keeps its own texts per language offers them here: entries -> [Entry]
    def sources = (@sources ||= {})
    def all_types = TYPES.merge(extra_types.transform_values { |v| v[:attrs] })

    def register_type(type, attrs:, label:, records:, off_controllers: [])
      extra_types[type.to_s] = { attrs: attrs.map(&:to_s), label: label, records: records, off: off_controllers.map(&:to_s) }
      install_reader(type.to_s, attrs.map(&:to_s))
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] type #{type} not registered: #{e.class} #{e.message}")
    end

    def register_source(key, label:, entries:, models: [])
      sources[key.to_s] = { label: label, entries: entries, models: models.map(&:to_s) }
      fallback_targets! if defined?(::GkRecords::Targets)
    end

    # A change is always logged: a source's model that no plugin made a records target gets a plain one
    def fallback_targets!
      sources.values.flat_map { |s| s[:models] }.uniq.each do |model|
        next if ::GkRecords::Targets.all.values.any? { |t| t.model == model }

        ::GkRecords::Targets.register(model.underscore, model: model, visible: ->(_o, user) { user.admin? }, editable: ->(_o, user) { user.admin? },
                                                         label: ->(o) { o.respond_to?(:name) ? o.name.to_s : "#{model} ##{o.id}" }, url: ->(_o) { nil })
      end
    end

    def off_controller?(name)
      OFF_CONTROLLERS.include?(name) || extra_types.values.any? { |v| v[:off].include?(name) }
    end

    def groups
      g = {}
      all_types.each_key do |type|
        label = extra_types[type] ? extra_types[type][:label] : -> { ::I18n.t("label_gk_fields_type_#{type.underscore}") }
        g[type] = Group.new(key: type, label: label, entries: -> { rows(type).map { |r| entry_for(type, r) } })
      end
      sources.each { |key, s| g[key] = Group.new(key: key, label: s[:label], entries: s[:entries]) }
      g
    end

    def entry_for(type, row)
      o = row.record
      thing = o.read_attribute(:name).to_s
      thing += " (#{o.project[:name]})" if o.respond_to?(:project) && o.project
      Entry.new(key: [type, o.id, row.attr, row.key].compact.join(':'), thing: thing, what: ::I18n.t("label_gk_fields_attr_#{row.attr}"),
                core: row.core, translations: row.translations, history: row.stored_id && "gk_fields_translation:#{row.stored_id}",
                saver: ->(texts, user, origin) { !store(type, o.id, row.attr, row.key, texts, user: user, origin: origin).nil? },
                original: if row.attr == VALUE
                            ->(text, _user) { Review.rename_value!(o.id, row.key, text) }
                          else
                            ->(text, _user) { Review.write_attribute!(o.class.base_class.name, o.id, row.attr, text) }
                          end)
    end

    # Every save of translations goes through here, whatever the way in (the page, a paste, the picker): the text is
    # saved where it is kept, and each language that changed is a row everyone may read (GkFieldsChange)
    def save_entry(entry, texts, user, origin)
      before = (entry.translations || {}).dup
      wanted = texts.to_h.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }
      return false unless entry.saver.call(wanted, user, origin)

      person = user&.logged? ? user : nil
      wanted.each do |lang, text|
        next if before[lang].to_s == text

        ::GkFieldsChange.create!(text_key: entry.key, thing: entry.thing.to_s.truncate(250), what: entry.what.to_s.truncate(250), lang: lang,
                               before_text: before[lang], after_text: text, user_id: person&.id,
                               origin: origin || (person ? 'human' : 'system'), created_at: Time.current)
      end
      true
    end

    # For a plugin that keeps its own texts: the change written in records on the thing (before and after, per language)
    def log(record, what, before, after, user, origin = nil)
      return unless record && defined?(::GkRecords::Events) && ::GkRecords::Targets.for_object(record)

      details = (before.keys | after.keys).each_with_object({}) do |l, h|
        h["#{what} (#{l})"] = [before[l], after[l]] if before[l].to_s != after[l].to_s
      end
      return if details.empty?

      person = user&.logged? ? user : nil
      ::GkRecords::Events.write(record, 'changed', details: details, user: person, origin: origin || (person ? 'human' : 'system'))
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] translation history not written: #{e.class} #{e.message}")
    end

    def active? = Thread.current[:gk_fields_on] == true
    def lang = (Thread.current[:gk_fields_lang] || ::I18n.locale).to_s

    def settings = (::Setting.plugin_gk_fields || {})

    # The language the core strings are written in: it needs no translation
    def core_language = settings['core_language'].to_s.strip.presence || ::Setting.default_language.to_s

    # The languages what is set up is offered in (the core language first)
    def content_languages
      # a list from the page's choice of languages, or a line of codes as stored before
      v = settings['content_languages']
      langs = (v.is_a?(Array) ? v.map(&:to_s) : v.to_s.split(/[\s,]+/)).map(&:strip).reject(&:empty?)
      langs = [::Setting.default_language.to_s, 'en'] if langs.empty?
      ([core_language] + langs).uniq
    end

    def languages = content_languages - [core_language]

    # The languages a text's translations are shown and edited in on the pages: every content language, the core
    # language included, since a translation in it is shown to its readers as in any other language
    def editable_languages = content_languages

    def with(on, lang: nil)
      prev = [Thread.current[:gk_fields_on], Thread.current[:gk_fields_lang]]
      Thread.current[:gk_fields_on] = on
      Thread.current[:gk_fields_lang] = lang.to_s.presence
      refresh! if on
      yield
    ensure
      Thread.current[:gk_fields_on], Thread.current[:gk_fields_lang] = prev
    end

    def without(&block) = with(false, &block)

    # All translations in memory, read again when a row was added or changed (one small query per request)
    def refresh!
      stamp = ::GkFieldsTranslation.pick(Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)'))
      return if stamp == @stamp

      @table = ::GkFieldsTranslation.all.each_with_object({}) do |r, h|
        h[[r.record_type, r.record_id, r.attribute_name, r.value_key.presence]] = r.translations_hash
      end
      @stamp = stamp
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] translations not read: #{e.class} #{e.message}")
      @table = {}
    end

    def table = (@table ||= {})

    # The translation in the reader's language, or nil (then the core string is shown). Found by the record's id and
    # attribute only, never by its text, and in every language the core language included: what is stored for that
    # text in the reader's language is shown, whatever the core language is now or was when it was written.
    def lookup(type, id, attr, key = nil)
      t = table[[type, id, attr.to_s, key]]
      t && t[lang].presence
    end

    # A list field's value as its label
    def value_label(custom_field, value)
      return value unless active? && value.is_a?(String) && custom_field&.id

      lookup('CustomField', custom_field.id, VALUE, value) || value
    end

    # For a request (an ApplicationController, ControllerPatch): on for pages shown to a person; in the API only with
    # lang=
    def for_request(controller, &block)
      lang = nil
      if controller.send(:api_request?)
        # the API gives core strings (they are the keys), and names in a language only when asked: lang=en.
        # That holds for the lists of trackers and statuses too; only their forms are kept on the core string.
        lang = controller.params[:lang].to_s.presence
        on = !lang.nil?
      else
        on = !off_controller?(controller.controller_name)
      end
      with(on, lang: lang, &block)
    end

    # A reader per attribute: the translation when switched on and there is one, otherwise what core gives
    def reader(type, attrs)
      Module.new do
        attrs.each do |a|
          define_method(a) do
            core = defined?(super) ? super() : read_attribute(a)
            return core unless GkFields::Translations.active? && !new_record?

            GkFields::Translations.lookup(type, id, a) || core
          end
        end
      end
    end

    # The REST API's custom field values: value is always the stored value, the same in every language, so that a
    # client never has to keep track of languages; with lang= a list field also gets value_lang, the value's name in that
    # language (the names of trackers and statuses are translated beside their ids in the same way). Without lang= the
    # API is not translated (active? is off) and is core's own.
    module ApiValuesPatch
      def render_api_custom_values(custom_values, api)
        return super unless GkFields::Translations.active?

        api.array :custom_fields do
          custom_values.each do |custom_value|
            cf = custom_value.custom_field
            attrs = { id: custom_value.custom_field_id, name: cf.name }
            attrs[:multiple] = true if cf.multiple?
            list = cf.field_format == 'list'
            api.custom_field attrs do
              if custom_value.value.is_a?(Array)
                values = custom_value.value.reject(&:blank?)
                api.array(:value) { values.each { |v| api.value v } }
                api.array(:value_lang) { values.each { |v| api.value_lang GkFields::Translations.value_label(cf, v) } } if list
              else
                api.value custom_value.value
                api.value_lang GkFields::Translations.value_label(cf, custom_value.value) if list && custom_value.value.present?
              end
            end
          end
        end unless custom_values.empty?
      end
    end

    # The labels of a list field's values. What is stored and validated is the core string; only the label changes.
    module ListFormatPatch
      def possible_values_options(custom_field, object = nil)
        opts = super
        return opts unless GkFields::Translations.active?

        opts.map { |v| GkFields::Translations.pair(custom_field, v) }
      end

      def possible_custom_value_options(custom_value)
        return super unless GkFields::Translations.active?

        cf = custom_value.custom_field
        raw = cf.possible_values
        missing = [custom_value.value].flatten.reject(&:blank?) - raw
        (raw + missing).map { |v| GkFields::Translations.pair(cf, v) }
      end

      def formatted_value(view, custom_field, value, customized = nil, html = false)
        return super unless GkFields::Translations.active? && custom_field.url_pattern.blank?

        shown = value.is_a?(Array) ? value.map { |v| GkFields::Translations.value_label(custom_field, v) } : GkFields::Translations.value_label(custom_field, value)
        super(view, custom_field, shown, customized, html)
      end
    end

    def pair(custom_field, value)
      return value unless value.is_a?(String)

      label = lookup('CustomField', custom_field.id, VALUE, value)
      label ? [label, value] : value
    end

    # Core patch (Patches.apply!): around every action of every controller (a method, not a callback, so controllers
    # loaded before this plugin are covered too)
    module ControllerPatch
      def process_action(*args)
        GkFields::CoreTexts.refresh! # Redmine's texts as this instance has corrected them, also when another process saved
        GkFields::Translations.for_request(self) { super }
        GkFields::Translations.api_names!(self)
      end
    end

    # The REST API with lang=: a thing's name is the name as it is written, the same in every language, and name_lang is
    # its name in the language asked for, beside its id, as a list field's value and value_lang are (ApiValuesPatch). A
    # client that knows no languages keeps working on name and id. By key in the JSON: one thing, or a list of them.
    API_ONE = { 'tracker' => 'Tracker', 'status' => 'IssueStatus', 'default_status' => 'IssueStatus', 'priority' => 'Enumeration',
                'category' => 'IssueCategory', 'activity' => 'Enumeration' }.freeze
    API_LIST = { 'trackers' => 'Tracker', 'issue_statuses' => 'IssueStatus', 'roles' => 'Role', 'issue_priorities' => 'Enumeration',
                 'time_entry_activities' => 'Enumeration', 'document_categories' => 'Enumeration', 'issue_categories' => 'IssueCategory',
                 'custom_fields' => 'CustomField' }.freeze

    def api_names!(controller)
      return unless controller.send(:api_request?) && controller.params[:lang].present?

      res = controller.response
      return unless res.media_type.to_s.include?('json') && res.body.present?

      data = JSON.parse(res.body)
      found = Hash.new { |h, k| h[k] = [] }
      api_walk(data) { |type, thing| found[type] << thing }
      return if found.empty?

      found.each do |type, things|
        model = type.constantize
        # the description too where it is translated (trackers, statuses, custom fields): description and description_lang
        desc = TYPES.fetch(model.base_class.name, []).include?('description')
        cols = desc ? %i[id name description] : %i[id name]
        core = model.where(id: things.map { |t| t['id'] }).pluck(*cols).to_h { |row| [row[0], row[1..]] }
        things.each do |t|
          name, description = core[t['id'].to_i]
          next unless name

          t['name_lang'] = t['name']
          t['name'] = name
          next unless desc && t.key?('description')

          t['description_lang'] = t['description']
          t['description'] = description
        end
      end
      res.body = data.to_json
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] API names not given beside their labels: #{e.class} #{e.message}")
    end

    def api_walk(node, key = nil, &block)
      case node
      when Hash
        type = API_ONE[key]
        block.call(type, node) if type && node['id'] && node.key?('name')
        node.each { |k, v| api_walk(v, k, &block) }
      when Array
        type = API_LIST[key]
        node.each do |v|
          if type && v.is_a?(Hash) && v['id'] && v.key?('name')
            block.call(type, v)
            v.each { |k, w| api_walk(w, k, &block) }
          else
            api_walk(v, nil, &block)
          end
        end
      end
    end

    # Core patch (Patches.apply!): a mail is written in the recipient's language, names included
    module MailerPatch
      def process(action, *args)
        GkFields::CoreTexts.refresh!
        GkFields::Translations.with(true) { super }
      end
    end

    # The translated readers on a model (core's in Patches.apply!, a plugin's in register_type), once per class: a
    # class that already has them (the same class after a reload of this file) is left as it is
    def install_reader(type, attrs)
      klass = type.constantize
      cols = attrs.select { |a| klass.column_names.include?(a) }
      marker = "GkFieldsReader#{type}"
      return if klass.ancestors.any? { |m| m.instance_variable_get(:@gk_fields_marker) == marker }

      mod = reader(type, cols)
      mod.instance_variable_set(:@gk_fields_marker, marker)
      klass.prepend(mod)
    end

    # ------------------------------------------------------------------ the admin page and the scenarios
    Row = Struct.new(:record, :attr, :key, :core, :translations, :stored_id, keyword_init: true)

    def records(type)
      case type
      when 'Tracker' then ::Tracker.sorted.to_a
      when 'IssueStatus' then ::IssueStatus.sorted.to_a
      when 'Enumeration' then ::Enumeration.order(:type, :position).to_a
      when 'Role' then ::Role.givable.sorted.to_a
      when 'IssueCategory' then ::IssueCategory.includes(:project).order(:project_id, :name).to_a
      when 'CustomField' then ::CustomField.order(:type, :position).to_a
      else extra_types[type] ? extra_types[type][:records].call.to_a : []
      end
    end

    # Every text of a type that can be translated, with what is there: empty core texts (a description never
    # written) are left out
    def rows(type)
      stored = ::GkFieldsTranslation.where(record_type: type).index_by { |r| [r.record_id, r.attribute_name, r.value_key.presence] }
      records(type).flat_map do |o|
        list = all_types[type].select { |a| o.class.column_names.include?(a) }.map { |a| [a, nil, o.read_attribute(a)] }
        list += Array(o.read_attribute(:possible_values)).map { |v| [VALUE, v.to_s, v.to_s] } if type == 'CustomField' && o.field_format == 'list'
        list.reject { |_a, _k, core| core.blank? }.map do |a, k, core|
          Row.new(record: o, attr: a, key: k, core: core, translations: stored[[o.id, a, k]]&.translations_hash || {}, stored_id: stored[[o.id, a, k]]&.id)
        end
      end
    end

    def missing(row) = languages.select { |l| (row.translations || {})[l].blank? }

    # Save one text's translations; returns the row when something changed. merge: only fill what is empty.
    def store(type, id, attr, key, texts, user: User.current, merge: false, origin: nil)
      rec = ::GkFieldsTranslation.find_or_initialize_by(record_type: type, record_id: id, attribute_name: attr.to_s, value_key: key.presence)
      before = rec.translations_hash
      wanted = texts.to_h.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }
      after = merge ? wanted.reject { |_l, v| v.empty? }.merge(before.reject { |_l, v| v.blank? }) : before.merge(wanted)
      after = after.reject { |_l, v| v.blank? }
      return nil if after == before.reject { |_l, v| v.blank? } && rec.persisted?
      return nil if after.empty? && rec.new_record?

      rec.translations = after.to_json
      rec.updated_by_id = user&.logged? ? user.id : nil
      rec.updated_at = Time.current
      rec.save!
      history(rec, before, after, user, origin)
      rec
    end

    # Everything that can be changed has its history: an event in records on the text
    def history(rec, before, after, user, origin = nil)
      return unless defined?(::GkRecords::Events) && ::GkRecords::Targets.find('gk_fields_translation')

      details = (before.keys | after.keys).each_with_object({}) { |l, h| h[l] = [before[l], after[l]] if before[l].to_s != after[l].to_s }
      person = user&.logged? ? user : nil
      ::GkRecords::Events.write(rec, rec.previously_new_record? ? 'created' : 'changed', details: details, user: person, origin: origin || (person ? 'human' : 'system'))
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] translation history not written: #{e.class} #{e.message}")
    end

    # ------------------------------------------------------------------ seeded defaults
    # A plugin's starting rows (the kinds its migration puts in, a list made the first time it is used) are named in
    # English. seed_record! gives one text of such a row, by its id, a translation in every language the plugin has
    # (texts: { lang => text }), English and the core language included, so that each reader gets the text of her
    # language whatever the core language is. Only a text with no row of translations yet gets them: a translation
    # an administrator wrote or changed is never touched. True when a row was written.
    def seed_record!(type, record, attr, texts)
      texts = texts.to_h.transform_keys(&:to_s).transform_values { |v| v.to_s.strip }.reject { |_l, v| v.empty? }
      return false if texts.empty? || !record&.id
      return false unless seedable?(type)
      return false if ::GkFieldsTranslation.exists?(record_type: type.to_s, record_id: record.id, attribute_name: attr.to_s, value_key: nil)

      !store(type.to_s, record.id, attr, nil, texts, user: nil, origin: 'system').nil?
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] #{type} ##{record&.id} not seeded: #{e.class} #{e.message}")
      false
    end

    # The same for the rows of a plugin's model that have a key (key_column, set once and never changed), the texts
    # from the plugin's locales: label_key_prefix + the key, in each language that has it. A row without a key, or
    # with a key the locales do not have, is one an administrator made and is left alone. Run after initialization,
    # when the plugin has registered its type, and again where the plugin makes its starting rows. Returns how many
    # rows got texts.
    def seed!(type, label_key_prefix:, key_column: :key, attr: 'name')
      return 0 unless seedable?(type)

      type.to_s.constantize.where.not(key_column => [nil, '']).to_a.count do |o|
        seed_record!(type, o, attr, locale_texts("#{label_key_prefix}#{o.read_attribute(key_column)}"))
      end
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] #{type} not seeded: #{e.class} #{e.message}")
      0
    end

    # { lang => text } of a locale key in every language that has it (never another language's text as a fallback)
    def locale_texts(key)
      ::I18n.available_locales.each_with_object({}) do |l, h|
        t = ::I18n.t(key, locale: l, default: nil, fallback: false)
        h[l.to_s] = t.to_s if t.is_a?(String) && !t.strip.empty?
      end
    end

    # The type is registered and both tables are there (not before the migrations have run)
    def seedable?(type)
      all_types.key?(type.to_s) && ::GkFieldsTranslation.table_exists? && type.to_s.safe_constantize&.table_exists? ? true : false
    rescue StandardError
      false
    end

    # The stored translations of a type's texts: { record_id => { lang => text } }
    def stored(type, attr = 'name')
      ::GkFieldsTranslation.where(record_type: type.to_s, attribute_name: attr.to_s, value_key: nil)
                           .to_a.to_h { |r| [r.record_id, r.translations_hash] }
    end

    # Every language of one text, as an API gives it, by the record's id: the stored translation in each language, and
    # the core string for lang (the language it is written in, default the core language) when that language has none
    def texts_for(type, id, attr, core, lang: core_language)
      row = ::GkFieldsTranslation.find_by(record_type: type.to_s, record_id: id, attribute_name: attr.to_s, value_key: nil)
      t = (row ? row.translations_hash : {}).reject { |_l, v| v.to_s.strip.empty? }
      { lang.to_s => core.to_s }.merge(t).reject { |_l, v| v.to_s.strip.empty? }
    end
  end

  # records loads after this plugin and asks for the targets then
  def self.register_records!
    Translations.fallback_targets!
    ::GkRecords::Targets.register('gk_fields_translation', model: 'GkFieldsTranslation',
                                                           visible: ->(_r, user) { user.admin? }, editable: ->(_r, user) { user.admin? },
                                                           label: ->(r) { r.display },
                                                           url: ->(r) { { controller: 'gk_fields_translations', action: 'index', type: r.record_type } })
    ::GkRecords::Targets.register('gk_fields_core_text', model: 'GkFieldsCoreText',
                                                         visible: ->(_r, user) { user.admin? }, editable: ->(_r, user) { user.admin? },
                                                         label: ->(r) { r.display },
                                                         url: ->(r) { { controller: 'gk_fields_translations', action: 'core', lang: r.locale, q: r.text_key } })
    # a layout of an issue's head: created and changed are records' own kinds, removed is the plugin's (the list,
    # since a removed layout has no page of its own)
    ::GkRecords::Targets.register('gk_fields_layout', model: 'GkFieldsLayout',
                                                      visible: ->(_r, user) { user.admin? }, editable: ->(_r, user) { user.admin? },
                                                      label: ->(r) { r.place_text },
                                                      url: ->(_r) { { controller: 'gk_fields_layouts', action: 'index' } })
    ::GkRecords::Kinds.register_event('gk_fields_layout_removed', plugin: :gk_fields, label_key: 'label_gk_fields_event_layout_removed',
                                                                  target: 'gk_fields_layout')
    # the plugin's pages (GkFieldsPage): a pasted text that could not be read is an event on Copy and paste, by the
    # person who pasted it, with the language and where it broke, never the text itself
    ::GkRecords::Targets.register('gk_fields_page', model: 'GkFieldsPage',
                                                    visible: ->(_r, user) { user.admin? }, editable: ->(_r, _user) { false },
                                                    label: ->(r) { r.label }, url: ->(r) { r.url })
    ::GkRecords::Kinds.register_event('gk_fields_paste_refused', plugin: :gk_fields, label_key: 'label_gk_fields_event_paste_refused',
                                                                 target: 'gk_fields_page')
  end

  # Copy and paste refused a text: the event above, when records is there; otherwise nothing, as before.
  # A cooldown: at most one such event per person and minute, so that bad requests one after another never become a
  # row each (the person is still told what was wrong every time)
  PASTE_REFUSED_COOLDOWN = 60

  def self.paste_refused!(user, lang, errors)
    return unless user&.logged? && defined?(::GkRecords::Events) && ::GkRecords::Targets.find('gk_fields_page')
    # the cooldown is asked of records itself (Rails' cache is a null store in development and per process elsewhere)
    # the database counts the minute (now()), since Redmine's local time sent without a zone is read as UTC there
    return if ::GkRecordsEvent.where(kind: 'gk_fields_paste_refused', user_id: user.id)
                              .where("created_at > now() - make_interval(secs => ?)", PASTE_REFUSED_COOLDOWN).exists?

    details = { 'error' => Array(errors).first.to_s.first(300) }
    details['language'] = lang.to_s if lang.present?
    ::GkRecords::Events.write(::GkFieldsPage.for('exchange'), 'gk_fields_paste_refused', details: details, user: user, origin: 'human')
  rescue StandardError => e
    Rails.logger.warn("[gk_fields] paste refused not logged: #{e.class} #{e.message}")
  end
end
