# frozen_string_literal: true

require_relative "i18n"

module GnomeSystemMonitor
  # The process table's columns, in the order proctable.cpp declares them.
  #
  # That order is not cosmetic: the gschema stores visibility and width under
  # `col-<index>-visible` and `col-<index>-width`, so an existing
  # installation's settings only keep meaning while the indices match
  # upstream's. Everything else the table needs — the GObject property to sort
  # on, how to render the value, whether the header carries a running total —
  # hangs off the same table.
  module Columns
    include Translations
    extend Translations

    Column = Struct.new(
      :index,
      :key,
      :title,
      :type,
      :render,
      :align,
      :total,
      :tnum,
      keyword_init: true,
    )

    # `render` names a formatter in ProcessView; `total` marks the columns
    # whose header shows the sum over every process, as upstream's
    # proctable_refresh_summary_headers() does.
    DEFINITIONS = [
      [0, :name, -> { _("Name") }, :string, :text, :start, false],
      [1, :user, -> { _("User") }, :string, :text, :start, false],
      [2, :status, -> { _("Status") }, :uint, :status, :start, false],
      [3, :vmsize, -> { _("Virtual Memory") }, :uint64, :size_na, :end, true],
      [4, :memres, -> { _("Resident Memory") }, :uint64, :size_na, :end, true],
      [5, :memwritable, -> { _("Writable Memory") }, :uint64, :size_na, :end, true],
      [6, :memshared, -> { _("Shared Memory") }, :uint64, :size_na, :end, true],
      [7, :memxserver, -> { _("X Server Memory") }, :uint64, :size_na, :end, false],
      # xgettext:no-c-format
      [8, :pcpu, -> { _("CPU") }, :double, :percentage, :end, true],
      [9, :cpu_time, -> { _("CPU Time") }, :uint64, :duration, :end, false],
      [10, :start_time, -> { _("Started") }, :uint64, :time, :start, false],
      [11, :nice, -> { _("Nice") }, :int, :text, :end, false],
      [12, :pid, -> { _("ID") }, :uint, :text, :end, false],
      [13, :security_context, -> { _("Security Context") }, :string, :text, :start, false],
      [14, :arguments, -> { _("Command Line") }, :string, :text, :start, false],
      [15, :mem, -> { _("Memory") }, :uint64, :size_na, :end, true],
      # xgettext: combined noun, the function the process is waiting in, see wchan ps(1)
      [16, :wchan, -> { _("Waiting Channel") }, :string, :text, :start, false],
      [17, :cgroup_name, -> { _("Control Group") }, :string, :text, :start, false],
      [18, :unit, -> { _("Unit") }, :string, :text, :start, false],
      [19, :session, -> { _("Session") }, :string, :text, :start, false],
      # TRANSLATORS: Seat = i.e. the physical seat the session of the process
      # belongs to, only for multi-seat environments.
      [20, :seat, -> { _("Seat") }, :string, :text, :start, false],
      [21, :owner, -> { _("Owner") }, :string, :text, :start, false],
      [22, :disk_read_total, -> { _("Disk Read Total") }, :uint64, :size_na, :end, true],
      [23, :disk_write_total, -> { _("Disk Write Total") }, :uint64, :size_na, :end, true],
      [24, :disk_read, -> { _("Disk Read") }, :uint64, :io_rate, :end, true],
      [25, :disk_write, -> { _("Disk Write") }, :uint64, :io_rate, :end, true],
      [26, :priority, -> { _("Priority") }, :int, :priority, :start, false],
    ].freeze

    # The columns rendered with tabular figures, so the digits line up down
    # the column however the value changes.
    TNUM = %i[
      pid vmsize memres memshared mem pcpu cpu_time disk_read_total
      disk_write_total disk_read disk_write start_time nice wchan
    ].freeze

    # proctable.cpp skips this one when it builds the view: it is read (and
    # totalled in the Resident Memory header) but never given a column.
    SKIPPED = :memwritable

    module_function

    def all
      @all ||= DEFINITIONS.map do |(index, key, title, type, render, align, total)|
        Column.new(
          index:  index,
          key:    key,
          title:  title,
          type:   type,
          render: render,
          align:  align,
          total:  total,
          tnum:   TNUM.include?(key),
        )
      end
    end

    # The columns that actually become a GtkColumnViewColumn. The name column
    # is built separately — it carries the icon and the tree expander — and
    # writable memory is not shown at all.
    def visible = all.reject { |column| column.key == SKIPPED || column.key == :name }

    def find(key) = all.find { |column| column.key == key }

    # The Priority column sorts and renders off the nice value, which is why
    # it has no storage of its own.
    def sort_key(column)
      case column.key
      when :priority then :nice
      else column.key
      end
    end
  end
end
