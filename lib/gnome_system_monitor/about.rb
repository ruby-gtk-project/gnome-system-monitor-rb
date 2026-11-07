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

  # The keyboard shortcuts dialog.
  #
  # Built from upstream's data/shortcuts-dialog.ui through GtkBuilder.
  # Upstream's root object there is an `AdwShortcutsDialog`, which is an
  # `Adwaita::Dialog` (shown with `present(parent)`, the same as
  # `AlertDialog`/`AboutDialog`), not a `GtkWindow` — the builder's objects
  # have to be searched for an `Adwaita::Dialog`, not a `Gtk::Window`, or the
  # search comes back empty and `present` raises on a `nil` dialog.
  class ShortcutsDialog
    def present(parent) = dialog.present(parent)

    def builder
      @builder ||= Gtk::Builder.new.tap do |b|
        b.translation_domain = "gnome-system-monitor"
        b.add_from_file(Paths.shortcuts_dialog_ui)
      end
    end

    def dialog = @dialog ||= builder.objects.find { |object| object.is_a?(Adwaita::Dialog) }
  end
end
