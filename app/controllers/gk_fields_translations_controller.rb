# frozen_string_literal: true

# Translations: every text that is set up, with its name in the other languages. One page per sort of thing,
# "only what is missing", copy and paste, the picker's page for one text, the changes for everyone to read, and
# the proposals for texts as they are written. Names are shown as their core strings here (translation is off
# for this controller). Not for administrators only: five global permissions say who may do what (Review), and
# Redmine's texts have one of their own.
# REST (.json): the texts and their translations, the changes, the proposals and Redmine's texts, by the same rules
# as the pages and never more than they show. An OAuth token also needs the scope gk_fields_api_read to read and
# gk_fields_api_manage to change, besides the permission, which core asks of a token itself; an administrator's
# token needs only the scope, and then counts as an administrator in every rule (acts_as_admin?).
class GkFieldsTranslationsController < ApplicationController
  self.main_menu = false
  layout :pick_layout

  READS = %w[index changes proposals core].freeze

  before_action :require_login
  before_action :require_api_scope
  # Two declared functions, off by default. Translations with Copy and paste, Changed texts, Proposed texts and
  # Redmine's texts is 'fields.translations'; the picker's list is 'fields.picker'; the page for one text (find) is
  # there when either is on
  before_action -> { render_404 unless GkFields.feature?('fields.translations') },
                only: %i[index update exchange review import changes propose proposals decide core core_update core_yaml]
  before_action -> { render_404 unless GkFields.feature?('fields.picker') }, only: [:texts]
  before_action -> { render_404 unless GkFields.feature?('fields.picker') || GkFields.feature?('fields.translations') }, only: [:find]
  before_action :require_translate_or_core, only: [:index]
  before_action :require_translate, only: [:update, :exchange, :review, :import]
  before_action :require_core_texts, only: [:core, :core_update, :core_yaml]
  before_action :require_reviewer, only: [:decide]
  accept_api_auth :index, :update, :changes, :propose, :proposals, :decide, :core, :core_update

  def index
    # whoever may only override Redmine's texts has that tab only
    return redirect_to(gk_fields_core_texts_path) if !may?(:gk_fields_translate) && !api_request?

    t = GkFields::Translations
    @groups = t.groups
    respond_to do |format|
      format.html do
        # without a type the first tab that has something to translate (an empty sort of thing has no tab)
        @group = @groups[params[:type]] || @groups.values.find { |g| g.entries.call.any? } || @groups.values.first
        @languages = t.languages.empty? ? [] : t.editable_languages # the core language too: a translation in it is shown to its readers
        @core_language = t.core_language
        all = @group.entries.call
        @missing_count = all.count { |e| t.missing(e).any? }
        @only_missing = params[:missing] == '1'
        @rows = @only_missing ? all.select { |e| t.missing(e).any? } : all
        @pending = GkFieldsProposal.pending.count
      end
      format.api { api_index }
    end
  end

  def update
    return api_update if api_request?

    t = GkFields::Translations
    known = GkFields::Exchange.index
    changed = 0
    (params[:rows].respond_to?(:to_unsafe_h) ? params[:rows].to_unsafe_h : {}).each_value do |row|
      _group, entry = known[row['key'].to_s]
      next unless entry # only texts that exist, never a made up one

      changed += 1 if t.save_entry(entry, (row['t'] || {}).slice(*t.editable_languages), User.current, nil)
    end
    flash[:notice] = l(:notice_gk_fields_saved, count: changed)
    if params[:back_text].present?
      redirect_to gk_fields_find_path(text: params[:back_text])
    else
      redirect_to gk_fields_translations_path(type: params[:type], missing: params[:missing].presence)
    end
  end

  # Copy and paste: the YAML of a language to copy out
  def exchange
    exchange_setup
    return unless params[:make] && @languages.include?(@to)

    @yaml, @count = GkFields::Exchange.export(@to, only_missing: @only_missing)
  end

  # What a pasted YAML would change; nothing is saved
  def review
    exchange_setup
    @pasted = params[:yaml].to_s
    @review_to, @changes, @errors = GkFields::Exchange.review(@pasted)
    GkFields.paste_refused!(User.current, @review_to, @errors) if @errors.present?
    render :exchange
  end

  # Save what the person saw in the review
  def import
    saved = GkFields::Exchange.apply(params[:yaml].to_s)
    flash[:notice] = l(:notice_gk_fields_saved, count: saved)
    redirect_to gk_fields_exchange_path
  end

  # Redmine's texts: core's own locale keys in one content language, core's text and the instance's own, with a
  # filter for what is missing or the same as the English, a search, and the plugin's starting suggestions
  def core
    c = GkFields::CoreTexts
    @groups = GkFields::Translations.groups
    @core_languages = c.languages
    return render_404 if api_request? && params[:lang].present? && !@core_languages.include?(params[:lang].to_s)

    @lang = @core_languages.include?(params[:lang].to_s) ? params[:lang].to_s : c.default_language(@core_languages)
    @filter = c::FILTERS.include?(params[:filter].to_s) ? params[:filter].to_s : nil
    @q = params[:q].to_s.strip
    all = @lang ? c.rows(@lang) : []
    list = c.filter(all, @filter, @q)
    @row_count = list.size
    respond_to do |format|
      format.html do
        @counts = { 'missing' => all.count(&:missing?), 'own' => all.count { |r| r.own.present? }, 'proposals' => all.count(&:proposal) }
        @paginator = Redmine::Pagination::Paginator.new(@row_count, c::PER_PAGE, params['page'])
        @rows = list[@paginator.offset, @paginator.per_page] || []
        @pending = GkFieldsProposal.pending.count
        @may_translate = may?(:gk_fields_translate)
      end
      format.api do
        # as core's own lists: offset and limit, at most a page of the page (PER_PAGE)
        offset = [params[:offset].to_i, 0].max
        limit = params[:limit].to_i.positive? ? [params[:limit].to_i, c::PER_PAGE].min : c::PER_PAGE
        render json: { api_version: 1, lang: @lang, languages: @core_languages, filter: @filter, q: @q.presence,
                       total_count: @row_count, offset: offset, limit: limit,
                       texts: (list[offset, limit] || []).map { |r| GkFields::Api.core_text(r) } }
      end
    end
  end

  def core_update
    c = GkFields::CoreTexts
    lang = params[:lang].to_s
    return render_404 unless c.languages.include?(lang)
    return api_core_update(lang) if api_request?

    rows = params[:rows].respond_to?(:to_unsafe_h) ? params[:rows].to_unsafe_h : {}
    posted = rows.values.select { |r| r.is_a?(Hash) }.map { |r| { key: r['key'], value: r['value'], confirmed: r['confirmed'] } }
    saved, errors = c.save(lang, posted, User.current)
    flash[:notice] = l(:notice_gk_fields_saved, count: saved)
    flash[:error] = errors.first(20).join(' ') if errors.any?
    redirect_to gk_fields_core_texts_path(lang: lang, filter: params[:filter].presence, q: params[:q].presence, page: params[:page].presence)
  end

  # The instance's own texts of one language in the form of core's locale file
  def core_yaml
    lang = params[:lang].to_s
    return render_404 unless GkFields::CoreTexts.languages.include?(lang)

    send_data GkFields::CoreTexts.export(lang), filename: "redmine_#{lang}_gk_fields.yml", type: 'text/yaml; charset=utf-8', disposition: 'inline'
  end

  # The picker's list: every text on screen that can be administered, as it is shown in the reader's language
  def texts
    return render(json: { texts: [] }) unless GkFields::Review.any?(User.current)

    lang = I18n.locale.to_s
    list = GkFields::Exchange.index.values.map { |_g, e| (e.translations || {})[lang].presence || e.core.to_s }
    render json: { texts: list.map(&:strip).select { |s| s.length.between?(2, 200) }.uniq }
  end

  # One text found by what it says on screen: its languages, its changes, and the way to propose a new original
  def find
    @text = params[:text].to_s.strip
    lang = I18n.locale.to_s
    @languages = GkFields::Translations.languages.empty? ? [] : GkFields::Translations.editable_languages
    @core_language = GkFields::Translations.core_language
    @hits = @text.empty? ? [] : GkFields::Exchange.index.values.select do |_g, e|
      e.core.to_s.strip == @text || (e.translations || {})[lang].to_s.strip == @text
    end
    shown = readable_keys(@hits.map { |_g, e| e.key })
    @hits = @hits.select { |_g, e| shown.include?(e.key) }
    @changes = GkFieldsChange.where(text_key: @hits.map { |_g, e| e.key }).newest_first.limit(50).includes(:user).group_by(&:text_key)
    @translations_on = GkFields.feature?('fields.translations') # The links and the form lead to its pages
    @may_translate = @translations_on && GkFields::Review.may?(User.current, :gk_fields_translate)
  end

  # What has been changed, for everyone
  def changes
    @changes = GkFieldsChange.newest_first.limit(200).includes(:user).to_a
    shown = readable_keys(@changes.map(&:text_key))
    @changes = @changes.select { |c| shown.include?(c.text_key) }
    respond_to do |format|
      format.html
      format.api { render json: { api_version: 1, changes: @changes.map { |c| GkFields::Api.change(c) } } }
    end
  end

  # A proposal for a text as it is written, or a list value
  def propose
    return api_propose if api_request?
    return unless load_entry_for_proposal

    @consequences = GkFields::Review.consequences(@entry)
    return unless request.post?

    # the same text is no proposal: said before anything is saved
    return @errors = [l(:error_gk_fields_proposal_same)] if params[:after_text].to_s.strip == @entry.core.to_s.strip

    # The place fields.proposal in gk_records decides whether the reason is required (required by default, as before);
    # the reason is kept on the proposal only, as before
    check = defined?(GkRecords::Reasons) ? GkRecords::Reasons.check('fields.proposal', params[:reason]) : nil
    return @errors = [check.error] if check && !check.ok

    proposal = GkFields::Review.propose(@entry, params[:after_text], check ? check.text : params[:reason], User.current)
    if proposal.persisted?
      flash[:notice] = l(:notice_gk_fields_proposed)
      redirect_to gk_fields_proposals_path
    else
      @errors = proposal.errors.full_messages
    end
  end

  # The latest 200 proposals, newest first: of all of them for a reviewer, of one's own for everyone else (the page and
  # REST alike)
  def proposals
    @reviewer = may?(:gk_fields_review)
    scope = GkFieldsProposal.newest_first.includes(:proposed_by, :reviewed_by)
    scope = scope.where(proposed_by_id: User.current.id) unless @reviewer
    # the count per state for the filter, then the state asked for (state=pending|approved|rejected); pending first
    @counts = scope.unscope(:order).group(:state).count
    @state = %w[pending approved rejected since].include?(params[:state]) ? params[:state] : nil
    all = scope.limit(200).to_a
    # what happened since the person was here last (decisions on her own, new ones to review): shown first by itself
    # when there is any and no other filter is asked for, as the notice at her name leads here
    @fresh = GkFields::Review.since_last(User.current, all, @reviewer).map(&:id)
    @state = 'since' if @state.nil? && params[:all].blank? && @fresh.any? && !api_request?
    list = if @state == 'since' then all.select { |p| @fresh.include?(p.id) }
           elsif @state then all.select { |p| p.state == @state }
           else all
           end
    @proposals = list.sort_by.with_index { |p, i| [p.state == 'pending' ? 0 : 1, i] }
    known = GkFields::Exchange.index
    @consequences = @proposals.select { |p| p.state == 'pending' }.to_h { |p| [p.id, (e = known[p.text_key]&.last) ? GkFields::Review.consequences(e) : {}] }
    respond_to do |format|
      format.html { GkFields::Review.seen!(User.current) }
      format.api do
        render json: { api_version: 1, reviewer: @reviewer,
                       proposals: @proposals.map { |p| GkFields::Api.proposal(p, @consequences[p.id]) } }
      end
    end
  end

  def decide
    proposal = GkFieldsProposal.pending.find_by(id: params[:id])
    return render_404 unless proposal
    return api_decide(proposal) if api_request?

    if params[:verdict] == 'approve'
      _group, entry = GkFields::Exchange.index[proposal.text_key]
      ok, message = GkFields::Review.approve(proposal, entry, User.current, params[:note])
      ok ? flash[:notice] = l(:notice_gk_fields_approved) : flash[:error] = message
    else
      GkFields::Review.reject(proposal, User.current, params[:note])
      flash[:notice] = l(:notice_gk_fields_rejected)
    end
    redirect_to gk_fields_proposals_path
  end

  private

  def pick_layout = User.current.admin? ? 'admin' : 'base'

  # The permission as the pages ask it; over REST an administrator's token with this action's scope (without :admin)
  # counts as an administrator too, as on GK Access's REST
  def may?(permission) = GkFields::Review.may?(User.current, permission) || acts_as_admin?

  # An administrator as the pages ask it (User#admin?); over REST also an administrator's token with this action's
  # scope but without :admin (GK Compat's admin_allows?), as on GK Access's REST. The same answer is given to every rule
  # that asks for an administrator: the permissions (may?), HTML and core's settings in Redmine's texts, approving
  # one's own proposal and the texts one may see named.
  def acts_as_admin?
    User.current.admin? || (api_request? && GkFields::ApiScope.admin_allows?(User.current, action_scope))
  end

  # A value REST takes as a text: a string or a number, or nothing (empty)
  def text_value?(value) = value.nil? || value.is_a?(String) || value.is_a?(Numeric)

  def action_scope = READS.include?(action_name) ? GkFields::ApiScope::READ : GkFields::ApiScope::MANAGE

  # REST only (the pages have no token): the token, if any, has this action's scope; true without a token or without
  # compat
  def require_api_scope
    return true unless api_request?
    return true if GkFields::ApiScope.allows?(User.current, action_scope)

    render_403
    false
  end

  def require_translate
    deny_access unless may?(:gk_fields_translate)
  end

  def require_translate_or_core
    deny_access unless may?(:gk_fields_translate) || (!api_request? && may?(:gk_fields_core_texts))
  end

  def require_core_texts
    deny_access unless may?(:gk_fields_core_texts)
  end

  def require_reviewer
    deny_access unless may?(:gk_fields_review)
  end

  # The texts this person may see named. An issue category is shown with its project's name (and is found by its
  # own), so one in a project she cannot see is left out for whoever has none of the four permissions on texts that
  # are set up. Everything else is for everyone, as before.
  def readable_keys(keys)
    keys = keys.uniq
    return keys if GkFields::Review.any?(User.current) || acts_as_admin?

    ids = keys.filter_map { |k| k.to_s[/\AIssueCategory:(\d+):/, 1]&.to_i }
    return keys if ids.empty?

    seen = IssueCategory.where(id: ids).includes(:project).select { |c| c.project&.visible?(User.current) }.map(&:id)
    keys.select { |k| (id = k.to_s[/\AIssueCategory:(\d+):/, 1]).nil? || seen.include?(id.to_i) }
  end

  def load_entry_for_proposal
    @group, @entry = GkFields::Exchange.index[params[:key].to_s]
    return (render_404 && false) unless @entry
    return (deny_access && false) unless GkFields::Review.may_propose?(User.current, @entry)

    true
  end

  def exchange_setup
    @languages = GkFields::Translations.languages
    @core_language = GkFields::Translations.core_language
    @to = params[:to].presence || @languages.first
    @only_missing = params[:only_missing] == '1'
  end

  # ------------------------------------------------------------------ REST

  # The texts of one tab (type=) or of every tab, with their translations; missing=1: only those that lack one
  def api_index
    t = GkFields::Translations
    groups = params[:type].present? ? [@groups[params[:type].to_s]].compact : @groups.values
    return render_404 if groups.empty?

    texts = groups.flat_map do |g|
      list = g.entries.call
      list = list.select { |e| t.missing(e).any? } if params[:missing] == '1'
      list.map { |e| GkFields::Api.text(g, e) }
    end
    render json: { api_version: 1, core_language: t.core_language, languages: t.editable_languages,
                   types: @groups.values.map { |g| { key: g.key, label: g.label.call.to_s } }, texts: texts }
  end

  # { translations: [{ key, texts: { lang => text } }] }: every key must be a text that exists, every language one that
  # is offered and every text a string or a number (empty: the translation is removed), else 422 and nothing is saved.
  # A key given twice is saved once, with the later texts winning per language, so that the change log says before
  # and after as they were.
  def api_update
    t = GkFields::Translations
    items = params[:translations]
    return render_api_errors(l(:error_gk_fields_api_translations)) unless items.is_a?(Array)

    known = GkFields::Exchange.index
    langs = t.editable_languages
    plan = items.map do |item|
      item = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : nil
      return render_api_errors(l(:error_gk_fields_api_translations)) unless item.is_a?(Hash) && item['texts'].is_a?(Hash)

      _group, entry = known[item['key'].to_s]
      return render_api_errors(l(:error_gk_fields_api_unknown_key, key: item['key'].to_s)) unless entry

      unknown = item['texts'].keys.map(&:to_s) - langs
      return render_api_errors(l(:error_gk_fields_api_unknown_language, lang: unknown.join(', '), known: langs.join(', '))) if unknown.any?

      texts = item['texts']
      return render_api_errors(l(:error_gk_fields_api_translations)) unless texts.values.all? { |v| text_value?(v) }

      [entry, texts.to_h { |k, v| [k.to_s, v.to_s] }]
    end
    plan = plan.group_by { |entry, _texts| entry.key }.map { |_key, list| [list.first.first, list.map(&:last).reduce({}, :merge)] }
    saved = 0
    GkFieldsTranslation.transaction { plan.each { |entry, texts| saved += 1 if t.save_entry(entry, texts, User.current, nil) } }
    render json: { api_version: 1, saved: saved }
  end

  # { proposal: { key, after_text, reason } }: as the page Propose a change; the permission for the kind of text through
  # may?, so that an administrator's token with the scope may propose as an administrator may on the page
  def api_propose
    return render_404 unless request.post?

    raw = params[:proposal]
    return render_api_errors(l(:error_gk_fields_api_proposal_body)) unless raw.is_a?(ActionController::Parameters)

    p = raw.permit(:key, :after_text, :reason)
    group, entry = GkFields::Exchange.index[p[:key].to_s]
    return render_404 unless entry
    return deny_access unless entry.original && may?(GkFields::Review.propose_permission(entry))
    return render_api_errors(l(:error_gk_fields_proposal_same)) if p[:after_text].to_s.strip == entry.core.to_s.strip

    check = defined?(GkRecords::Reasons) ? GkRecords::Reasons.check('fields.proposal', p[:reason]) : nil
    return render_api_errors(check.error) if check && !check.ok

    proposal = GkFields::Review.propose(entry, p[:after_text], check ? check.text : p[:reason], User.current)
    return render_validation_errors(proposal) unless proposal.persisted?

    render json: { api_version: 1, type: group.key, proposal: GkFields::Api.proposal(proposal, GkFields::Review.consequences(entry)) },
           status: :created
  end

  # { verdict: "approve" | "reject", note }: as the reviewer's buttons; any other verdict is refused, never read as reject
  def api_decide(proposal)
    verdict = params[:verdict].to_s
    return render_api_errors(l(:error_gk_fields_api_verdict)) unless %w[approve reject].include?(verdict)

    if verdict == 'approve'
      _group, entry = GkFields::Exchange.index[proposal.text_key]
      ok, message = GkFields::Review.approve(proposal, entry, User.current, params[:note], admin: acts_as_admin?)
      return render_api_errors(message) unless ok
    else
      GkFields::Review.reject(proposal, User.current, params[:note])
    end
    render json: { api_version: 1, proposal: GkFields::Api.proposal(proposal.reload) }
  end

  # { lang, texts: [{ key, value, confirmed }] }: a value or confirmed not given stays as it is; an unknown key, a value
  # that is not a string or a number, a mark that is not true or false, or a text the rules refuse (a variable
  # Redmine's text lacks, HTML or one of Redmine's settings from someone who is not an administrator) gives 422 and
  # nothing is saved
  def api_core_update(lang)
    c = GkFields::CoreTexts
    items = params[:texts]
    return render_api_errors(l(:error_gk_fields_api_core_texts)) unless items.is_a?(Array)

    english = c.core_texts('en')
    stored = GkFieldsCoreText.where(locale: lang).index_by(&:text_key)
    posted = items.map do |item|
      item = item.respond_to?(:to_unsafe_h) ? item.to_unsafe_h : nil
      return render_api_errors(l(:error_gk_fields_api_core_texts)) unless item.is_a?(Hash)

      key = item['key'].to_s
      return render_api_errors(l(:error_gk_fields_api_unknown_key, key: key)) unless english.key?(key)

      flag = item['confirmed']
      unless text_value?(item['value']) && [nil, true, false].include?(flag)
        return render_api_errors(l(:error_gk_fields_api_core_texts))
      end

      rec = stored[key]
      confirmed = item.key?('confirmed') ? ActiveModel::Type::Boolean.new.cast(item['confirmed']) == true : rec&.confirmed == true
      { key: key, value: item.key?('value') ? item['value'].to_s : rec&.value.to_s, confirmed: confirmed ? '1' : '0' }
    end
    saved = 0
    errors = []
    GkFieldsCoreText.transaction do
      saved, errors = c.save(lang, posted, User.current, admin: acts_as_admin?)
      raise ActiveRecord::Rollback if errors.any?
    end
    c.refresh! # what the store read inside the transaction is read again
    return render_api_errors(errors) if errors.any?

    render json: { api_version: 1, lang: lang, saved: saved }
  end
end
