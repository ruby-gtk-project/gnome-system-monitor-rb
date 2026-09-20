# frozen_string_literal: true

require "adwaita"

require_relative "columns"
require_relative "proc_fs"

module GnomeSystemMonitor
  # One row of the process table.
  #
  # Upstream's ProcInfo is a plain struct feeding a GtkTreeStore. A
  # GtkColumnView sorts on GObject properties instead, so every sortable field
  # is installed as a real property: GtkStringSorter and GtkNumericSorter then
  # do the comparing in C, and a property that changes re-sorts the view by
  # itself.
  #
  # `install_property` in these bindings wires a property to Ruby accessors of
  # the same name rather than creating them, so each one needs its
  # `attr_accessor` too.
  class Process < GLib::Object
    type_register

    PARAMS = {
      string: ->(name) { GLib::Param::String.new(
        name,
        name,
        name,
        "",
        GLib::Param::READWRITE,
      ) },
      uint:   ->(name) { GLib::Param::UInt.new(
        name,
        name,
        name,
        0,
        2**32 - 1,
        0,
        GLib::Param::READWRITE,
      ) },
      int:    ->(name) { GLib::Param::Int.new(
        name,
        name,
        name,
        -2**31,
        2**31 - 1,
        0,
        GLib::Param::READWRITE,
      ) },
      uint64: ->(name) { GLib::Param::UInt64.new(
        name,
        name,
        name,
        0,
        2**63 - 1,
        0,
        GLib::Param::READWRITE,
      ) },
      double: ->(name) { GLib::Param::Double.new(
        name,
        name,
        name,
        0.0,
        1e12,
        0.0,
        GLib::Param::READWRITE,
      ) },
    }.freeze

    Columns.all.each do |column|
      attr_accessor column.key

      install_property(PARAMS.fetch(column.type).call(column.key.to_s))
    end

    # The text each column shows, as its own property. The cells bind to
    # these; the columns sort on the typed properties above. A cell cannot
    # format anything for itself — the binding that keeps it live is a
    # GtkExpression, which can only read a property — so the formatting
    # happens once per process per tick and lands here.
    TEXT_SUFFIX = "_text"

    Columns.all.each do |column|
      :"#{column.key}#{TEXT_SUFFIX}".then do |key|
        attr_accessor key

        install_property(PARAMS.fetch(:string).call(key.to_s))
      end
    end

    # Not columns, so not properties: the tree structure, the identity the
    # refresh matches on, and the tooltip.
    attr_accessor :ppid, :uid, :comm, :tooltip, :icon, :children, :child_store

    def initialize
      super
      Columns.all.each do |column|
        case column.type
        when :string then send(:"#{column.key}=", "")
        when :double then send(:"#{column.key}=", 0.0)
        else send(:"#{column.key}=", 0)
        end

        send(:"#{column.key}#{TEXT_SUFFIX}=", "")
      end
      @children = []
      @ppid = -1
      @uid = -1
      @comm = ""
      @tooltip = ""
    end

    # Tell the sorters and the bound labels that a value moved. Notifying
    # every property on every tick would re-sort the whole view constantly, so
    # only the ones that actually changed are announced.
    def announce(changed)
      changed.each { |key| notify(key.to_s) }
    end

    # The fields that never change for the life of a process, read once when
    # it first appears. Upstream does the same in ProcInfo's constructor.
    # False if the process is already gone.
    def load_static(now)
      ProcFs.process(pid).then do |stat|
        case
        when stat.nil? then false
        else fill_static(stat, ProcFs.cmdline(pid), now)
        end
      end
    end

    # A kernel thread has an empty cmdline, and then the comm is all there is
    # to show for a name and a command line both.
    def fill_static(stat, arguments, now)
      self.comm = stat[:comm]
      self.name = ProcFs.process_name(stat[:comm], arguments)
      self.arguments = arguments.join(" ").then { |line| line.empty? ? stat[:comm] : line }
      self.tooltip = self.arguments
      self.uid = ProcFs.uid(pid).to_i
      self.user = ProcFs.user_name(uid)
      self.security_context = ProcFs.security_context(pid)
      self.start_time = now.boot_time + (stat[:start_ticks] / ProcFs::CLOCK_TICKS)
      self.cpu_time = (stat[:utime] + stat[:stime]) * 100 / ProcFs::CLOCK_TICKS

      # Seed the IO counters too. The rate columns are a delta against these,
      # so leaving them at zero would make a process's whole lifetime of IO
      # show up as one tick's worth of throughput the first time it is seen.
      ProcFs.io(pid).then do |io|
        self.disk_read_total = io[:read]
        self.disk_write_total = io[:write]
      end

      true
    end

    # One refresh tick. `now` carries the values shared across every process
    # in this pass — the CPU total delta, the interval, the boot time — so
    # they are read once rather than once per process.
    #
    # Returns the properties whose value moved, for announce().
    def update(now)
      ProcFs.process(pid)&.then do |stat|
        [].tap do |changed|
          changed.concat(update_cpu(stat, now))
          changed.concat(update_memory)
          changed.concat(update_io(now))
          changed.concat(update_strings(stat))
        end
      end
    end

    def update_cpu(stat, now)
      ((stat[:utime] + stat[:stime]) * 100 / ProcFs::CLOCK_TICKS).then do |new_cpu_time|
        [].tap do |changed|
          (new_cpu_time - cpu_time).then do |difference|
            # If the process burned CPU since the last tick it is running,
            # whatever the kernel's momentary state says (#606579).
            if difference.positive?
              stat[:state] = ProcFs::RUNNING
            end

            set(changed, :pcpu, (difference * now.cpu_scale / now.cpu_total_time.to_f).clamp(0.0, now.cpu_scale))
          end

          set(changed, :cpu_time, new_cpu_time)
          set(changed, :status, stat[:state])
          set(changed, :nice, stat[:nice])
          set(changed, :priority, stat[:nice])
          self.ppid = stat[:ppid]
        end
      end
    end

    def update_memory
      [].tap do |changed|
        ProcFs.memory(pid)&.then do |memory|
          set(changed, :vmsize, memory[:vmsize])
          set(changed, :memres, memory[:memres])
          set(changed, :memshared, memory[:memshared])
          set(changed, :mem, [memory[:memres] - memory[:memshared], 0].max)
        end

        set(changed, :memwritable, ProcFs.memory_writable(pid).to_i)
      end
    end

    # The rate columns are a delta over the interval, and the total columns
    # are the counter itself — which is why the totals have to be updated
    # after the rates are worked out from them.
    def update_io(now)
      [].tap do |changed|
        ProcFs.io(pid).then do |io|
          set(changed, :disk_read, [(io[:read] - disk_read_total) / now.interval, 0].max.to_i)
          set(changed, :disk_write, [(io[:write] - disk_write_total) / now.interval, 0].max.to_i)
          set(changed, :disk_read_total, io[:read])
          set(changed, :disk_write_total, io[:write])
        end
      end
    end

    def update_strings(_stat)
      [].tap do |changed|
        set(changed, :wchan, ProcFs.wchan(pid))
        set(changed, :cgroup_name, ProcFs.cgroup_name(pid))
        set(changed, :unit, ProcFs.systemd_unit(pid))

        ProcFs.systemd_session(pid).then do |session_id|
          set(changed, :session, session_id)

          ProcFs.session_info(session_id).then do |info|
            set(changed, :seat, info[:seat])
            set(changed, :owner, info[:owner] ? ProcFs.user_name(info[:owner]) : "")
          end
        end
      end
    end

    # Assign only when the value moved, and record that it did. A GtkSorter
    # reacts to the notify, so a no-op write is a wasted re-sort.
    def set(changed, key, value)
      if send(key) != value
        send(:"#{key}=", value)
        changed << key
      end
    end

    # Write a column's rendered text. True when it moved, which is what tells
    # the view this row needs binding again.
    def set_text(key, text)
      :"#{key}#{TEXT_SUFFIX}".then do |property|
        if send(property) == text
          false
        else
          send(:"#{property}=", text)
          true
        end
      end
    end

    # What identifies this row across a refresh.
    def key = pid

    def kernel_thread? = arguments.empty? || arguments == comm

    # GLIBTOP_EXCLUDE_IDLE: the Active Processes view hides anything that is
    # merely asleep.
    def active? = status != ProcFs::INTERRUPTIBLE && status != ProcFs::ZOMBIE

    def own? = uid == ::Process.uid
  end
end
