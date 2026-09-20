# frozen_string_literal: true

# Drives the main window: every tab, the search bar, the selection-driven
# action bar, and each of the dialogs the process menu opens.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "tmpdir"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir

# dconf cannot write inside the scratch config directory, and a write it
# cannot persist is silently rolled back — which makes every "was it
# remembered?" check fail for the wrong reason. The memory backend keeps the
# settings real for the length of the run without touching the user's.
ENV["GSETTINGS_BACKEND"] = "memory"

require "gnome_system_monitor"
require_relative "gtk_driver"

# NON_UNIQUE so the test drives its own instance instead of handing over to a
# System Monitor already running on the session bus.
GtkDriver.drive(
  GnomeSystemMonitor::Application.new(flags: Gio::ApplicationFlags::NON_UNIQUE),
  shots: "tmp/shots",
) do |d, app|
  window = -> { app.window }

  d.window { app.window.window }

  # The first frame is not rendered until the window has been through the
  # loop a couple of times; shooting before that gets no render node at all.
  d.step("let the window realise") { nil }
  d.step("and settle") { nil }

  d.step("the window builds") do
    d.check("three pages") { window.call.stack.pages.n_items == 3 }
    d.check("processes loaded") { window.call.table.processes.size > 10 }
    d.check("the action bar is hidden with nothing selected") do
      !window.call.action_bar_revealer.reveal_child?
    end
    d.shot("01-resources")
  end

  d.step("the graphs sample") do
    window.call.resources_view.update
    window.call.resources_view.update
  end

  d.step("let the graphs render") { nil }

  d.step("the resources tab fills in") do
    d.check("the memory label is populated") do
      window.call.resources_view.memory_label.label.include?("%")
    end
    d.check("a CPU label is populated") do
      window.call.resources_view.cpu_value_labels.first.label.end_with?("%")
    end
    d.shot("02-resources-live")
  end

  d.step("switch to Processes") do
    window.call.stack.visible_child_name = "processes"
  end

  d.step("the process table renders") do
    d.check("the tab was remembered") do
      GnomeSystemMonitor::Settings[GnomeSystemMonitor::Settings::CURRENT_TAB] == "processes"
    end
    d.check("rows are showing") { window.call.process_view.selection.n_items > 10 }
    d.check("the CPU header carries a total") do
      window.call.process_view.column_widget(GnomeSystemMonitor::Columns.find(:pcpu)).title.include?("%")
    end
    d.shot("03-processes")
  end

  # The cells are filled in when the view binds a row, and a row is only bound
  # once — so a value that changes in place only reaches the screen because
  # the refresh tells the model its rows changed. Reading the label back out
  # of the widget tree is not safe under these bindings, so this checks the
  # two halves that make it work: the rendered text lands on the row, and the
  # store announces it.
  d.step("watch the store for announcements") do
    @announcements = 0
    window.call.table.root_store.signal_connect("items-changed") { @announcements += 1 }
  end

  # All in one step: the refresh timer runs between steps and would put the
  # real CPU figure back before the next one looked.
  d.step("a value changes under a bound cell") do
    window.call.process_view.unwrap(window.call.process_view.selection.get_item(0)).then do |process|
      @before = process.pcpu_text
      process.pcpu = 42.5
      window.call.process_view.refresh_headers
      @after = process.pcpu_text
    end
  end

  d.step("the change reached the row and the model") do
    d.check("the row had a rendered value") { !@before.nil? && @before.end_with?("%") }
    d.check("the row now renders the new value") { @after == "42.5%" }
    d.check("the store announced the change") { @announcements.positive? }
  end

  d.step("search for this very process") do
    window.call.search_button.active = true
    window.call.search_entry.text = "ruby"
  end

  d.step("the search narrows the table") do
    d.check("the search bar is showing") { window.call.search_bar.search_mode_enabled? }
    d.check("fewer rows than before") do
      window.call.process_view.selection.n_items < window.call.table.processes.size
    end
    d.check("at least one match") { window.call.process_view.selection.n_items.positive? }
    d.shot("04-search")
  end

  d.step("clear the search") do
    window.call.search_entry.text = ""
    window.call.search_button.active = false
  end

  # This very process, so the memory maps and open files lists have something
  # in them — the row at position 0 is whatever sorts first, often a kernel
  # thread with neither.
  d.step("select this process") do
    (0...window.call.process_view.selection.n_items).find do |index|
      window.call.process_view.unwrap(window.call.process_view.selection.get_item(index)).pid == Process.pid
    end.then { |index| window.call.process_view.selection.select_item(index, true) }
  end

  d.step("selecting reveals the action bar") do
    d.check("one process selected") { window.call.process_view.selected.length == 1 }
    d.check("the action bar is revealed") { window.call.action_bar_revealer.reveal_child? }
    d.check("the properties action is enabled") do
      window.call.simple_actions["process-properties"].enabled?
    end
    d.shot("05-selection")
  end

  d.step("open the process properties") do
    window.call.simple_actions["process-properties"].activate(nil)
  end

  d.step("let the properties window realise") { nil }

  d.step("the properties window shows real values") do
    d.check("a properties window opened") { window.call.detail_windows.length == 1 }
    d.check("the PID row is filled in") do
      window.call.detail_windows.first.rows[:pid].last.label.match?(/\A\d+\z/)
    end
    d.shot("06-properties", window.call.detail_windows.first.window)
  end

  d.step("close the properties window") do
    window.call.detail_windows.first.window.close
  end

  d.step("open the memory maps") do
    window.call.simple_actions["memory-maps"].activate(nil)
  end

  d.step("let the maps window realise") { nil }

  d.step("the memory maps list is populated") do
    d.check("a maps window opened") { window.call.detail_windows.length == 1 }
    d.check("mappings were read") { window.call.detail_windows.first.store.n_items > 5 }
    d.check("mappings reach the view") { window.call.detail_windows.first.selection.n_items > 5 }
    d.shot("07-memory-maps", window.call.detail_windows.first.window)
    window.call.detail_windows.first.window.close
  end

  d.step("open the open files list") do
    window.call.simple_actions["open-files"].activate(nil)
  end

  d.step("let the files window realise") { nil }

  d.step("the open files list is populated") do
    d.check("a files window opened") { window.call.detail_windows.length == 1 }
    d.check("descriptors were read") { window.call.detail_windows.first.store.n_items.positive? }
    d.shot("08-open-files", window.call.detail_windows.first.window)
    window.call.detail_windows.first.window.close
  end

  d.step("show dependencies") do
    GnomeSystemMonitor::Settings[GnomeSystemMonitor::Settings::SHOW_DEPENDENCIES] = true
  end

  d.step("let the tree settle") { nil }

  d.step("the tree has fewer roots than processes") do
    d.check("some processes have parents") do
      window.call.table.root_store.n_items < window.call.table.processes.size
    end
    d.shot("09-dependencies")
    GnomeSystemMonitor::Settings[GnomeSystemMonitor::Settings::SHOW_DEPENDENCIES] = false
  end

  d.step("switch to File Systems") do
    window.call.stack.visible_child_name = "disks"
  end

  d.step("the file systems tab lists mounts") do
    d.check("mounts found") { window.call.disks_view.store.n_items.positive? }
    d.shot("10-disks")
  end

  d.step("open Preferences") do
    window.call.open_preferences
  end

  d.step("the preferences dialog has three pages") do
    d.check("a dialog is showing") { !window.call.window.visible_dialog.nil? }
    d.check("the resources page is titled") { window.call.preferences.resources_page.title == "Resources" }
    d.check("every process column has a switch") do
      window.call.preferences.process_fields_group.then do |group|
        GnomeSystemMonitor::Columns.visible.all? do |column|
          !window.call.preferences.process_field_row(column).nil?
        end && !group.nil?
      end
    end
    d.shot("11-preferences")
    window.call.window.visible_dialog&.close
  end

  d.step("switch back to Processes for a final shot") do
    window.call.stack.visible_child_name = "processes"
  end

  d.step("the process table is still live") do
    d.check("rows still showing") { window.call.process_view.selection.n_items > 10 }
    d.shot("12-processes-final")
  end
end
