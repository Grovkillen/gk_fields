# frozen_string_literal: true

module GkFields
  # A custom field format for a point in time. Core has a date only.
  #
  # Stored as text in the custom value, in UTC, minute precision: "2026-10-06 08:30:00Z" (ISO 8601 as RFC 3339 writes
  # it, with a space between date and time). The space and not "T" so that core's own date filter, which compares the
  # stored text with "YYYY-MM-DD HH:MM:SS" (written in UTC for this format, QueryPatch), sorts right against it (a "T"
  # sorts after every time on the same day).
  # Read with "T" as well (the API). Shown in the viewer's time zone (User#time_zone, else the server's) and core's
  # date and time format; edited with <input type="datetime-local">, read in the time zone of the one who saves.
  #
  # From Ruby: GkFields::DateTime.get(issue, cf) -> Time (UTC) or nil; GkFields::DateTime.set(issue, cf, time) puts
  # the value on the object (Time, the stored text or nil; nothing is saved).
  module DateTime
    FORMAT = 'gk_fields_datetime'
    STORED = /\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?Z\z/
    LOCAL = /\A(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?\z/
    KEEP = ['', '__none__'].freeze # empty, and bulk edit's "clear"

    module_function

    # The stored text as a Time in UTC, nil when it is not a stored value
    def parse(value)
      m = STORED.match(value.to_s.strip) or return nil
      y, mo, d, h, mi = m.captures.first(5).map(&:to_i)
      return nil unless valid?(y, mo, d, h, mi)

      ::Time.utc(y, mo, d, h, mi)
    end

    # A time as it is stored: UTC, whole minutes
    def dump(time)
      return '' if time.nil?

      t = time.respond_to?(:utc) ? time.utc : time.to_time.utc
      t.strftime('%Y-%m-%d %H:%M:00Z')
    end

    # What a form, the API or Ruby sends, as it is stored: a stored value (with Z) as it is, a value without zone (the
    # datetime-local field) in the time zone of user. Empty and bulk edit's clear as they are; anything else is kept
    # as written so that validation can refuse it.
    def normalize(value, user = ::User.current)
      text = value.to_s.strip
      return text if KEEP.include?(text)

      if (t = parse(text)) then dump(t)
      elsif (t = from_local(text, user)) then dump(t)
      else value.to_s
      end
    end

    # "2026-10-06T10:30" in the person's time zone (else the server's) as a Time in UTC, nil when it is not one
    def from_local(text, user = ::User.current)
      m = LOCAL.match(text.to_s.strip) or return nil
      y, mo, d, h, mi = m.captures.first(5).map(&:to_i)
      return nil unless valid?(y, mo, d, h, mi)

      tz = zone(user)
      (tz ? tz.local(y, mo, d, h, mi) : ::Time.local(y, mo, d, h, mi)).utc
    end

    def valid?(y, mo, d, h, mi) = ::Date.valid_date?(y, mo, d) && h < 24 && mi < 60

    def zone(user) = user.respond_to?(:time_zone) ? user.time_zone : nil

    # The time in the person's time zone (else the server's)
    def local(time, user = ::User.current)
      tz = zone(user)
      tz ? time.in_time_zone(tz) : time.getlocal
    end

    # The value for <input type="datetime-local">, in the person's time zone; nil when the value is not a stored one
    def to_input(value, user = ::User.current)
      t = parse(value) or return nil
      local(t, user).strftime('%Y-%m-%dT%H:%M')
    end

    # Core's date and time format in the person's time zone: "2026-10-06 10:30"
    def text(value, user = ::User.current)
      t = value.is_a?(String) ? parse(value) : value
      t ? Formatter.format_time(t, true, user) : ''
    end

    Formatter = Object.new.extend(::Redmine::I18n)

    def field(cf) = cf.is_a?(::CustomField) ? cf : ::CustomField.find_by(id: cf.to_i)

    # The value on an object (an issue, a project, anything with custom fields) as a Time in UTC, or nil
    def get(object, cf)
      f = field(cf) or return nil
      parse(object.custom_field_value(f))
    end

    # Puts the value on the object (not saved): a Time, a stored text, a datetime-local text or nil (empties it).
    # Returns what will be stored.
    def set(object, cf, time)
      f = field(cf) or return nil
      value = time.nil? ? '' : (time.is_a?(String) ? normalize(time) : dump(time))
      object.custom_field_values = { f.id.to_s => value }
      value
    end

    # Core patch for the filter (Patches.apply!). Core's date operators make the start and end of the chosen days in
    # the reader's time zone and write them as text without zone (Query#quoted_time) to compare with the stored text,
    # which is in UTC; a meeting between midnight and 02:00 Swedish time then fell on the day before. For this format
    # the bounds are written in UTC too, so the day is the reader's day. Only quoted_time's text changes; the
    # operators, relative dates and gk_queries' own (which call the same methods) are core's.
    module QueryPatch
      private # as in core

      def sql_for_custom_field(field, operator, value, custom_field_id)
        filter = @available_filters && @available_filters[field]
        cf = filter && filter[:field]
        return super unless cf.respond_to?(:field_format) && cf.field_format == FORMAT

        begin
          was = @gk_fields_utc_bounds
          @gk_fields_utc_bounds = true
          super
        ensure
          @gk_fields_utc_bounds = was
        end
      end

      def quoted_time(time, is_custom_filter)
        return super unless @gk_fields_utc_bounds && is_custom_filter && time.respond_to?(:getutc)

        time.getutc.strftime('%Y-%m-%d %H:%M:%S')
      end
    end

    # The format itself. Filtered as a date, the day in the reader's time zone (QueryPatch). Sorted by the stored
    # text, which sorts as time. Not grouped, not summed, one value.
    class Format < ::Redmine::FieldFormat::Unbounded
      self.multiple_supported = false
      self.searchable_supported = false
      self.totalable_supported = false
      self.form_partial = nil
      add FORMAT

      def label = 'label_gk_fields_format_datetime'

      def set_custom_field_value(custom_field, custom_field_value, value)
        v = super
        v.is_a?(Array) ? v.map { |x| DateTime.normalize(x) } : DateTime.normalize(v)
      end

      def cast_single_value(_custom_field, value, _customized = nil) = DateTime.parse(value)

      def validate_single_value(_custom_field, value, _customized = nil)
        DateTime.parse(value) ? [] : [::I18n.t('activerecord.errors.messages.invalid')]
      end

      def formatted_value(_view, _custom_field, value, _customized = nil, html = false)
        return Array(value).map { |v| one(v, html) }.join(', ') if value.is_a?(Array)

        one(value, html)
      end

      def one(value, html)
        t = DateTime.parse(value)
        return DateTime.text(t) if t

        html ? ERB::Util.html_escape(value.to_s) : value.to_s
      end

      def edit_tag(view, tag_id, tag_name, custom_value, options = {})
        view.text_field_tag(tag_name, DateTime.to_input(custom_value.value) || custom_value.value,
                            options.merge(id: tag_id, type: 'datetime-local', step: 60))
      end

      def bulk_edit_tag(view, tag_id, tag_name, custom_field, _objects, value, options = {})
        view.text_field_tag(tag_name, DateTime.to_input(value) || (value == '__none__' ? '' : value),
                            options.merge(id: tag_id, type: 'datetime-local', step: 60)) +
          bulk_clear_tag(view, tag_id, tag_name, custom_field, value)
      end

      def query_filter_options(_custom_field, _query) = { type: :date }
    end
  end
end
