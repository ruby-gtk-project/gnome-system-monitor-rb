# frozen_string_literal: true

require "adwaita"

require_relative "actions"
require_relative "i18n"
require_relative "settings"
require_relative "units"

module GnomeSystemMonitor
  # The small confirmation and edit dialogs of procdialogs.cpp: confirming a
  # signal, choosing a priority, choosing an affinity — and reporting when one
  # of them could not be done.
  module Dialogs
    include Translations
    extend Translations

    # setpriority(2)'s range.
    NICE_MINIMUM = -20
    NICE_MAXIMUM = 19

    module_function

    # procdialog_create_kill_dialog(). `on_confirm` runs only if the user
    # agrees; when the preference to ask first is off, it runs straight away.
    def confirm_signal(parent, processes, signal, &on_confirm)
      if Settings[Settings::KILL_DIALOG]
        alert_dialog(processes, signal).tap do |dialog|
          dialog.signal_connect("response") do |_dialog, response|
            if response == "confirm"
              on_confirm.call
            end
          end

          dialog.present(parent)
        end
      else
        on_confirm.call
      end
    end

    def alert_dialog(processes, signal)
      Adwaita::AlertDialog.new(heading(processes, signal), body(signal)).tap do |dialog|
        dialog.add_response("cancel", _("_Cancel"))
        dialog.add_response("confirm", confirm_label(signal))
        dialog.set_response_appearance("confirm", Adwaita::ResponseAppearance::DESTRUCTIVE)
        dialog.close_response = "cancel"
        dialog.default_response = "cancel"
      end
    end

    # A single process is named; several are counted.
    def heading(processes, signal)
      if processes.length == 1
        format(single_heading(signal), short_name(processes.first))
      else
        format(plural_heading(signal, processes.length), processes.length)
      end
    end

    # The name is cut at " -" so a process that carries its arguments in its
    # name does not fill the dialog's title.
    def short_name(process) = process.name.split(" -").first.to_s

    def single_heading(signal)
      case signal
      # xgettext: primary alert message for killing single process
      when :kill then _("Force Stop %s?")
      # xgettext: primary alert message for ending single process
      when :term then _("End %s?")
      # xgettext: primary alert message for stopping single process
      else _("Temporarily Stop %s?")
      end
    end

    def plural_heading(signal, count)
      case signal
      # xgettext: primary alert message for killing multiple processes
      when :kill then n_("Force Stop Selected Process?", "Force Stop %d Selected Processes?", count)
      # xgettext: primary alert message for ending multiple processes
      when :term then n_("End Selected Process?", "End %d Selected Processes?", count)
      # xgettext: primary alert message for stopping multiple processes
      else n_("Temporarily Stop Selected Process?", "Temporarily Stop %d Selected Processes?", count)
      end
    end

    def body(signal)
      case signal
      # xgettext: secondary alert message
      when :kill then _("Force stopping processes can result in data loss, crashes, and system failures")
      # xgettext: secondary alert message
      when :term then _("Ending processes can result in data loss, crashes, and system failures")
      # xgettext: secondary alert message
      else _("Stopping (pausing) processes can result in data loss, crashes, and system failures")
      end
    end

    def confirm_label(signal)
      case signal
      when :kill then _("_Force Stop")
      when :term then _("_End")
      else _("_Pause")
      end
    end

    # Actions::Failure, shown the way procactions.cpp shows it.
    def report(parent, failure)
      Adwaita::AlertDialog.new(failure.heading, failure.message).tap do |dialog|
        dialog.add_response("close", _("_Close"))
        dialog.close_response = "close"
        dialog.present(parent)
      end
    end
  end

  # procdialog_create_renice_dialog(): a slider from -20 to 19 with the
  # priority band it lands in spelled out underneath.
  class ReniceDialog
    include Translations

    def initialize(processes:, on_apply:)
      @processes = processes
      @on_apply = on_apply
    end

    attr_reader :processes, :on_apply

    def build
      dialog.tap do |d|
        d.extra_child = box

        box.tap do |b|
          b.append(nice_label)
          b.append(scale)
          b.append(priority_label)

          scale.signal_connect("value-changed") { update_priority_label }
        end

        d.signal_connect("response") do |_dialog, response|
          if response == "change"
            on_apply.call(scale.value.to_i)
          end
        end
      end

      update_priority_label
      dialog
    end

    def present(parent)
      build
      dialog.present(parent)
    end

    def dialog
      @dialog ||= Adwaita::AlertDialog.new(heading, nil).tap do |d|
        d.add_response("cancel", _("_Cancel"))
        d.add_response("change", _("_Change Priority"))
        d.set_response_appearance("change", Adwaita::ResponseAppearance::SUGGESTED)
        d.close_response = "cancel"
        d.default_response = "change"
      end
    end

    def heading
      if processes.length == 1
        format(
          _("Change Priority of %<name>s (PID %<pid>u)"),
          name: processes.first.name,
          pid:  processes.first.pid,
        )
      else
        format(
          n_(
            "Change Priority of the Selected Process",
            "Change Priority of %d Selected Processes",
            processes.length,
          ),
          processes.length,
        )
      end
    end

    def box
      @box ||= Gtk::Box.new(:vertical, 6).tap do |b|
        b.margin_top = 6
      end
    end

    def nice_label
      @nice_label ||= Gtk::Label.new(_("_Nice Value:")).tap do |label|
        label.use_underline = true
        label.halign = :start
        label.mnemonic_widget = scale
      end
    end

    def scale
      @scale ||= Gtk::Scale.new(:horizontal, adjustment).tap do |s|
        s.digits = 0
        s.draw_value = true
        s.value_pos = :right
        s.hexpand = true
      end
    end

    def adjustment
      @adjustment ||= Gtk::Adjustment.new(
        processes.first.nice,
        Dialogs::NICE_MINIMUM,
        Dialogs::NICE_MAXIMUM,
        1,
        1,
        0,
      )
    end

    def priority_label
      @priority_label ||= Gtk::Label.new.tap do |label|
        label.halign = :start
        label.add_css_class("dim-label")
      end
    end

    def update_priority_label
      priority_label.label = Units.nice_level_with_priority(scale.value.to_i)
    end
  end

  # setaffinity.cpp: one toggle per CPU, plus "run on all" and "apply to child
  # threads".
  class AffinityDialog
    include Translations

    def initialize(process:, cpu_count:, on_apply:)
      @process = process
      @cpu_count = cpu_count
      @on_apply = on_apply
    end

    attr_reader :process, :cpu_count, :on_apply

    def build
      dialog.tap do |d|
        d.extra_child = box

        box.tap do |b|
          b.append(all_cpus_check)
          b.append(cpu_grid)
          b.append(child_threads_check)

          cpu_checks.each_with_index do |check, index|
            cpu_grid.attach(
              check,
              index % columns,
              index / columns,
              1,
              1,
            )
            check.signal_connect("toggled") { sync_all_cpus_check }
          end

          all_cpus_check.signal_connect("toggled") { apply_all_cpus }
        end

        d.signal_connect("response") do |_dialog, response|
          if response == "apply"
            on_apply.call(selected_cpus, child_threads_check.active?)
          end
        end
      end

      load_current
      dialog
    end

    def present(parent)
      build
      dialog.present(parent)
    end

    def load_current
      Actions.affinity(process.pid).then do |cpus|
        cpu_checks.each_with_index { |check, index| check.active = cpus.include?(index) }
        sync_all_cpus_check
      end
    end

    def selected_cpus
      cpu_checks.each_with_index.select { |check, _index| check.active? }.map { |(_check, index)| index }
    end

    # The "all CPUs" box follows the individual ones rather than driving them,
    # except when the user clicks it.
    def sync_all_cpus_check
      if !@applying_all
        @syncing = true
        all_cpus_check.active = cpu_checks.all?(&:active?)
        @syncing = false
      end
    end

    def apply_all_cpus
      if !@syncing
        @applying_all = true
        cpu_checks.each { |check| check.active = all_cpus_check.active? }
        @applying_all = false
      end
    end

    def dialog
      @dialog ||= Adwaita::AlertDialog.new(heading, nil).tap do |d|
        d.add_response("cancel", _("_Cancel"))
        d.add_response("apply", _("_Apply"))
        d.set_response_appearance("apply", Adwaita::ResponseAppearance::SUGGESTED)
        d.close_response = "cancel"
        d.default_response = "apply"
      end
    end

    def heading
      format(_("Set Affinity of %<name>s (PID %<pid>u)"), name: process.name, pid: process.pid)
    end

    def box = @box ||= Gtk::Box.new(:vertical, 12).tap { |b| b.margin_top = 6 }

    def columns = @columns ||= [cpu_count, 8].min

    def cpu_grid
      @cpu_grid ||= Gtk::Grid.new.tap do |grid|
        grid.row_spacing = 6
        grid.column_spacing = 12
      end
    end

    def cpu_checks
      @cpu_checks ||= Array.new(cpu_count) do |index|
        Gtk::CheckButton.new(format(_("CPU%d"), index + 1))
      end
    end

    def all_cpus_check
      @all_cpus_check ||= Gtk::CheckButton.new(_("_Run on all CPUs")).tap do |check|
        check.use_underline = true
      end
    end

    def child_threads_check
      @child_threads_check ||= Gtk::CheckButton.new(_("Apply to Child _Threads")).tap do |check|
        check.use_underline = true
      end
    end
  end
end
