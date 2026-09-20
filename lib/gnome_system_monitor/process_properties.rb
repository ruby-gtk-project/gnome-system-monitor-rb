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
            bar.pack_start(end_button)
            bar.pack_end(force_stop_button)

            end_button.signal_connect("clicked") { on_signal.call(:term) }
            force_stop_button.signal_connect("clicked") { on_signal.call(:kill) }
          end
        end
      end

      update
      window
    end

    def present(parent)
      build
      window.transient_for = parent
      window.present
    end

    # Every value row, so update() can walk them without naming each one
    # twice.
    def rows
      @rows ||= {
        pid:              row(_("Process ID")),
        user:             row(_("User")),
        start_time:       row(_("Started")),
        priority:         row(_("Priority")),
        status:           row(_("Status")),
        pcpu:             row(_("CPU")),
        mem:              row(_("Memory")),
        cpu_time:         row(_("CPU Time")),
        vmsize:           row(_("Virtual Memory")),
        memres:           row(_("Resident Memory")),
        memwritable:      row(_("Writable Memory")),
        memshared:        row(_("Shared Memory")),
        security_context: row(_("Security Context")),
        arguments:        row(_("Command Line")),
        wchan:            row(_("Waiting Channel")),
        cgroup_name:      row(_("Control Group")),
      }
    end

    # The same formatters the process table uses, so a value reads the same in
    # both places.
    def update
      Settings[Settings::PROCESS_MEMORY_IN_IEC].then do |iec|
        rows.each do |key, (_row, label)|
          label.label = value_for(key, iec)
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
    # is often long and worth copying.
    def row(title)
      Gtk::Label.new.tap do |label|
        label.wrap = true
        label.selectable = true
        label.xalign = 1
        label.halign = :end
        label.add_css_class("dim-label")
      end.then do |label|
        [
          Adwaita::ActionRow.new.tap do |r|
            r.title = title
            r.add_suffix(label)
          end,
          label,
        ]
      end
    end

    def action_bar = @action_bar ||= Gtk::ActionBar.new

    def end_button
      @end_button ||= Gtk::Button.new(label: _("_End Process…")).tap do |button|
        button.use_underline = true
        button.add_css_class("destructive-action")
      end
    end

    def force_stop_button
      @force_stop_button ||= Gtk::Button.new(label: _("_Force Stop…")).tap do |button|
        button.use_underline = true
        button.add_css_class("destructive-action")
      end
    end
  end
end
