# frozen_string_literal: true

module GkFields
  # The picker's anchors. A text that can be administered is found by the key of its entry (Translations' Entry#key),
  # never by its words: on a page asked for with gk_fields_pick=1 by whoever may work with texts, the translated
  # readers (Translations.reader) and a list field's labels (Translations.value_label) end each name they give with
  # an invisible mark that carries the number of its entry on this page. The picker's script (PickerHooks) takes the
  # marks out of the page and puts the icon where each one stood, leading to that entry; the numbers' keys are written
  # into the page by the same hook. So a name is found wherever core draws it and whatever core's words, language,
  # markup or order, and a text that is not one of ours is never touched.
  #
  # Marks are given only while the request is a page (GET, HTML, not XMLHttpRequest, not the REST API), the function
  # fields.picker is on, translation is on for the controller or the page is core's list of trackers, statuses,
  # enumerations, custom fields or roles (Translations.list_page?: there the core strings are marked; never where the
  # names are edited, so a mark is never saved back) and the reader may work with texts (Review.any?, asked the first
  # time a mark is wanted, when the request's user is known). A mail sent from such a request gets none
  # (Translations.with). The mark is U+2063 (invisible separator), the number in binary as U+200B (0) and U+200C (1),
  # and U+2064 (invisible plus). Only a whole mark gets an icon; a mark cut short (a title shortened after the reader
  # gave it) is only taken out of the page's text, and a lone U+2063 in what a person wrote is left as it is.
  module Picker
    PARAM = 'gk_fields_pick'
    START = "⁣"
    STOP = "⁤"
    BITS = "​‌"

    module_function

    # Whether the request asks for the marks (ControllerPatch, through Translations.for_request); who reads it is asked
    # later (allowed?)
    def wanted?(controller)
      req = controller.request
      controller.params[PARAM].to_s == '1' && req.get? && !req.xhr? && !controller.send(:api_request?) &&
        (req.format.nil? || req.format.html?) && GkFields.feature?('fields.picker')
    rescue StandardError
      false
    end

    # The state of this request: nil, or { allowed: nil/true/false, keys: { entry key => number } }
    def state = Thread.current[:gk_fields_pick]
    def state=(value)
      Thread.current[:gk_fields_pick] = value
    end

    def fresh(wanted) = wanted ? { allowed: nil, keys: {} } : nil

    def on?
      s = state
      return false unless s

      s[:allowed] = Review.any?(::User.current) ? true : false if s[:allowed].nil?
      s[:allowed]
    rescue StandardError
      false
    end

    # The text with its entry's mark at the end, or the text as it is
    def mark(key, text)
      return text unless text.is_a?(String) && !text.empty? && on?

      keys = state[:keys]
      n = (keys[key.to_s] ||= keys.size)
      "#{text}#{START}#{n.to_s(2).tr('01', BITS)}#{STOP}"
    end

    # The entries' keys in the order of their numbers, for the page's script
    def keys
      s = state
      s && s[:allowed] ? s[:keys].sort_by(&:last).map(&:first) : []
    end
  end
end
