# frozen_string_literal: true

module GnomeSystemMonitor
  APPLICATION_ID = "org.gnome.SystemMonitor"
  SCHEMA_ID = "org.gnome.gnome-system-monitor"
  RESOURCE_PATH = "/org/gnome/gnome-system-monitor"
  VERSION = "51"

  # Where the gschema, the CSS, the icons and the shortcuts UI live. Upstream
  # bundles all of this into a GResource; a Ruby checkout has no build step to
  # bake one, so the files are read from data/ next to lib/ instead.
  module Paths
    module_function

    def data_dir = File.expand_path("../../data", __dir__)

    # Where the privileged helpers live — the same directory the polkit
    # policy names.
    def bin_dir = File.expand_path("../../bin", __dir__)

    def style_css = File.join(data_dir, "style.css")

    def shortcuts_dialog_ui = File.join(data_dir, "shortcuts-dialog.ui")

    def icons_dir = File.join(data_dir, "icons")

    def locale_dir = File.join(data_dir, "locale")

    def po_dir = File.expand_path("../../po", __dir__)

    def schema_source = File.join(data_dir, "gnome-system-monitor.gschema.xml")

    # GSettings will not open a schema it cannot find on disk, and running
    # from a checkout there is no installed copy — so compile the source
    # schema in place the first time and point GSettings at it.
    def install_schemas!
      File.join(data_dir, "gschemas.compiled").then do |compiled|
        if !File.exist?(compiled) || File.mtime(schema_source) > File.mtime(compiled)
          compile_schemas!
        end
      end

      ENV["GSETTINGS_SCHEMA_DIR"] = [data_dir, ENV.fetch("GSETTINGS_SCHEMA_DIR", nil)].compact.join(":")
    end

    # An installed copy has its schema compiled already and its data directory
    # read-only, which is fine — only a checkout needs to build it.
    def compile_schemas!
      system(
        "glib-compile-schemas",
        "--strict",
        data_dir,
        exception: true,
      )
    rescue StandardError => e
      warn("Could not compile the GSettings schema in #{data_dir}: #{e.message}")
    end
  end
end
