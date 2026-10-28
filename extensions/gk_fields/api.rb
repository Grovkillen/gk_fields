# frozen_string_literal: true

module GkFields
  # OAuth token scopes on the REST API, through gk_compat when it is there (it is optional). A scope only limits: who
  # may do something is still the same check as on the pages (a permission, or the admin flag). Without gk_compat
  # 1.01.000 or later (the scope checks came there) core's own checks apply.
  module ApiScope
    module_function

    # Read the texts and their translations, the changes, the proposals, Redmine's texts and the layouts
    READ = :gk_fields_api_read
    # Save translations and Redmine's texts, propose and decide, and create, change and remove layouts
    MANAGE = :gk_fields_api_manage

    # True without a token; with a token only when it has the permission
    def allows?(user, permission)
      shim?(:scope_allows?) ? ::GkCompat.call(:scope_allows?, user, permission) : true
    end

    # The account is an administrator and the token, if any, has the permission (or :admin)
    def admin_allows?(user, permission)
      shim?(:admin_allows?) ? ::GkCompat.call(:admin_allows?, user, permission) : user.admin?
    end

    # gk_compat is there and has the shim for the running series (an older gk_compat has neither scope check)
    def shim?(name)
      defined?(::GkCompat) && ::GkCompat.respond_to?(:used) && ::GkCompat.used.shims.key?(name)
    end
  end

  # What the REST API answers: the same facts the pages show, never more. Times in ISO 8601 with the offset.
  module Api
    module_function

    def time(value) = value&.iso8601

    def user(person) = person && { id: person.id, name: person.name }

    # One text that can be translated (Translations::Entry), with the tab it is on
    def text(group, entry)
      { key: entry.key, type: group.key, thing: entry.thing.to_s, what: entry.what.to_s, text: entry.core.to_s,
        translations: (entry.translations || {}).reject { |_l, v| v.to_s.strip.empty? } }
    end

    def change(row)
      { id: row.id, key: row.text_key, thing: row.thing.to_s, what: row.what.to_s, lang: row.lang, before: row.before_text,
        after: row.after_text, user: user(row.user), origin: row.origin, proposal_id: row.proposal_id, created_on: time(row.created_at) }
    end

    # A proposal as the page Proposed texts shows it; consequences only while it waits
    def proposal(row, consequences = nil)
      out = { id: row.id, key: row.text_key, kind: row.kind, thing: row.thing.to_s, what: row.what.to_s, before: row.before_text,
              after: row.after_text, reason: row.reason, state: row.state, proposed_by: user(row.proposed_by),
              created_on: time(row.created_at), reviewed_by: user(row.reviewed_by), reviewed_on: time(row.reviewed_at),
              review_note: row.review_note }
      out[:consequences] = consequences if row.state == 'pending' && consequences
      out
    end

    # One of Redmine's texts in a language (CoreTexts::Row)
    def core_text(row)
      { key: row.key, english: row.english, text: row.core, override: row.own, confirmed: row.confirmed ? true : false,
        missing: row.missing?, suggestion: row.proposal, core_changed: row.core_changed? ? true : false,
        updated_on: time(row.record&.updated_at), updated_by: user(row.record&.updated_by) }
    end

    def layout(row)
      { id: row.id, tracker: row.tracker && { id: row.tracker.id, name: row.tracker.name },
        status: row.status && { id: row.status.id, name: row.status.name },
        project: row.project && { id: row.project.id, identifier: row.project.identifier, name: row.project.name },
        scope: row.scope, layout: row.data, updated_by_id: row.updated_by_id, updated_on: time(row.updated_at) }
    end
  end
end
