# frozen_string_literal: true

require "gio2"

require_relative "paths"

module GnomeSystemMonitor
  # The app's GSettings, schema and all, exactly as upstream declares them —
  # data/org.gnome.gnome-system-monitor.gschema.xml is upstream's file with
  # only the gettext domain filled in. Sharing the schema means a port and a C
  # build read and write the same configuration.
  module Settings
    UPDATE_INTERVAL = "update-interval"
    GRAPH_UPDATE_INTERVAL = "graph-update-interval"
    DISKS_INTERVAL = "disks-interval"
    GRAPH_DATA_POINTS = "graph-data-points"
    SHOW_DEPENDENCIES = "show-dependencies"
    SHOW_WHOSE_PROCESSES = "show-whose-processes"
    SHOW_ALL_FS = "show-all-fs"
    SOLARIS_MODE = "solaris-mode"
    PROCESS_MEMORY_IN_IEC = "process-memory-in-iec"
    RESOURCES_MEMORY_IN_IEC = "resources-memory-in-iec"
    SMOOTH_REFRESH = "smooth-refresh"
    KILL_DIALOG = "kill-dialog"
    NETWORK_IN_BITS = "network-in-bits"
    NETWORK_TOTAL_IN_BITS = "network-total-in-bits"
    LOGARITHMIC_SCALE = "logarithmic-scale"
    CPU_STACKED_AREA_CHART = "cpu-stacked-area-chart"
    CPU_SMOOTH_GRAPH = "cpu-smooth-graph"
    CURRENT_TAB = "current-tab"
    WINDOW_WIDTH = "window-width"
    WINDOW_HEIGHT = "window-height"
    MAXIMIZED = "maximized"

    PROCTREE = "proctree"
    DISKSVIEW = "disksview"

    module_function

    def settings = @settings ||= Gio::Settings.new(SCHEMA_ID)

    def proctree = @proctree ||= settings.get_child(PROCTREE)

    def disksview = @disksview ||= settings.get_child(DISKSVIEW)

    # These bindings unwrap a GVariant on the way out and wrap it on the way
    # in, so a setting reads and writes as the plain Ruby value.
    def [](key) = settings.get_value(key)

    def []=(key, value)
      settings.set_value(key, value)
    end

    # The two intervals are stored in milliseconds and wanted in seconds
    # everywhere they are used.
    def update_interval = settings.get_int(UPDATE_INTERVAL) / 1000.0

    def graph_update_interval = settings.get_int(GRAPH_UPDATE_INTERVAL) / 1000.0

    def disks_interval = settings.get_int(DISKS_INTERVAL) / 1000.0

    # 100% per CPU, or 100% across the machine when Solaris mode is on.
    def cpu_scale(cpu_count)
      if settings.get_boolean(SOLARIS_MODE)
        100
      else
        100 * cpu_count
      end
    end

    # proctree keeps one width and one visibility flag per column index; the
    # index is the column's position in Columns::DEFINITIONS.
    def column_visible?(index) = proctree.get_boolean("col-#{index}-visible")

    def set_column_visible(index, visible)
      proctree.set_boolean("col-#{index}-visible", visible)
    end

    def column_width(index) = proctree.get_int("col-#{index}-width")

    def set_column_width(index, width)
      proctree.set_int("col-#{index}-width", width)
    end

    def columns_order = proctree.get_value("columns-order")

    def set_columns_order(order)
      proctree.set_value("columns-order", order)
    end

    def sort_column = proctree.get_int("sort-col")

    def sort_order = proctree.get_int("sort-order")

    def set_sort(column, order)
      proctree.set_int("sort-col", column)
      proctree.set_int("sort-order", order)
    end

    # The disks view names its column keys after the column id rather than
    # numbering them, which is how upstream's disksview schema is written.
    def disks_column_visible?(id) = disksview.get_boolean("col-#{id}-visible")

    def set_disks_column_visible(id, visible)
      disksview.set_boolean("col-#{id}-visible", visible)
    end

    def disks_column_width(id) = disksview.get_int("col-#{id}-width")

    def set_disks_column_width(id, width)
      disksview.set_int("col-#{id}-width", width)
    end
  end
end
