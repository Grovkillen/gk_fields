# frozen_string_literal: true

# The layouts of an issue's head (Administration, Layouts): the list, and a layout written as JSON for a tracker,
# maybe a status and a project, and a scope, checked as it is saved (GkFields::Layouts.errors). Preview draws the
# sections for an issue the administrator names, without saving; issues suggests the issues of the layout's tracker
# (and status and project) for it. The designer with drag and drop comes later and writes the same JSON.
# A layout saved or removed is an event in records on the layout (who, when, before and after), with the reason of
# the place fields.layout when records is there.
# REST (.json): the same, for administrators only, as the pages. An OAuth token also needs the scope
# gk_fields_api_read to read and gk_fields_api_manage to change.
class GkFieldsLayoutsController < ApplicationController
  layout 'admin'
  self.main_menu = false
  menu_item :gk_fields_layouts
  # the preview draws custom fields as the issue page does (custom_field_name_tag, custom_field_value_tag)
  helper :custom_fields

  READS = %w[index show].freeze

  before_action :require_admin_or_scope
  # the layouts are a declared function and need gk_access's levels: off or without it the pages answer as if they
  # were not there
  before_action -> { render_404 unless GkFields.layouts? }
  before_action :find_layout, only: %i[show edit update destroy]
  accept_api_auth :index, :show, :create, :update, :destroy

  EXAMPLE = <<~JSON
    {
      "sections": [
        { "key": "basic", "title": { "sv": "Grund", "en": "Basic" }, "columns": 2,
          "fields": [ { "field": "status" }, { "field": "priority" }, { "field": "assigned_to" }, { "field": "due_date" } ] }
      ]
    }
  JSON

  def index
    @layouts = GkFieldsLayout.includes(:tracker, :status, :project).order(:tracker_id, :project_id, :status_id, :scope).to_a
    respond_to do |format|
      format.html
      format.api { render json: { api_version: 1, layouts: @layouts.map { |lay| GkFields::Api.layout(lay) } } }
    end
  end

  # REST only: one layout
  def show
    respond_to do |format|
      format.html { redirect_to edit_gk_fields_layout_path(@layout) }
      format.api { render json: { api_version: 1, layout: GkFields::Api.layout(@layout) } }
    end
  end

  def new
    @layout = GkFieldsLayout.new(scope: 'show', layout: EXAMPLE)
  end

  def create
    @layout = GkFieldsLayout.new(layout_params)
    keep_or_preview(:new)
  rescue GkFields::Layouts::BodyError => e
    render_api_errors(e.message)
  end

  def edit; end

  def update
    @before = snapshot(@layout)
    @layout.assign_attributes(layout_params)
    keep_or_preview(:edit)
  rescue GkFields::Layouts::BodyError => e
    render_api_errors(e.message)
  end

  # A layout is a setting of the issue page, not a record of work: it is removed, and what it was stays in the
  # layout's events in records
  def destroy
    before = snapshot(@layout)
    if @layout.destroy
      log_layout('gk_fields_layout_removed', before, {}, nil)
      return render_api_ok if api_request?

      flash[:notice] = l(:notice_successful_delete)
    elsif api_request?
      return render_validation_errors(@layout)
    end
    redirect_to gk_fields_layouts_path
  end

  ISSUES_LIMIT = 20

  # The issues a preview can use, as JSON for the form's list: visible issues of the tracker named, and of the status
  # and project when they are named, found by number or by a part of the subject
  def issues
    tracker_id = params[:tracker_id].to_i
    return render(json: []) if tracker_id <= 0

    scope = Issue.visible.where(tracker_id: tracker_id)
    scope = scope.where(status_id: params[:status_id].to_i) if params[:status_id].to_i.positive?
    scope = scope.where(project_id: params[:project_id].to_i) if params[:project_id].to_i.positive?
    term = params[:term].to_s.strip
    if (m = term.match(/\A#?(\d+)\z/))
      # a number: the issues whose number starts with it (as core's issue search), or whose subject has it
      scope = scope.where("CAST(#{Issue.table_name}.id AS CHAR(13)) LIKE ? OR LOWER(#{Issue.table_name}.subject) LIKE ?",
                          "#{m[1]}%", "%#{m[1]}%")
    elsif term.present?
      scope = scope.where("LOWER(#{Issue.table_name}.subject) LIKE ?", "%#{Issue.sanitize_sql_like(term.downcase)}%")
    end
    rows = scope.order(id: :desc).limit(ISSUES_LIMIT).includes(:tracker).map do |i|
      { id: i.id, label: "#{i.tracker.name} ##{i.id}: #{i.subject.to_s.truncate(60)}" }
    end
    render json: rows
  end

  private

  # The pages are an administrator's (core's require_admin). REST: an administrator, and a token also needs the read
  # or the manage scope (or :admin), so that a token can be narrowed to this API.
  def require_admin_or_scope
    return require_admin unless api_request?
    return false unless require_login

    scope = READS.include?(action_name) ? GkFields::ApiScope::READ : GkFields::ApiScope::MANAGE
    return true if GkFields::ApiScope.admin_allows?(User.current, scope)

    render_403
    false
  end

  def find_layout
    @layout = GkFieldsLayout.find_by(id: params[:id]) or render_404
  end

  # The form's gk_fields_layout; REST's { layout: { tracker_id, status_id, project_id, scope, layout } }, where the
  # layout itself may be the JSON as a text or as an object. A REST body without it is refused with core's 422.
  def layout_params
    raw = api_request? ? params[:layout] : params.require(:gk_fields_layout)
    raise GkFields::Layouts::BodyError, l(:error_gk_fields_api_layout_body) unless raw.is_a?(ActionController::Parameters)

    # REST's layout as an object is written as the JSON text the page keeps; never permitted as a scalar
    object = api_request? && raw[:layout].is_a?(ActionController::Parameters)
    p = raw.permit(*%i[tracker_id status_id project_id scope], *(object ? [] : [:layout]))
    p[:layout] = JSON.pretty_generate(raw[:layout].to_unsafe_h) if object
    %i[status_id project_id].each { |k| p[k] = nil if p.key?(k) && p[k].blank? }
    p
  end

  # Where the issue named for a preview is not where the layout applies: another tracker gives no preview (its
  # fields are not the layout's), another status or project is said but previewed
  def preview_mismatch(issue)
    return {} unless issue

    out = {}
    if @layout.tracker_id && issue.tracker_id != @layout.tracker_id
      out[:tracker] = l(:text_gk_fields_layout_preview_other_tracker, issue: "##{issue.id}", tracker: issue.tracker&.name.to_s,
                                                                      layout: @layout.tracker&.name.to_s)
    end
    if @layout.status_id && issue.status_id != @layout.status_id
      out[:status] = l(:text_gk_fields_layout_preview_other_status, issue: "##{issue.id}", status: issue.status&.name.to_s,
                                                                    status_layout: @layout.status&.name.to_s)
    end
    if @layout.project_id && issue.project_id != @layout.project_id
      out[:project] = l(:text_gk_fields_layout_preview_other_project, issue: "##{issue.id}", project: issue.project&.name.to_s,
                                                                      project_layout: @layout.project&.name.to_s)
    end
    out
  end

  # Save, or with Preview show the sections for the issue named (nothing is saved). The reason of the place
  # fields.layout in gk_records is asked for as the layout is saved, never for a preview. REST saves only (no preview).
  def keep_or_preview(form)
    @layout.updated_by_id = User.current.id
    if params[:preview].present? && !api_request?
      @layout.valid?
      @preview_issue = Issue.visible.find_by(id: params[:preview_issue_id].to_s[/\d+/].to_i)
      @preview_mismatch = preview_mismatch(@preview_issue)
      if @preview_issue && @preview_mismatch[:tracker].nil? && @layout.errors.empty?
        @preview_sections = GkFields::Layouts.sections_for(@preview_issue, User.current, layout: @layout.data)
      end
      return render(form)
    end
    check = defined?(::GkRecords::Reasons) ? ::GkRecords::Reasons.check('fields.layout', params[:reason]) : nil
    if check && !check.ok
      return render_api_errors(check.error) if api_request?

      @layout.valid?
      @layout.errors.add(:base, check.error)
      return render(form)
    end
    if @layout.save
      log_layout(@before ? 'changed' : 'created', @before || {}, snapshot(@layout), check&.text)
      if api_request?
        return render(json: { api_version: 1, layout: GkFields::Api.layout(@layout) }, status: (@before ? :ok : :created))
      end

      flash[:notice] = l(@before ? :notice_successful_update : :notice_successful_create)
      redirect_to gk_fields_layouts_path
    elsif api_request?
      render_validation_errors(@layout)
    else
      render form
    end
  end

  # What an event says about a layout: where it applies, and its JSON
  def snapshot(layout) = { 'place' => layout.place_text, 'layout' => layout.layout.to_s }

  # The layout's event in records: what changed, before and after, and the reason; nothing when records is not there,
  # and nothing for a layout saved as it was (no change, as with the other things the plugin keeps; a reason given
  # with it is not kept either)
  def log_layout(kind, before, after, reason)
    return unless defined?(::GkRecords::Events) && ::GkRecords::Targets.find('gk_fields_layout')

    details = (before.keys | after.keys).each_with_object({}) do |k, h|
      h[k] = [before[k], after[k]] if before[k].to_s != after[k].to_s
    end
    return if kind == 'changed' && details.empty?

    ::GkRecords::Events.write(@layout, kind, details: details, reason: reason, user: User.current, reason_key: 'fields.layout')
  rescue StandardError => e
    Rails.logger.warn("[gk_fields] layout event not written: #{e.class} #{e.message}")
  end
end
