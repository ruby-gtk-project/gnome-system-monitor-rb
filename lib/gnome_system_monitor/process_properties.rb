# frozen_string_literal: true

require "adwaita"

require_relative "columns"
require_relative "proc_fs"
require_relative "i18n"
require_relative "settings"
require_relative "units"

module GnomeSystemMonitor
  # procproperties.ui: one process, spelled out in rows, refreshed on the
  # process tick for as long as the window is open.
  class ProcessProperties
    include Translations

    def initialize(process:, on_signal:)
      @process = process
      @on_signal = on_signal
    end

    attr_reader :process, :on_signal

    def build
      window.tap do |win|
        win.title = format(_("%<name>s (PID %<pid>u)"), name: process.name, pid: process.pid)
        win.content = toolbar_view
        win.insert_action_group("procprop", action_group)
        win.add_controller(escape_shortcut)

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = page
          view.add_bottom_bar(action_bar)

          page.tap do |p|
            p.add(details_group)
            p.add(status_group)
            p.add(usage_group)
            p.add(extra_group)
          end

          action_bar.tap do |bar|
            bar.set_center_widget(button_box)
            bar.pack_end(menu_button)

            button_box.tap do |box|
              box.append(end_button)
              box.append(force_stop_button)
            end
          end
        end
      end

      update
      window
    end

    # procproperties.cpp inserts a "procprop" action group on the window: the
    # two action-bar buttons, the two More Actions menu items and the Escape
    # shortcut all drive the same four signals through it, rather than each
    # knowing how to send one.
    SIGNAL_ACTIONS = {
      "send-signal-stop" => :stop,
      "send-signal-cont" => :cont,
      "send-signal-term" => :term,
      "send-signal-kill" => :kill,
    }.freeze

    def action_group
      @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
        SIGNAL_ACTIONS.each { |name, signal| group.add_action(signal_action(name, signal)) }
        group.add_action(close_action)
      end
    end

    def signal_action(name, signal)
      Gio::SimpleAction.new(name).tap do |a|
        a.signal_connect("activate") { on_signal.call(signal) }
      end
    end

    def close_action
      Gio::SimpleAction.new("close").tap do |a|
        a.signal_connect("activate") { window.close }
      end
    end

    def present(parent)
      build
      window.transient_for = parent
      window.present
    end

    # Every value row, so update() can walk them without naming each one
    # twice. An entry is the row widget and the setter that writes a value
    # into it, because the two kinds of row carry their value differently.
    def rows
      @rows ||= titles.to_h { |key, title| [key, row_for(key, title)] }
    end

    def titles
      {
        pid:              _("Process ID"),
        user:             _("User"),
        start_time:       _("Started"),
        priority:         _("Priority"),
        status:           _("Status"),
        pcpu:             _("CPU"),
        mem:              _("Memory"),
        cpu_time:         _("CPU Time"),
        vmsize:           _("Virtual Memory"),
        memres:           _("Resident Memory"),
        memwritable:      _("Writable Memory"),
        memshared:        _("Shared Memory"),
        security_context: _("Security Context"),
        arguments:        _("Command Line"),
        wchan:            _("Waiting Channel"),
        cgroup_name:      _("Control Group"),
      }
    end

    # procproperties.ui's last group holds four values long enough to want the
    # whole width of the row, so each goes in the subtitle under its title
    # rather than beside it — which is what the `property` style class is for.
    PROPERTY_KEYS = %i[security_context arguments wchan cgroup_name].freeze

    def row_for(key, title)
      if PROPERTY_KEYS.include?(key)
        property_row(title)
      else
        value_row(title)
      end
    end

    # The same formatters the process table uses, so a value reads the same in
    # both places.
    def update
      Settings[Settings::PROCESS_MEMORY_IN_IEC].then do |iec|
        rows.each do |key, (_row, write)|
          write.call(value_for(key, iec))
        end
      end
    end

    def value_for(key, iec)
      process.send(key).then do |value|
        case key
        when :pcpu then Units.percentage(value)
        when :cpu_time then Units.duration(value)
        when :start_time then Units.start_time(value)
        when :status then status_text(value)
        when :priority then Units.nice_level(value)
        when :mem, :vmsize, :memres, :memwritable, :memshared then Units.size_or_na(value, iec)
        else value.to_s
        end
      end
    end

    def status_text(status)
      case status
      when ProcFs::RUNNING then _("Running")
      when ProcFs::STOPPED then _("Stopped")
      when ProcFs::ZOMBIE then _("Zombie")
      when ProcFs::UNINTERRUPTIBLE then _("Uninterruptible")
      else _("Sleeping")
      end
    end

    # Widgets
    def window
      @window ||= Adwaita::Window.new.tap do |win|
        win.set_default_size(500, 640)
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new
    def page = @page ||= Adwaita::PreferencesPage.new

    def details_group = @details_group ||= group(_("Details"), %i[pid user])
    def status_group = @status_group ||= group(_("Status"), %i[start_time priority status])

    def usage_group
      @usage_group ||= group(_("Usage"), %i[pcpu mem cpu_time vmsize memres memwritable memshared])
    end

    def extra_group
      @extra_group ||= group(nil, %i[security_context arguments wchan cgroup_name])
    end

    def group(title, keys)
      Adwaita::PreferencesGroup.new.tap do |g|
        if title
          g.title = title
        end

        keys.each { |key| g.add(rows.fetch(key).first) }
      end
    end

    # Each row is the row itself and the label that carries its value; the
    # value wraps and is selectable, because a command line or a control group
    # is often long and worth copying. `numeric` is procproperties.ui's class
    # on every one of these: tabular figures, so a column of sizes lines up.
    def value_row(title)
      Gtk::Label.new.tap do |label|
        label.wrap = true
        label.selectable = true
        label.xalign = 1
        label.halign = :end
        label.add_css_class("dim-label")
        label.add_css_class("numeric")
      end.then do |label|
        [
          Adwaita::ActionRow.new.tap do |r|
            r.title = title
            r.add_suffix(label)
          end,
          ->(text) { label.label = text },
        ]
      end
    end

    def property_row(title)
      Adwaita::ActionRow.new.tap do |r|
        r.title = title
        r.subtitle_selectable = true
        r.add_css_class("property")
        r.add_css_class("numeric")
      end.then do |r|
        [r, ->(text) { r.subtitle = text }]
      end
    end

    def action_bar
      @action_bar ||= Gtk::ActionBar.new.tap do |bar|
        bar.margin_top = 6
        bar.margin_bottom = 6
        bar.margin_start = 6
        bar.margin_end = 6
      end
    end

    def button_box
      @button_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.hexpand = true
        box.homogeneous = true
        box.margin_start = 6
        box.margin_end = 6
      end
    end

    # The More Actions button: Pause and Resume, which have no button of their
    # own in the action bar, pointing up out of the bottom bar.
    def menu_button
      @menu_button ||= Gtk::MenuButton.new.tap do |button|
        button.icon_name = "view-more-symbolic"
        button.direction = :up
        button.tooltip_text = _("More Actions")
        button.menu_model = menu
        button.add_css_class("flat")
      end
    end

    def menu
      @menu ||= Gio::Menu.new.tap do |m|
        m.append(_("_Pause…"), "procprop.send-signal-stop")
        m.append(_("_Resume"), "procprop.send-signal-cont")
      end
    end

    def escape_shortcut
      @escape_shortcut ||= Gtk::ShortcutController.new.tap do |controller|
        controller.scope = :managed
        controller.add_shortcut(
          Gtk::Shortcut.new(
            Gtk::ShortcutTrigger.parse_string("Escape"),
            Gtk::NamedAction.new("procprop.close"),
          ),
        )
      end
    end

    def end_button
      @end_button ||= Gtk::Button.new(label: _("_End Process…")).tap do |button|
        button.use_underline = true
        button.action_name = "procprop.send-signal-term"
        button.add_css_class("destructive-action")
      end
    end

    def force_stop_button
      @force_stop_button ||= Gtk::Button.new(label: _("_Force Stop…")).tap do |button|
        button.use_underline = true
        button.action_name = "procprop.send-signal-kill"
        button.add_css_class("destructive-action")
      end
    end
  end
end
