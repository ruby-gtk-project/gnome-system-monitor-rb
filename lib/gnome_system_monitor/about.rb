# frozen_string_literal: true

require "adwaita"

require_relative "i18n"
require_relative "paths"

module GnomeSystemMonitor
  # The about dialog, with upstream's credits.
  class About
    include Translations

    DEVELOPERS = [
      "Kevin Vandersloot",
      "Erik Johnsson",
      "Benoît Dejean",
      "Paolo Borelli",
      "Karl Lattimer",
      "Chris Kühl",
      "Robert Roth",
      "Stefano Facchini",
    ].freeze

    ARTISTS = ["Baptiste Mille-Mathias", "Jakub Steiner"].freeze

    def present(parent)
      dialog.present(parent)
    end

    def dialog
      @dialog ||= Adwaita::AboutDialog.new.tap do |d|
        d.application_name = _("System Monitor")
        d.application_icon = APPLICATION_ID
        d.version = VERSION
        d.developers = DEVELOPERS
        d.artists = ARTISTS
        d.copyright = "© 2001-2025 The GNOME Project"
        d.license_type = Gtk::License::GPL_2_0
        d.website = "https://apps.gnome.org/SystemMonitor/"
        d.issue_url = "https://gitlab.gnome.org/GNOME/gnome-system-monitor/-/issues"
        d.comments = _("View and manage system resources")
        # TRANSLATORS: eg. 'Translator Name <you@example.com>' or a website.
        d.translator_credits = _("translator-credits")
      end
    end
  end

  # The keyboard shortcuts window.
  #
  # Built from upstream's data/shortcuts-dialog.ui through GtkBuilder, as the
  # Ruby bindings cannot construct a GtkShortcutsWindow directly — the
  # generated constructor resolves to GtkWindow's and raises.
  class ShortcutsDialog
    def present(parent)
      window.tap do |win|
        win.transient_for = parent
        win.present
      end
    end

    def builder
      @builder ||= Gtk::Builder.new.tap do |b|
        b.translation_domain = "gnome-system-monitor"
        b.add_from_file(Paths.shortcuts_dialog_ui)
      end
    end

    def window = @window ||= builder.objects.find { |object| object.is_a?(Gtk::Window) }
  end
end
