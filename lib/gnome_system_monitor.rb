# frozen_string_literal: true

require_relative "gnome_system_monitor/paths"

GnomeSystemMonitor::Paths.install_schemas!

require_relative "gnome_system_monitor/application"
