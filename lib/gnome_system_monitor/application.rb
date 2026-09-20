# frozen_string_literal: true

require "adwaita"

require_relative "about"
require_relative "detail_windows"
require_relative "i18n"
require_relative "paths"
require_relative "window"

module GnomeSystemMonitor
  # application.cpp: one window, the application-wide actions behind the
  # primary menu, and the style and icon setup the window needs before it is
  # built.
  class Application
    include Translations

    HELP_URI = "help:gnome-system-monitor"

    # The application id is the D-Bus name, so a second launch hands over to
    # the instance that already owns it — which is what makes System Monitor a
    # single-window app. Tests pass NON_UNIQUE so they drive their own
    # instance rather than waking whatever is already running on the session
    # bus.
    def initialize(flags: Gio::ApplicationFlags::DEFAULT_FLAGS)
      @flags = flags
    end

    attr_reader :flags

    def build
      application.tap do |app|
        app.signal_connect("startup") { on_startup }
        app.signal_connect("activate") { on_activate }

        app.add_action(preferences_action)
        app.add_action(lsof_action)
        app.add_action(help_action)
        app.add_action(quit_action)

        preferences_action.signal_connect("activate") { window.open_preferences }
        lsof_action.signal_connect("activate") { window.open_search_open_files }
        help_action.signal_connect("activate") { open_help }
        quit_action.signal_connect("activate") { app.quit }

        app.set_accels_for_action("app.quit", ["<Control>Q"])
        app.set_accels_for_action("app.help", ["F1"])
        app.set_accels_for_action("window.close", ["<Control>W"])
      end
    end

    def run(argv) = application.run(argv)

    def application
      @application ||= Gtk::Application.new(APPLICATION_ID, flags)
    end

    def on_startup
      load_style
      register_icons
    end

    def on_activate
      window.build
      window.present
    end

    def window = @window ||= Window.new(application: self)

    def set_accels_for_action(name, accelerators)
      application.set_accels_for_action(name, accelerators)
    end

    def open_about(parent)
      About.new.present(parent)
    end

    def open_shortcuts(parent)
      ShortcutsDialog.new.present(parent)
    end

    def open_help
      Gtk::UriLauncher.new(HELP_URI).launch(application.active_window, nil) do |_launcher, _result|
        nil
      end
    rescue StandardError => e
      warn("Could not open the help: #{e.message}")
    end

    def load_style
      Gtk::CssProvider.new.tap do |provider|
        provider.load_from_path(Paths.style_css)
        Gtk::StyleContext.add_provider_for_display(
          Gdk::Display.default,
          provider,
          Gtk::StyleProvider::PRIORITY_APPLICATION,
        )
      end
    rescue StandardError => e
      warn("Could not load #{Paths.style_css}: #{e.message}")
    end

    # Running from a checkout there is no installed icon theme, so point the
    # theme at the one in data/ — that is where the two view-switcher icons
    # live as well as the app icon.
    def register_icons
      Gtk::IconTheme.get_for_display(Gdk::Display.default).add_search_path(Paths.icons_dir)
    end

    def preferences_action = @preferences_action ||= Gio::SimpleAction.new("preferences")
    def lsof_action = @lsof_action ||= Gio::SimpleAction.new("lsof")
    def help_action = @help_action ||= Gio::SimpleAction.new("help")
    def quit_action = @quit_action ||= Gio::SimpleAction.new("quit")
  end
end
