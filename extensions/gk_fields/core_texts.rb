# frozen_string_literal: true

module GkFields
  # Redmine's texts: core's own locale keys corrected in this instance (overrides), on the page Translations. Core's
  # locale files are never changed. The overrides are rows in gk_fields_core_texts and are shown through I18n: a
  # backend in front of the one Redmine set up (I18n's Chain), so a key with an override gives it and every other key
  # gives core's text as before. An override removed is simply no longer found.
  #
  # Why a backend and not store_translations into core's backend: a text stored that way cannot be taken back without
  # reloading every locale file, it is lost each time I18n reloads its files (in development whenever a locale file
  # changes), and a backend that Redmine sets up again on a reload would drop it. The chain is put in place when the
  # plugin starts (Patches.apply!, on every preparation) and again at each request and mail (refresh!), so it is
  # there whatever Redmine did with I18n.backend; it is never put in twice. I18n.reload! reaches the overrides too:
  # they are read again from the table at the next lookup.
  module CoreTexts
    PER_PAGE = 100
    FILTERS = %w[missing own proposals].freeze
    PROPOSALS_DIR = File.expand_path('../../config/core_texts', __dir__)
    LOCK = Mutex.new

    # Core's locale keys that are settings read with l(), not words (the CSV export and import, the PDF, the calendar,
    # the text direction): a wrong value breaks those pages for every reader in the language, so only an administrator
    # changes them, and only to a value Redmine can use. A stored value that does not hold is never shown.
    SETTINGS = {
      'direction' => ->(v) { %w[ltr rtl].include?(v) },
      'general_csv_encoding' => ->(v) { ::Setting::ENCODINGS.any? { |e| e.casecmp?(v) } },
      'general_csv_separator' => ->(v) { v.length == 1 && !v.match?(/["'\s]/) },
      'general_csv_decimal_separator' => ->(v) { v.length == 1 },
      'general_first_day_of_week' => ->(v) { v.match?(/\A[1-7]\z/) },
      'general_pdf_fontname' => ->(v) { CoreTexts.core_values('general_pdf_fontname').include?(v) },
      'general_pdf_monospaced_fontname' => ->(v) { CoreTexts.core_values('general_pdf_monospaced_fontname').include?(v) }
    }.freeze

    # The corrections, read from the table. Never written to by anyone else: store_translations on the chain goes to
    # the backend below (Chain#store_translations would otherwise put it here, where the next reload drops it).
    class Store < ::I18n::Backend::Simple
      include ::I18n::Backend::Pluralization

      # The backend this one stands in front of, to complete a namespace or a plural with core's other keys
      attr_accessor :below

      # Only the language asked for: a fallback here (when I18n has put Fallbacks into Simple) would give a reader
      # an English correction before core's own text in her language. The chain, or the backend below, falls back.
      def translate(locale, key, options = ::I18n::EMPTY_HASH)
        super(locale, key, options.merge(fallback: false))
      end

      protected

      def init_translations
        LOCK.synchronize do
          @translations = CoreTexts.read_table
          @initialized = true
        end
      end

      def lookup(locale, key, scope = [], options = ::I18n::EMPTY_HASH)
        found = super
        return found unless found.is_a?(Hash) && below

        base = below.send(:lookup, locale, key, scope, options)
        base.is_a?(Hash) ? ::I18n::Utils.deep_merge(base, found) : found
      rescue StandardError
        found
      end
    end

    # I18n's chain with two changes: what other code stores goes to core's backend, and lookup (which some plugins
    # call to read a locale's text without fallbacks) asks the corrections first
    class Chain < ::I18n::Backend::Chain
      def store_translations(locale, data, options = ::I18n::EMPTY_HASH)
        backends.last.store_translations(locale, data, options)
      end

      protected

      def lookup(locale, key, scope = [], options = ::I18n::EMPTY_HASH)
        backends.each do |backend|
          found = backend.send(:lookup, locale, key, scope, options)
          return found unless found.nil?
        end
        nil
      end
    end

    Row = Struct.new(:lang, :key, :english, :core, :own, :confirmed, :proposal, :record, keyword_init: true) do
      # What a reader in the language sees now
      def shown = own.presence || core || english

      # Missing: core has no text in the language, or the same text as the English with words in it, and the
      # instance has neither its own text nor the mark that core's text is right. One of core's settings among its
      # texts (SETTINGS) is never missing: it is a value, not a word to translate.
      def missing?
        return false if lang == 'en' || own.present? || confirmed || CoreTexts::SETTINGS.key?(key)

        core.nil? || (core.strip == english.to_s.strip && CoreTexts.wordy?(english))
      end

      # Core's English or core's text in the language is not what it was when the row was saved
      def core_changed?
        record && (record.value.present? || record.confirmed) &&
          (record.english_text.to_s != english.to_s || record.core_text.to_s != core.to_s)
      end
    end

    module_function

    def store = (@store ||= Store.new)

    # Core patch (Patches.apply!, and refresh!): the chain in front of whatever backend Redmine has set up
    def install!
      current = ::I18n.backend
      return if current.is_a?(Chain)

      store.below = current
      store.reload!
      ::I18n.backend = Chain.new(store, current)
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] Redmine's texts not installed: #{e.class} #{e.message}")
    end

    def table?
      @table_ok ||= ::GkFieldsCoreText.table_exists?
    rescue StandardError
      false
    end

    # { locale => nested texts } of every correction with a text
    def read_table
      out = {}
      return out unless table?

      ::GkFieldsCoreText.where.not(value: [nil, '']).pluck(:locale, :text_key, :value).each do |locale, key, value|
        # a setting whose stored value Redmine cannot use is left to core's text
        next if (check = SETTINGS[key.to_s]) && !check.call(value.to_s)

        path = key.to_s.split('.').map(&:to_sym)
        leaf = path.pop
        node = path.inject(out[locale.to_sym] ||= {}) { |h, k| h[k].is_a?(Hash) ? h[k] : (h[k] = {}) }
        node[leaf] = value
      end
      out
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] Redmine's texts not read: #{e.class} #{e.message}")
      {}
    end

    # Once per request and mail: the chain in place (if anything replaced I18n.backend since the plugin started), and
    # the overrides read again when a row was added or changed in another process
    def refresh!
      install!
      return unless table?

      stamp = ::GkFieldsCoreText.pick(Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)'))
      return if stamp == @stamp

      @stamp = stamp
      store.reload!
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] Redmine's texts not refreshed: #{e.class} #{e.message}")
    end

    # ------------------------------------------------------------------ core's files
    def core_file(lang) = ::Rails.root.join('config', 'locales', "#{lang}.yml").to_s

    # The content languages core has a locale file for (GkFields.content_languages, English included)
    def languages = GkFields.content_languages.select { |l| l.match?(/\A[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?\z/) && File.file?(core_file(l)) }

    # The language the page opens in: the first that is not English
    def default_language(langs) = langs.detect { |l| l != 'en' } || langs.first

    # { 'dotted.key' => text } of core's locale file for the language, as the file says now
    def core_texts(lang) = flat_file(core_file(lang), lang)

    # Every value core's own locale files give a key (the fonts Redmine has for its languages)
    def core_values(key)
      (@core_values ||= {})[key] ||= Dir[::Rails.root.join('config', 'locales', '*.yml').to_s].filter_map do |f|
        flat_file(f, File.basename(f, '.yml'))[key]
      end.uniq
    end

    # The starting suggestions shipped with the plugin (config/core_texts/<lang>.yml): offered, never applied
    def proposals(lang)
      return {} unless lang.to_s.match?(/\A[A-Za-z-]+\z/)

      flat_file(File.join(PROPOSALS_DIR, "#{lang}.yml"), lang)
    end

    def flat_file(path, lang)
      return {} unless File.file?(path)

      mtime = File.mtime(path)
      cached = (@files ||= {})[path]
      return cached.last if cached && cached.first == mtime

      data = YAML.safe_load(File.read(path, encoding: 'UTF-8'), permitted_classes: [Symbol], aliases: true) || {}
      flat = flatten(data.is_a?(Hash) ? data[lang.to_s] : nil)
      @files[path] = [mtime, flat]
      flat
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] #{path} not read: #{e.class} #{e.message}")
      {}
    end

    # Only texts: lists (the names of days and months) and other values are left out
    def flatten(hash, prefix = nil, out = {})
      return out unless hash.is_a?(Hash)

      hash.each do |k, v|
        key = [prefix, k.to_s].compact.join('.')
        if v.is_a?(Hash)
          flatten(v, key, out)
        elsif v.is_a?(String)
          out[key] = v
        end
      end
      out
    end

    # A text with words in it, beside its variables, format directives and markup
    def wordy?(text) = text.to_s.gsub(/%\{\w+\}|%[-^#0-9]*[a-zA-Z]|<[^>]*>/, '').match?(/\p{L}{2,}/)

    # Every interpolation I18n fills in: %{name}, %{name|other} and %<name>fmt (I18n's own patterns); a name with | is
    # never one core's text has, so it is always refused
    def variables(text) = text.to_s.scan(/%\{([^}]*)\}|%<(\w+)>/).flatten.compact.uniq

    # ------------------------------------------------------------------ the page
    def rows(lang)
      english = core_texts('en')
      have = lang == 'en' ? english : core_texts(lang)
      offered = proposals(lang)
      stored = table? ? ::GkFieldsCoreText.where(locale: lang).includes(:updated_by).index_by(&:text_key) : {}
      english.sort.map do |key, en|
        rec = stored[key]
        prop = offered[key].presence
        prop = nil if prop == have[key] || prop == rec&.value
        Row.new(lang: lang, key: key, english: en, core: have[key], own: rec&.value, confirmed: rec ? rec.confirmed : false,
                proposal: prop, record: rec)
      end
    end

    def filter(rows, which, query)
      list = case which
             when 'missing' then rows.select(&:missing?)
             when 'own' then rows.select { |r| r.own.present? }
             when 'proposals' then rows.select(&:proposal)
             else rows
             end
      q = query.to_s.strip.downcase
      return list if q.empty?

      list.select { |r| [r.key, r.english, r.core, r.own, r.proposal].any? { |t| t.to_s.downcase.include?(q) } }
    end

    # Save what was posted for one language: [{ key:, value:, confirmed: }]. Only core's own keys; a text the same as
    # core's is no correction. admin: whether the person counts as an administrator for the rules below (the pages ask
    # User#admin?; REST also takes an administrator's token with the API's scope). Returns [saved, errors].
    def save(lang, posted, user, origin: nil, admin: user&.admin?)
      english = core_texts('en')
      have = lang == 'en' ? english : core_texts(lang)
      saved = 0
      errors = []
      posted.each do |p|
        key = p[:key].to_s
        next unless english.key?(key)

        value = p[:value].to_s.delete("\r\n")
        value = '' if value.strip.empty? || value == have[key]
        confirmed = p[:confirmed].to_s == '1'
        rec = ::GkFieldsCoreText.find_or_initialize_by(locale: lang, text_key: key)
        before = rec.value.to_s
        next if before == value && rec.confirmed == confirmed
        next if rec.new_record? && value.empty? && !confirmed

        if (error = problem(key, value, english[key], have[key], admin))
          errors << error
          next
        end

        rec.value = value.presence
        rec.confirmed = confirmed
        rec.english_text = english[key]
        rec.core_text = have[key]
        rec.updated_by_id = user&.logged? ? user.id : nil
        rec.updated_at = Time.current
        rec.save!
        if before != value
          core_shown = have[key] || english[key]
          log(rec, before.presence || core_shown, value.presence || core_shown, user, origin)
        end
        saved += 1
      end
      @stamp = nil
      refresh!
      [saved, errors]
    end

    # A correction may use only the variables core's texts have (another would break the page that shows it), markup
    # only from an administrator (whoever else may override never writes HTML into a page), and one of core's settings
    # among its texts (SETTINGS) only from an administrator and only as a value Redmine can use. admin: whether the
    # person counts as an administrator (save). Taking a setting's correction away is a change of the setting too, so
    # only an administrator does that as well.
    def problem(key, value, english, core, admin)
      return ::I18n.t(:error_gk_fields_core_text_setting, key: key) if SETTINGS.key?(key) && !admin
      return nil if value.empty?

      allowed = variables(english) | variables(core)
      extra = variables(value) - allowed
      if extra.any?
        return ::I18n.t(:error_gk_fields_core_text_variables, key: key, variables: extra.map { |v| "%{#{v}}" }.join(', '),
                                                            allowed: allowed.empty? ? '-' : allowed.map { |v| "%{#{v}}" }.join(', '))
      end
      return ::I18n.t(:error_gk_fields_core_text_setting, key: key) if (check = SETTINGS[key]) && !check.call(value)
      return ::I18n.t(:error_gk_fields_core_text_html, key: key) if !admin && (key.match?(/_html(\.|\z)/) || value.match?(/[<>]/))

      nil
    end

    # Every change of a text is a row everyone may read, and an event in records on the row when records is there
    def log(rec, before, after, user, origin)
      person = user&.logged? ? user : nil
      ::GkFieldsChange.create!(text_key: "core:#{rec.text_key}", thing: rec.text_key.truncate(250), what: ::I18n.t(:label_gk_fields_core_texts),
                               lang: rec.locale, before_text: before, after_text: after, user_id: person&.id,
                               origin: origin || (person ? 'human' : 'system'), created_at: Time.current)
      return unless defined?(::GkRecords::Events) && ::GkRecords::Targets.find('gk_fields_core_text')

      ::GkRecords::Events.write(rec, rec.previously_new_record? ? 'created' : 'changed', details: { rec.locale => [before, after] },
                                                                                       user: person, origin: origin || (person ? 'human' : 'system'))
    rescue StandardError => e
      Rails.logger.warn("[gk_fields] Redmine's text history not written: #{e.class} #{e.message}")
    end

    # The corrections of one language in the form of core's locale file, to keep or to send to Redmine's translators
    def export(lang)
      out = {}
      ::GkFieldsCoreText.where(locale: lang).where.not(value: [nil, '']).order(:text_key).pluck(:text_key, :value).each do |key, value|
        path = key.split('.')
        leaf = path.pop
        node = path.inject(out) { |h, k| h[k].is_a?(Hash) ? h[k] : (h[k] = {}) }
        node[leaf] = value
      end
      { lang => out }.to_yaml(line_width: -1)
    end
  end
end
