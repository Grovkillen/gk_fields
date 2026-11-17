# frozen_string_literal: true

module GkFields
  # The gate to GK GUI Stuff, which fields requires (IDENTITY.yml, gk_gui_stuff). It is open when GK GUI Stuff answers
  # the gate's questions, its base version (the version without a candidate's suffix) is the lowest one fields needs or
  # later, and its own gate is open; candidates of one base version are not told apart.
  #
  # A gate closes only the interface, never a protection. Closed, the gate closes what a person works with: the pages
  # (core's 404), the menu items, the REST API, what fields draws on other pages (the Texts button and its pencils,
  # the link beside a name in the administration, the layouts' sections, the translated names and the corrected
  # Redmine texts, the field format Date and time), the view hooks, the core patches that draw or translate
  # (Patches.apply!) and what fields registers in other plugins in order to draw (records' reason places, GK GUI
  # Stuff's menu row and personal row, the appearances). Other plugins that ask fields about texts are answered as if
  # it were not there (Translations). It never closes:
  # * the three functions declared in gk_records (init.rb): records answers off for a function that is not declared,
  #   and what a layout's level hides hangs on the function Layouts;
  # * what a layout's level hides (Layouts.hidden_keys, the core patch Layouts::ShowPatch set by Patches.protect!, and
  #   the form's view): a section can not be drawn without GK GUI Stuff, but hiding needs no drawing. Core draws the
  #   issue page and the form, and the fields of a section above the person's ceiling are left out, as long as
  #   gk_access is there and the function Layouts is on;
  # * the levels a stored layout names, registered as in use in gk_access (Layouts.register_levels!, init.rb), so that
  #   no level a layout needs is removed there meanwhile;
  # * the permissions (the five on the texts and the two OAuth scopes): init.rb registers them whatever the gate says.
  #   Core's role form lists only the permissions that are registered and Role#permissions= writes the whole list, so
  #   a role saved while they were away would lose them. With the gate closed they open nothing: the controllers
  #   answer 404.
  # The settings page says the first thing that is not met (missing, too old, or installed but not active) in one line
  # of core's own form (<p class="warning">) before the About box, and that protection and traces hold all the same;
  # the migrations run all the same, so the stored layouts, texts and settings stand untouched until GK GUI Stuff
  # comes in. The extension files are always loaded, so another plugin that asks defined?(::GkFields::X) finds fields'
  # API.
  #
  # Fields loads before gk_gui_stuff (Redmine loads the plugins in the order of their directories' names), so init.rb
  # cannot ask the gate: what the gate opens starts at the end of each preparation (Gate.start!), and the menus, the
  # controllers and the listeners ask at each request.

  # The lowest base version the gate opens for; IDENTITY.yml requires the same base and a test holds the two together
  GUI_STUFF_MIN = '1.05.000'

  #   GkFields.gui_closed -> nil when the gate is open; otherwise the first thing that is not met: :missing (no GK GUI
  #   Stuff), :old (it does not answer open?, or its base version is older than GUI_STUFF_MIN) or :inactive (its own
  #   gate is closed)
  def self.gui_closed
    return :missing unless defined?(::GkGuiStuff)
    return :old unless ::GkGuiStuff.respond_to?(:open?) && ::GkGuiStuff.respond_to?(:version_at_least?) &&
                       ::GkGuiStuff.version_at_least?(GUI_STUFF_MIN)
    return :inactive unless ::GkGuiStuff.open?

    nil
  rescue StandardError
    :missing
  end

  #   GkFields.gui? -> true when gui_closed has nothing to say
  def self.gui? = gui_closed.nil?

  module Gate
    # The hook methods a view or controller listener answers (view_*, controller_*, model_*). Redmine asks a listener
    # respond_to?(hook) once and keeps the answer (Redmine::Hook.hook_listeners), so a closed gate keeps every hook of
    # fields' listeners silent. A listener is registered as soon as its class is defined (Listener.inherited), so the
    # gate is in the listener and not in init.rb.
    HOOK = /\A(view|controller|model)_/

    module Listener
      def respond_to?(name, include_all = false)
        return false if HOOK.match?(name.to_s) && !GkFields.gui?

        super
      end
    end

    # Every fields controller (the pages and the REST API) is closed without GK GUI Stuff: core's 404. A plain
    # before_action, after the ones ApplicationController has (the session, the user, the language), so that the 404 is
    # drawn for the person and in the language of the request; before the controller's own (require_login and the like)
    module Controller
      def self.included(base)
        base.before_action :gk_fields_gate
      end

      private

      def gk_fields_gate
        render_404 unless GkFields.gui?
      end
    end

    module_function

    # Fields at work, once GK GUI Stuff is known: fields loads before gk_gui_stuff (Redmine loads the plugins in the
    # order of their directories' names), so its init.rb cannot ask the gate. Boot below calls this at the end of every
    # preparation, the first and each reload in development, when every plugin's init.rb has run. Closed: nothing.
    # Open: the core patches (each guarded against a second one), the readers of the plugins' own models registered
    # before the gate was known and the field format Date and time (each only once). The permissions and the
    # protection do not wait for this: init.rb sets them whatever the gate says. Returns whether the gate is open.
    def start!
      return false unless GkFields.gui?

      Patches.apply!
      Translations.install_registered_readers!
      DateTime.register_format!
      true
    end

    # Core's hook at the end of each preparation (Redmine::PluginLoader, after every plugin's init.rb); not a view hook,
    # so the listener's gate above leaves it alone. The protection first, before the gate is asked: init.rb has set it
    # already, and this is its second try should that one have failed (the prepend is guarded against a second one)
    class Boot < ::Redmine::Hook::Listener
      def after_plugins_loaded(_context = {})
        Patches.protect!
        Gate.start!
      end
    end
  end
end
