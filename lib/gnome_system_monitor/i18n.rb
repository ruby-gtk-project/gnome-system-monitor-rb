# frozen_string_literal: true

require "gettext"

require_relative "paths"

module GnomeSystemMonitor
  # Upstream's gettext domain is the project name, and the catalogues are the
  # ones in po/ — so the same translations serve the port unchanged.
  module Translations
    include GetText

    bindtextdomain("gnome-system-monitor", path: Paths.locale_dir)
  end
end
