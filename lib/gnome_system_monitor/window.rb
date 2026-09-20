# frozen_string_literal: true

require "adwaita"

require_relative "actions"
require_relative "detail_windows"
require_relative "dialogs"
require_relative "disks_view"
require_relative "i18n"
require_relative "preferences"
require_relative "process_properties"
require_relative "process_table"
require_relative "process_view"
require_relative "resources_view"
require_relative "settings"

module GnomeSystemMonitor
  # interface.cpp: the main window — a view switcher over Resources, Processes
  # and File Systems, the search bar, the primary menu, and the action bar
  # that appears when a process is selected.
  class Window
    include Translations

    # The window actions, and the accelerators the shortcuts window
    # advertises for them.
    ACCELERATORS = {
      "win.search"             => ["<Control>F"],
      "win.refresh"            => ["<Control>R"],
      "win.show-dependencies"  => ["<Control>D"],
      "win.process-properties" => ["<Alt>Return"],
      "win.memory-maps"        => ["<Control>M"],
      "win.open-files"         => ["<Control>O"],
      "win.set-affinity"       => ["<Alt>S"],
      "win.send-signal-stop"   => ["<Control>S"],
      "win.send-signal-cont"   => ["<Control>C"],
      "win.send-signal-term"   => ["<Control>T"],
      "win.send-signal-kill"   => ["<Control>K"],
      "win.shortcuts"          => ["<Control>question"],
      "win.about"              => [],
    }.freeze

    PAGES = %w[resources processes disks].freeze

    def initialize(application:)
      @application = application
      @detail_windows = []
    end

    attr_reader :application, :detail_windows

    def build
      window.tap do |win|
        win.title = _("System Monitor")
        win.icon_name = APPLICATION_ID
        win.content = toolbar_view

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.add_top_bar(search_bar)
          view.content = stack

          header_bar.tap do |bar|
            bar.title_widget = view_switcher
            bar.pack_start(search_button)
            bar.pack_end(menu_button)
          end

          search_bar.tap do |bar|
            bar.child = search_entry
            search_button.bind_property(
              "active",
              bar,
              "search-mode-enabled",
              GLib::BindingFlags::BIDIRECTIONAL,
            )

            search_entry.signal_connect("search-changed") do
              table.search_text = search_entry.text
            end
          end

          stack.tap do |s|
            add_page(
              s,
              resources_view.build,
              "resources",
              _("_Resources"),
              "resources-symbolic",
            )
            add_page(
              s,
              processes_page,
              "processes",
              _("_Processes"),
              "processes-symbolic",
            )
            add_page(
              s,
              disks_view.build,
              "disks",
              _("_File Systems"),
              "drive-harddisk-symbolic",
            )

            s.signal_connect("notify::visible-child-name") { on_page_changed }
          end

          processes_page.tap do |page|
            page.append(process_view.build)
            page.append(action_bar_revealer)

            action_bar_revealer.child = process_action_bar

            process_action_bar.tap do |bar|
              bar.pack_start(end_process_button)
              bar.pack_end(properties_button)
            end
          end

          view_switcher.stack = stack
        end

        install_actions
        restore_window_state
      end

      window
    end

    def present
      window.present
      start_timers
      refresh_processes
    end

    # Actions
    def install_actions
      simple_actions.each_value { |action| window.add_action(action) }
      window.add_action(dependencies_action)
      window.add_action(whose_processes_action)

      ACCELERATORS.each do |name, accelerators|
        if !accelerators.empty?
          application.set_accels_for_action(name, accelerators)
        end
      end
    end

    def simple_actions
      @simple_actions ||= {
        "search"             => toggle_action("search") { search_button.active = !search_button.active? },
        "refresh"            => action("refresh") { refresh_processes },
        "process-properties" => action("process-properties") { open_properties },
        "memory-maps"        => action("memory-maps") { open_detail(:memory_maps) },
        "open-files"         => action("open-files") { open_detail(:open_files) },
        "set-affinity"       => action("set-affinity") { open_affinity },
        "send-signal-stop"   => action("send-signal-stop") { confirm_and_signal(:stop) },
        "send-signal-cont"   => action("send-signal-cont") { send_signal(:cont) },
        "send-signal-term"   => action("send-signal-term") { confirm_and_signal(:term) },
        "send-signal-kill"   => action("send-signal-kill") { confirm_and_signal(:kill) },
        "priority"           => priority_action,
        "shortcuts"          => action("shortcuts") { application.open_shortcuts(window) },
        "about"              => action("about") { application.open_about(window) },
      }
    end

    def action(name, &block)
      Gio::SimpleAction.new(name).tap do |a|
        a.signal_connect("activate") { block.call }
      end
    end

    def toggle_action(name, &block) = action(name, &block)

    # The priority menu items carry the nice value as their target; 32 is
    # upstream's sentinel for "ask me", which opens the renice dialog.
    CUSTOM_PRIORITY = 32

    def priority_action
      Gio::SimpleAction.new("priority", GLib::VariantType.new("i")).tap do |a|
        a.signal_connect("activate") do |_action, parameter|
          if parameter.value == CUSTOM_PRIORITY
            open_renice
          else
            apply_priority(parameter.value)
          end
        end
      end
    end

    def dependencies_action
      @dependencies_action ||= Settings.settings.create_action(Settings::SHOW_DEPENDENCIES).tap do
        Settings.settings.signal_connect("changed::#{Settings::SHOW_DEPENDENCIES}") do
          refresh_processes
        end
      end
    end

    def whose_processes_action
      @whose_processes_action ||= Settings.settings.create_action(Settings::SHOW_WHOSE_PROCESSES).tap do
        Settings.settings.signal_connect("changed::#{Settings::SHOW_WHOSE_PROCESSES}") do
          refresh_processes
        end
      end
    end

    # Refreshing
    def start_timers
      @process_timer = GLib::Timeout.add((Settings.update_interval * 1000).to_i) do
        refresh_processes
        GLib::Source::CONTINUE
      end

      @graph_timer = GLib::Timeout.add((Settings.graph_update_interval * 1000).to_i) do
        resources_view.update
        GLib::Source::CONTINUE
      end

      @disks_timer = GLib::Timeout.add((Settings.disks_interval * 1000).to_i) do
        disks_view.refresh
        GLib::Source::CONTINUE
      end
    end

    # The intervals are settings, so changing one has to restart the timer it
    # drives rather than wait for the next tick of the old one.
    def restart_timers
      stop_timers
      start_timers
    end

    def stop_timers
      [@process_timer, @graph_timer, @disks_timer].compact.each { |id| GLib::Source.remove(id) }
      @process_timer = @graph_timer = @disks_timer = nil
    end

    def refresh_processes
      table.refresh
      process_view.refresh_headers
      update_action_state
      detail_windows.each(&:update)
    end

    def on_page_changed
      Settings[Settings::CURRENT_TAB] = stack.visible_child_name
      update_action_state
    end

    # Queued rather than run on the spot. Both callers are signals the model
    # emits while it is still rearranging itself — items-changed, and the
    # selection-changed that restoring a selection sets off — and reading the
    # selection from inside one of those can hand back a row that is already
    # gone.
    def update_action_state
      if !@action_state_queued
        @action_state_queued = true

        GLib::Idle.add do
          @action_state_queued = false
          apply_action_state
          GLib::Source::REMOVE
        end
      end
    end

    # The action bar slides in only when something is selected, and the
    # per-process actions are insensitive until then.
    def apply_action_state
      process_view.selected.then do |selected|
        action_bar_revealer.reveal_child = !selected.empty? && stack.visible_child_name == "processes"

        %w[
          process-properties memory-maps open-files set-affinity
          send-signal-stop send-signal-cont send-signal-term send-signal-kill priority
        ].each do |name|
          simple_actions[name].enabled = !selected.empty?
        end
      end
    end

    # Process operations
    def selected = process_view.selected

    def confirm_and_signal(signal)
      selected.then do |processes|
        if !processes.empty?
          Dialogs.confirm_signal(window, processes, signal) { send_signal(signal) }
        end
      end
    end

    def send_signal(signal)
      selected.each do |process|
        Actions.send_signal(process.pid, signal).then do |failure|
          if failure
            Dialogs.report(window, failure)
          end
        end
      end

      refresh_processes
    end

    def apply_priority(priority)
      selected.each do |process|
        Actions.set_priority(process.pid, priority).then do |failure|
          if failure
            Dialogs.report(window, failure)
          end
        end
      end

      refresh_processes
    end

    def open_renice
      selected.then do |processes|
        if !processes.empty?
          ReniceDialog.new(processes: processes, on_apply: ->(nice) { apply_priority(nice) })
                      .present(window)
        end
      end
    end

    def open_affinity
      selected.first.then do |process|
        if process
          AffinityDialog.new(
            process:   process,
            cpu_count: resources_view.cpu_count,
            on_apply:  ->(cpus, threads) { apply_affinity(process, cpus, threads) },
          ).present(window)
        end
      end
    end

    def apply_affinity(process, cpus, child_threads)
      Actions.set_affinity(process.pid, cpus, child_threads).then do |failure|
        if failure
          Dialogs.report(window, failure)
        end
      end
    end

    def open_properties
      selected.first.then do |process|
        if process
          ProcessProperties.new(
            process:   process,
            on_signal: ->(signal) { confirm_and_signal(signal) },
          ).tap do |properties|
            detail_windows << properties
            forget_on_close(properties, properties.window)
            properties.present(window)
          end
        end
      end
    end

    # One window per kind, pointed at whichever process is selected — as
    # upstream keeps one per process — rather than a fresh one each time.
    def open_detail(kind)
      selected.first.then do |process|
        if process
          detail_views[kind].tap do |view|
            if !detail_windows.include?(view)
              detail_windows << view
              forget_on_close(view, view.window)
            end

            view.present(window, process)
          end
        end
      end
    end

    def detail_views
      @detail_views ||= Hash.new { |views, kind| views[kind] = DetailWindows.send(kind) }
    end

    # A detail window stops being refreshed the moment it closes, rather than
    # being kept alive by the refresh list.
    def forget_on_close(view, detail)
      detail.signal_connect("close-request") do
        detail_windows.delete(view)
        false
      end
    end

    def open_search_open_files
      SearchOpenFiles.new.present(window)
    end

    def open_preferences
      preferences.present(window)
    end

    def preferences
      @preferences ||= Preferences.new(
        disks_view:   disks_view,
        process_view: process_view,
        on_change:    -> { on_preferences_changed },
      )
    end

    def on_preferences_changed
      resources_view.apply_settings
      restart_timers
      refresh_processes
      disks_view.refresh
    end

    # Window state
    def restore_window_state
      window.set_default_size(
        Settings.settings.get_int(Settings::WINDOW_WIDTH),
        Settings.settings.get_int(Settings::WINDOW_HEIGHT),
      )

      if Settings[Settings::MAXIMIZED]
        window.maximize
      end

      stack.visible_child_name = current_tab

      window.signal_connect("close-request") do
        save_window_state
        false
      end
    end

    # A tab name from a future version would leave the stack empty, so an
    # unknown one falls back to the first page.
    def current_tab
      Settings[Settings::CURRENT_TAB].then do |name|
        PAGES.include?(name) ? name : PAGES.first
      end
    end

    def save_window_state
      stop_timers

      if !window.maximized?
        Settings.settings.set_int(Settings::WINDOW_WIDTH, window.default_width)
        Settings.settings.set_int(Settings::WINDOW_HEIGHT, window.default_height)
      end

      Settings[Settings::MAXIMIZED] = window.maximized?
      process_view.save_sort
      process_view.save_column_widths
      disks_view.save_sort
      disks_view.save_column_widths
    end

    # Widgets
    def window
      @window ||= Adwaita::ApplicationWindow.new(application.application).tap do |win|
        win.add_css_class("view")
      end
    end

    def toolbar_view
      @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
        view.width_request = 620
        view.height_request = 480
      end
    end

    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def view_switcher
      @view_switcher ||= Adwaita::ViewSwitcher.new.tap do |switcher|
        switcher.policy = Adwaita::ViewSwitcherPolicy::WIDE
      end
    end

    def search_button
      @search_button ||= Gtk::ToggleButton.new.tap do |button|
        button.tooltip_text = _("Search")
        button.icon_name = "edit-find-symbolic"
      end
    end

    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.tooltip_text = _("Main Menu")
        button.icon_name = "open-menu-symbolic"
        button.primary = true
        button.menu_model = main_menu
      end
    end

    def search_bar = @search_bar ||= Gtk::SearchBar.new

    def search_entry
      @search_entry ||= Gtk::SearchEntry.new.tap do |entry|
        entry.placeholder_text = _("Search processes and users")
        entry.width_request = 300
      end
    end

    def stack
      @stack ||= Adwaita::ViewStack.new.tap do |s|
        s.hexpand = true
        s.vexpand = true
      end
    end

    def add_page(stack, child, name, title, icon_name)
      stack.add_titled(child, name, title).tap do |page|
        page.icon_name = icon_name
        page.use_underline = true
      end
    end

    def processes_page = @processes_page ||= Gtk::Box.new(:vertical, 0)

    def action_bar_revealer
      @action_bar_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_up
      end
    end

    def process_action_bar = @process_action_bar ||= Gtk::ActionBar.new

    def end_process_button
      @end_process_button ||= Gtk::Button.new(label: _("_End Process…")).tap do |button|
        button.use_underline = true
        button.halign = :start
        button.receives_default = true
        button.action_name = "win.send-signal-term"
        button.add_css_class("destructive-action")
      end
    end

    def properties_button
      @properties_button ||= Gtk::Button.new.tap do |button|
        button.tooltip_text = _("Process Properties")
        button.icon_name = "document-properties-symbolic"
        button.action_name = "win.process-properties"
      end
    end

    def table = @table ||= ProcessTable.new

    def resources_view = @resources_view ||= ResourcesView.new

    def disks_view = @disks_view ||= DisksView.new

    def process_view
      @process_view ||= ProcessView.new(
        table:                table,
        on_selection_changed: -> { update_action_state },
        on_context_menu:      ->(x, y) { show_context_menu(x, y) },
      )
    end

    # menus.ui's process-popup-menu, shown where the pointer is.
    def show_context_menu(x, y)
      context_menu.tap do |popover|
        popover.set_parent(process_view.column_view)
        popover.pointing_to = Gdk::Rectangle.new(
          x.to_i,
          y.to_i,
          1,
          1,
        )
        popover.popup
      end
    end

    def context_menu
      @context_menu ||= Gtk::PopoverMenu.new(:model, process_popup_menu).tap do |popover|
        popover.has_arrow = false
        popover.halign = :start
      end
    end

    def process_popup_menu
      @process_popup_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, section { |s| s.append(_("_Properties"), "win.process-properties") })

        menu.append_section(
          nil,
          section do |s|
                    s.append(_("_Memory Maps"), "win.memory-maps")
                    # Translators: this means 'Files that are open' (open is not a verb here)
                    s.append(_("_Open Files"), "win.open-files")
                  end,
        )

        menu.append_section(
          nil,
          section do |s|
                    s.append_submenu(_("_Change Priority"), priority_menu)
                  end,
        )

        menu.append_section(
          nil,
          section do |s|
                    s.append(_("_Pause…"), "win.send-signal-stop")
                    s.append(_("_Resume"), "win.send-signal-cont")
                  end,
        )

        menu.append_section(
          nil,
          section do |s|
                    s.append(_("_End…"), "win.send-signal-term")
                    s.append(_("_Force Stop…"), "win.send-signal-kill")
                  end,
        )
      end
    end

    PRIORITIES = [
      [-> { _("_Very High") }, -20],
      [-> { _("_High") }, -5],
      [-> { _("_Normal") }, 0],
      [-> { _("_Low") }, 5],
      [-> { _("Ve_ry Low") }, 19],
    ].freeze

    def priority_menu
      @priority_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(
          nil,
          section do |s|
                    PRIORITIES.each do |(label, value)|
                      s.append_item(priority_item(label.call, value))
                    end
                  end,
        )

        menu.append_section(
          nil,
          section do |s|
                    s.append_item(priority_item(_("Cus_tom"), CUSTOM_PRIORITY))
                    s.append(_("Set _Affinity…"), "win.set-affinity")
                  end,
        )
      end
    end

    def priority_item(label, value)
      Gio::MenuItem.new(label, nil).tap do |item|
        item.set_action_and_target_value("win.priority", GLib::Variant.new(value, "i"))
      end
    end

    # menus.ui's process-window-menu, which is the primary menu while the
    # Processes tab is showing; the other tabs get the shorter one.
    def main_menu
      @main_menu ||= Gio::Menu.new.tap do |menu|
        menu.append_section(nil, section { |s| s.append(_("_Refresh"), "win.refresh") })

        menu.append_section(
          nil,
          section do |s|
                    s.append_item(whose_item(_("Ac_tive Processes"), "active"))
                    s.append_item(whose_item(_("All Pro_cesses"), "all"))
                    s.append_item(whose_item(_("_My Processes"), "user"))
                  end,
        )

        menu.append_section(nil, section { |s| s.append(_("Show _Dependencies"), "win.show-dependencies") })

        menu.append_section(
          nil,
          section do |s|
                    # Menu item to Open Search for Open Files dialog
                    s.append(_("_Search for Open Files"), "app.lsof")
                  end,
        )

        menu.append_section(
          nil,
          section do |s|
                    s.append(_("_Preferences"), "app.preferences")
                    s.append(_("_Help"), "app.help")
                    s.append(_("_Keyboard Shortcuts"), "win.shortcuts")
                    s.append(_("_About System Monitor"), "win.about")
                  end,
        )
      end
    end

    def whose_item(label, target)
      Gio::MenuItem.new(label, nil).tap do |item|
        item.set_action_and_target_value("win.show-whose-processes", GLib::Variant.new(target, "s"))
      end
    end

    def section
      Gio::Menu.new.tap { |menu| yield(menu) }
    end
  end
end
