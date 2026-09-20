# frozen_string_literal: true

require "adwaita"

require_relative "columns"
require_relative "i18n"
require_relative "settings"

module GnomeSystemMonitor
  # preferences.ui: three pages of switches bound straight to GSettings, plus
  # the two "Information Fields" groups that turn the table columns on and
  # off.
  class Preferences
    include Translations

    # The update intervals are stored in milliseconds and edited in seconds,
    # over the ranges prefsdialog.cpp allows.
    INTERVAL_RANGES = {
      Settings::UPDATE_INTERVAL       => [1.0, 100.0, 0.25],
      Settings::GRAPH_UPDATE_INTERVAL => [0.25, 100.0, 0.25],
      Settings::DISKS_INTERVAL        => [1.0, 100.0, 1.0],
    }.freeze

    GRAPH_DATA_POINTS_RANGE = [30, 600].freeze

    def initialize(disks_view:, process_view:, on_change:)
      @disks_view = disks_view
      @process_view = process_view
      @on_change = on_change
    end

    attr_reader :disks_view, :process_view, :on_change

    def build
      dialog.tap do |d|
        d.add(resources_page)
        d.add(processes_page)
        d.add(disks_page)

        build_resources_page
        build_processes_page
        build_disks_page
      end
    end

    def present(parent)
      build
      dialog.present(parent)
    end

    def dialog
      @dialog ||= Adwaita::PreferencesDialog.new.tap do |d|
        d.title = _("Preferences")
      end
    end

    # Resources
    def resources_page
      @resources_page ||= Adwaita::PreferencesPage.new.tap do |page|
        page.title = _("Resources")
      end
    end

    def build_resources_page
      resources_page.tap do |page|
        page.add(
          behavior_group(_("Behavior")) do |group|
                    group.add(interval_row(_("_Update Interval in Seconds"), Settings::GRAPH_UPDATE_INTERVAL))
                    group.add(data_points_row)
                    group.add(switch_row(_("Draw Charts as S_mooth Graphs"), Settings::CPU_SMOOTH_GRAPH))
                  end,
        )

        page.add(
          behavior_group(_("CPU")) do |group|
                    group.add(switch_row(_("_Draw CPU Chart as Stacked Area Chart"), Settings::CPU_STACKED_AREA_CHART))
                  end,
        )

        page.add(
          behavior_group(_("Memory and Swap")) do |group|
                    group.add(switch_row(_("Show Memory and Swap in IEC"), Settings::RESOURCES_MEMORY_IN_IEC))
                    group.add(switch_row(_("Show Memory in Logarithmic Scale"), Settings::LOGARITHMIC_SCALE))
                  end,
        )

        page.add(
          behavior_group(_("Network")) do |group|
                    group.add(switch_row(_("_Show Network Speed in Bits"), Settings::NETWORK_IN_BITS))
                    group.add(switch_row(_("Show Network _Totals in Bits"), Settings::NETWORK_TOTAL_IN_BITS))
                  end,
        )
      end
    end

    # Processes
    def processes_page
      @processes_page ||= Adwaita::PreferencesPage.new.tap do |page|
        page.title = _("Processes")
      end
    end

    def build_processes_page
      processes_page.tap do |page|
        page.add(
          behavior_group(_("Behavior")) do |group|
                    group.add(interval_row(_("_Update Interval in Seconds"), Settings::UPDATE_INTERVAL))
                    group.add(switch_row(_("Enable _Smooth Refresh"), Settings::SMOOTH_REFRESH))
                    group.add(switch_row(_("Alert Before Ending or _Force Stopping Processes"), Settings::KILL_DIALOG))
                    group.add(switch_row(_("_Divide CPU Usage by CPU Count"), Settings::SOLARIS_MODE))
                    group.add(switch_row(_("Show Memory in IEC"), Settings::PROCESS_MEMORY_IN_IEC))
                  end,
        )

        page.add(process_fields_group)
      end
    end

    # The Information Fields group: one switch per column, writing the same
    # gschema keys the table reads its visibility from.
    def process_fields_group
      @process_fields_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Information Fields")

        Columns.visible.each do |column|
          group.add(process_field_row(column))
        end
      end
    end

    def process_field_row(column)
      Adwaita::SwitchRow.new.tap do |row|
        row.title = column.title.call
        row.active = Settings.column_visible?(column.index)

        row.signal_connect("notify::active") do
          Settings.set_column_visible(column.index, row.active?)
          process_view.column_widget(column).visible = row.active?
        end
      end
    end

    # File Systems
    def disks_page
      @disks_page ||= Adwaita::PreferencesPage.new.tap do |page|
        page.title = _("File Systems")
      end
    end

    def build_disks_page
      disks_page.tap do |page|
        page.add(
          behavior_group(_("Behavior")) do |group|
                    group.add(interval_row(_("_Update Interval in Seconds"), Settings::DISKS_INTERVAL))
                    group.add(switch_row(_("Show _All File Systems"), Settings::SHOW_ALL_FS))
                  end,
        )

        page.add(disks_fields_group)
      end
    end

    def disks_fields_group
      @disks_fields_group ||= Adwaita::PreferencesGroup.new.tap do |group|
        group.title = _("Information Fields")

        disks_view.columns.each do |column|
          group.add(disks_field_row(column))
        end
      end
    end

    def disks_field_row(column)
      Adwaita::SwitchRow.new.tap do |row|
        row.title = column.title
        row.active = Settings.disks_column_visible?(column.id)

        row.signal_connect("notify::active") do
          Settings.set_disks_column_visible(column.id, row.active?)
          disks_view.column_widget(column).visible = row.active?
        end
      end
    end

    # Rows
    def behavior_group(title)
      Adwaita::PreferencesGroup.new.tap do |group|
        group.title = title
        yield(group)
      end
    end

    def switch_row(title, key)
      Adwaita::SwitchRow.new.tap do |row|
        row.title = title
        row.use_underline = true
        Settings.settings.bind(
          key,
          row,
          "active",
          Gio::SettingsBindFlags::DEFAULT,
        )
        row.signal_connect("notify::active") { on_change.call }
      end
    end

    def interval_row(title, key)
      INTERVAL_RANGES.fetch(key).then do |(minimum, maximum, step)|
        Adwaita::SpinRow.new(
          Gtk::Adjustment.new(
            1,
            minimum,
            maximum,
            step,
            step,
            0,
          ),
          step,
          2,
        ).tap do |row|
          row.title = title
          row.use_underline = true
          row.value = Settings.settings.get_int(key) / 1000.0

          row.signal_connect("notify::value") do
            Settings.settings.set_int(key, (row.value * 1000).to_i)
            on_change.call
          end
        end
      end
    end

    def data_points_row
      @data_points_row ||= Adwaita::ActionRow.new.tap do |row|
        row.title = _("_Chart Data Points")
        row.use_underline = true
        row.add_suffix(data_points_scale)
      end
    end

    def data_points_scale
      @data_points_scale ||= Gtk::Scale.new(:horizontal, data_points_adjustment).tap do |scale|
        scale.digits = 0
        scale.draw_value = true
        scale.value_pos = :right
        scale.width_request = 200
        scale.valign = :center

        scale.signal_connect("value-changed") do
          Settings[Settings::GRAPH_DATA_POINTS] = scale.value.to_i
          on_change.call
        end
      end
    end

    def data_points_adjustment
      @data_points_adjustment ||= Gtk::Adjustment.new(
        Settings[Settings::GRAPH_DATA_POINTS],
        GRAPH_DATA_POINTS_RANGE.first,
        GRAPH_DATA_POINTS_RANGE.last,
        10,
        10,
        0,
      )
    end
  end
end
