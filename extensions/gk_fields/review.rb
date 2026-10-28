# frozen_string_literal: true

module GkFields
  # Who may do what with the texts, and the proposals.
  # A translation (a text in another language than the one it is written in) is saved at once and logged: the
  # original is untouched, so nothing else can break. A change of the text as it is written, and of a list value,
  # has other consequences (every language without a translation, import, API, formulas; a list value is stored
  # as text on every issue), so from anyone but an administrator it is a proposal that a reviewer approves.
  # Four permissions on the texts that are set up, all global: translate, propose originals, propose list values (its
  # own, for its consequences), review. A fifth, also global, overrides Redmine's own texts (CoreTexts); it is not
  # among the four, since the picker and the proposals concern the texts that are set up. An administrator has them
  # all. Nobody approves her own proposal but an administrator.
  module Review
    PERMISSIONS = %i[gk_fields_translate gk_fields_propose_originals gk_fields_propose_list_values gk_fields_review].freeze

    module_function

    def may?(user, permission)
      return false unless user&.logged?

      user.admin? || user.allowed_to_globally?(permission)
    end

    def any?(user) = PERMISSIONS.any? { |p| may?(user, p) }

    # The proposals that wait for this person to decide: not her own, unless she is an administrator
    # What waits for the person: the proposals to review (a reviewer), and her own proposals decided since she last
    # opened Proposed texts, so that an approval or a rejection is a notice at her name (gui_stuff's count)
    def waiting_for(user)
      to_review = 0
      if may?(user, :gk_fields_review)
        scope = ::GkFieldsProposal.pending
        scope = scope.where.not(proposed_by_id: user.id) unless user.admin?
        to_review = scope.count
      end
      to_review + decided_unseen(user)
    rescue StandardError
      0
    end

    SEEN = :gk_fields_proposals_seen

    def decided_unseen(user)
      return 0 unless user&.logged?

      seen = user.pref[SEEN].presence
      scope = ::GkFieldsProposal.where(proposed_by_id: user.id).where.not(state: 'pending').where.not(reviewed_by_id: user.id)
      scope = scope.where('reviewed_at > ?', Time.iso8601(seen.to_s)) if seen
      scope.count
    rescue StandardError
      0
    end

    # When the person last opened Proposed texts (nil: never)
    def seen_at(user)
      v = user&.logged? ? user.pref[SEEN].presence : nil
      v ? Time.iso8601(v.to_s) : nil
    rescue ArgumentError
      nil
    end

    # What happened since then, for her: decisions on her own proposals, and (a reviewer) proposals to review that came
    def since_last(user, proposals, reviewer)
      at = seen_at(user)
      proposals.select do |p|
        if p.proposed_by_id == user.id
          p.state != 'pending' && p.reviewed_by_id != user.id && p.reviewed_at && (at.nil? || p.reviewed_at > at)
        else
          reviewer && p.state == 'pending' && (at.nil? || p.created_at > at)
        end
      end
    end

    # Proposed texts opened: what happened is seen
    def seen!(user)
      return unless user&.logged?

      pref = user.pref
      pref[SEEN] = Time.now.utc.iso8601
      pref.save
    end

    def menu?(user)
      return waiting_for(user).positive? if user.admin?

      any?(user)
    end

    def menu_caption(user)
      n = waiting_for(user)
      n.positive? ? "#{::I18n.t(:label_gk_fields_proposals)} (#{n})" : ::I18n.t(:label_gk_fields_proposals)
    end

    def kind(entry) = entry.key.to_s.include?(":#{Translations::VALUE}:") ? 'list_value' : 'original'

    # The permission that proposes this kind of text: a list value has its own, for its consequences
    def propose_permission(entry) = kind(entry) == 'list_value' ? :gk_fields_propose_list_values : :gk_fields_propose_originals

    def may_propose?(user, entry)
      return false unless entry.original

      may?(user, propose_permission(entry))
    end

    # What approving would touch besides the text itself, for the reviewer: stored values, and the rules that name the
    # value, which gk_workflow_rules gives through its public method rules_naming (the rules whose conditions name the
    # text); never read from its table. Without that method the rules are not counted.
    def consequences(entry)
      type, id, attr, value = entry.key.split(':', 4)
      return {} unless type == 'CustomField' && attr == Translations::VALUE

      out = { 'stored_values' => ::CustomValue.where(custom_field_id: id.to_i, value: value).count }
      out['rules'] = ::GkWorkflowRules.rules_naming(value).count if defined?(::GkWorkflowRules) && ::GkWorkflowRules.respond_to?(:rules_naming)
      out
    rescue StandardError
      {}
    end

    def propose(entry, after, reason, user)
      ::GkFieldsProposal.create(text_key: entry.key, kind: kind(entry), thing: entry.thing.to_s.truncate(250), what: entry.what.to_s.truncate(250),
                              before_text: entry.core.to_s, after_text: after.to_s.strip, reason: reason.to_s.strip.presence, proposed_by_id: user.id,
                              state: 'pending', created_at: Time.current)
    end

    # Approve: the text is changed where it is kept, and the change is logged. admin: whether the person counts as an
    # administrator, who may approve her own (the pages ask User#admin?; REST also takes an administrator's token with
    # the API's scope). Returns [ok, message].
    def approve(proposal, entry, user, note, admin: user.admin?)
      return [false, ::I18n.t(:error_gk_fields_proposal_gone)] unless entry&.original
      return [false, ::I18n.t(:error_gk_fields_proposal_stale)] if entry.core.to_s != proposal.before_text.to_s
      return [false, ::I18n.t(:error_gk_fields_proposal_own)] if proposal.proposed_by_id == user.id && !admin

      ::GkFieldsProposal.transaction do
        entry.original.call(proposal.after_text, user)
        proposal.update!(state: 'approved', reviewed_by_id: user.id, reviewed_at: Time.current, review_note: note.to_s.strip.presence)
        ::GkFieldsChange.create!(text_key: entry.key, thing: entry.thing.to_s.truncate(250), what: entry.what.to_s.truncate(250), lang: Translations.core_language,
                               before_text: proposal.before_text, after_text: proposal.after_text, user_id: proposal.proposed_by_id,
                               origin: 'human', proposal_id: proposal.id, created_at: Time.current)
      end
      [true, nil]
    rescue ArgumentError => e
      # rename_value! says in the person's language why the value cannot be renamed
      [false, e.message.to_s.truncate(300)]
    rescue ::ActiveRecord::RecordInvalid => e
      # core's validation of the thing (a name already taken), in the person's language
      [false, e.record.errors.full_messages.join(' ').truncate(300)]
    rescue StandardError => e
      # anything else (a validation in core, the database) is written to the log; the page says the text was not changed
      Rails.logger.warn("[gk_fields] proposal #{proposal&.id} not approved: #{e.class} #{e.message}")
      [false, ::I18n.t(:error_gk_fields_proposal_not_applied)]
    end

    def reject(proposal, user, note)
      proposal.update!(state: 'rejected', reviewed_by_id: user.id, reviewed_at: Time.current, review_note: note.to_s.strip.presence)
    end

    # The text of a core thing or a registered model as it is written: its name or description
    def write_attribute!(type, id, attr, text)
      record = type.constantize.find(id)
      record.update!(attr => text)
    end

    # A list value renamed: in the field, on everything that has the value stored, and as the key of its translations
    def rename_value!(field_id, old, new)
      field = ::CustomField.find(field_id)
      values = Array(field.read_attribute(:possible_values)).map(&:to_s)
      raise ArgumentError, ::I18n.t(:error_gk_fields_value_gone) unless values.include?(old)
      raise ArgumentError, ::I18n.t(:error_gk_fields_value_taken) if values.include?(new)

      field.possible_values = values.map { |v| v == old ? new : v }
      field.default_value = new if field.default_value.to_s == old
      field.save!
      ::CustomValue.where(custom_field_id: field.id, value: old).update_all(value: new)
      ::GkFieldsTranslation.where(record_type: 'CustomField', record_id: field.id, attribute_name: Translations::VALUE, value_key: old)
                         .update_all(value_key: new, updated_at: Time.current)
    end
  end
end
