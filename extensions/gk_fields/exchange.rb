# frozen_string_literal: true

module GkFields
  # Copy and paste: the texts of one language as YAML to copy into an AI chat, and the translated YAML pasted
  # back. Nothing is saved from a paste before a person has seen what would change, and every change is logged
  # like any other (records events, origin import, before and after).
  # Every text that can be translated goes this way, core's and every plugin's (Translations.groups).
  # The format is a list, one entry per text: key (which text), context (what it is, for the translator; never
  # read back), the text as it is written, and the text in the language to translate to.
  module Exchange
    MAX_BYTES = 1_000_000
    Change = Struct.new(:entry, :key, :before, :after, :state, keyword_init: true)

    module_function

    # { key => [group, entry] } for every text that can be translated
    def index
      Translations.groups.each_value.with_object({}) do |group, h|
        group.entries.call.each { |e| h[e.key] = [group, e] }
      rescue StandardError => e
        Rails.logger.warn("[gk_fields] #{group.key} gave no texts: #{e.class} #{e.message}")
      end
    end

    def context(group, entry)
      [group.label.call, entry.thing.presence, entry.what.presence].compact.uniq.join(': ')
    end

    # The YAML to copy: every text, or only those the language lacks
    def export(to, only_missing: false)
      from = Translations.core_language
      lines = ["# #{::I18n.t(:text_gk_fields_yaml_1, from: from, to: to)}", "# #{::I18n.t(:text_gk_fields_yaml_2, to: to)}",
               "# #{::I18n.t(:text_gk_fields_yaml_3)}", "from: #{from}", "to: #{to}", 'texts:']
      count = 0
      index.each do |key, (group, entry)|
        have = (entry.translations || {})[to].to_s
        next if only_missing && have.present?

        count += 1
        lines << "  - key: #{key.to_json}"
        lines << "    context: #{context(group, entry).to_json}"
        lines << "    #{from}: #{entry.core.to_s.to_json}"
        lines << "    #{to}: #{have.to_json}"
      end
      [lines.join("\n") + "\n", count]
    end

    # What a pasted YAML would change: [language, changes, errors]. Nothing is saved here.
    def review(text)
      return [nil, [], [::I18n.t(:error_gk_fields_yaml_size)]] if text.to_s.bytesize > MAX_BYTES

      data = begin
        YAML.safe_load(text.to_s.sub(/\A\s*```[a-z]*\s*\n/, '').sub(/\n```\s*\z/, "\n"))
      rescue Psych::SyntaxError => e
        # where the text breaks, in the person's language; the parser's own message is English and technical
        return [nil, [], [::I18n.t(:error_gk_fields_yaml_parse, line: e.line, column: e.column)]]
      rescue StandardError
        # YAML that is not plain data (a date, an alias the safe loader refuses) is not the form copied out
        return [nil, [], [::I18n.t(:error_gk_fields_yaml_shape)]]
      end
      return [nil, [], [::I18n.t(:error_gk_fields_yaml_shape)]] unless data.is_a?(Hash) && data['texts'].is_a?(Array)

      to = data['to'].to_s
      from = data['from'].to_s
      return [to, [], [::I18n.t(:error_gk_fields_yaml_lang, lang: to, known: Translations.languages.join(', '))]] unless Translations.languages.include?(to)

      known = index
      changes = data['texts'].map do |item|
        next Change.new(key: item.inspect.truncate(80), state: 'unknown') unless item.is_a?(Hash)

        key = item['key'].to_s
        _group, entry = known[key]
        after = item[to].is_a?(String) || item[to].is_a?(Numeric) ? item[to].to_s.strip : ''
        next Change.new(key: key, after: after, state: 'unknown') unless entry

        before = (entry.translations || {})[to].to_s
        state = if item.key?(from) && item[from].to_s != entry.core.to_s then 'stale' # the text was rewritten since the copy
                elsif after.empty? then 'empty'
                elsif after == before then 'same'
                elsif before.empty? then 'new'
                else 'changed'
                end
        Change.new(entry: entry, key: key, before: before, after: after, state: state)
      end
      [to, changes, []]
    end

    # Save what the review found: new and changed texts only. Returns the number saved.
    def apply(text, user: User.current)
      to, changes, errors = review(text)
      return 0 if errors.any?

      changes.select { |c| %w[new changed].include?(c.state) }.count { |c| Translations.save_entry(c.entry, { to => c.after }, user, 'import') }
    end
  end
end
