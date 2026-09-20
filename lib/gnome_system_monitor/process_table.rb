# frozen_string_literal: true

require "adwaita"

require_relative "columns"
require_relative "proc_fs"
require_relative "process"
require_relative "settings"
require_relative "system_stats"

module GnomeSystemMonitor
  # The model behind the process view: which processes exist, how they nest,
  # and what the search box hides.
  #
  # Upstream keeps a GtkTreeStore and rebuilds rows into it. A GtkColumnView
  # wants a GListModel, so the store here holds Process objects, a
  # GtkTreeListModel gives them the dependency tree, and a GtkFilterListModel
  # applies the search — the same three jobs, in the widgets GTK4 provides for
  # them.
  class ProcessTable
    # The values shared by every process in one refresh pass, so each is
    # computed once rather than once per process.
    Tick = Struct.new(
      :cpu_scale,
      :cpu_total_time,
      :interval,
      :boot_time,
    )

    def initialize
      @processes = {}
      @search_text = ""
      @cpu_total_time_last = 0
    end

    attr_reader :processes, :search_text

    def search_text=(text)
      @search_text = text.to_s
      search_filter.changed(:different)
    end

    # The model the view hands to its selection: tree, then search.
    def model = filter_model

    def root_store = @root_store ||= Gio::ListStore.new(Process)

    # Every store behind the tree, so a refresh can announce the lot.
    def stores
      [root_store] + processes.each_value.filter_map(&:child_store)
    end

    # `passthrough` false so the rows arrive as GtkTreeListRows, which is what
    # the expander in the name column needs. Autoexpand is off: upstream's
    # dependency view starts collapsed.
    def tree_model
      @tree_model ||= Gtk::TreeListModel.new(root_store, false, false) do |process|
        child_store_for(process)
      end
    end

    def filter_model = @filter_model ||= Gtk::FilterListModel.new(tree_model, search_filter)

    # iter_matches_search_key(): the terms are split on spaces and bars and
    # joined into one alternation, matched case-insensitively against the
    # name, the user, the PID and the command line. A pattern that will not
    # compile is matched literally.
    def search_filter
      @search_filter ||= Gtk::CustomFilter.new do |row|
        if search_text.empty?
          true
        else
          matches?(row.item)
        end
      end
    end

    def matches?(process)
      search_regexp.then do |regexp|
        [process.name, process.user, process.pid.to_s, process.arguments].any? do |field|
          regexp.match?(field)
        end
      end
    end

    # Recompiled only when the text moves: the filter runs this once per row
    # per keystroke.
    def search_regexp
      if @search_regexp_text != search_text
        @search_regexp_text = search_text
        @search_regexp = compile_search(search_text)
      end

      @search_regexp
    end

    def compile_search(text)
      text.split(/[ |]/).reject(&:empty?).join("|").then do |pattern|
        Regexp.new(pattern, Regexp::IGNORECASE)
      end
    rescue RegexpError
      Regexp.new(Regexp.escape(text), Regexp::IGNORECASE)
    end

    # One poll of /proc. Adds what appeared, updates the rest, re-hangs the
    # tree, and only then lets go of what exited.
    #
    # That last order matters. A Process is a GObject whose values live in
    # Ruby instance variables, and the stores hold the GObject, not the Ruby
    # wrapper. Drop the last Ruby reference while a store still holds the row
    # and the wrapper can be collected and later rebuilt — and rebuilding one
    # during a GC sweep takes the interpreter down with it.
    def refresh
      tick.then do |now|
        wanted_pids.then do |pids|
          add_new(pids, now)

          exited(pids, now).then do |dead|
            rearrange(processes.each_value.reject { |process| dead.include?(process.pid) })
            dead.each { |pid| processes.delete(pid) }
          end
        end
      end
    end

    # The processes that are no longer there: the ones /proc stopped listing,
    # plus the ones that vanished between that listing and their own update.
    def exited(pids, now)
      (processes.keys - pids).to_set.tap do |dead|
        processes.each_value do |process|
          process.update(now).then do |changed|
            if changed
              process.announce(changed)
            else
              dead << process.pid
            end
          end
        end
      end
    end

    # glibtop_get_proclist()'s three modes. "active" is EXCLUDE_IDLE, which
    # can only be judged once a process has been read, so it is applied after
    # the update rather than to the raw PID list.
    def wanted_pids
      ProcFs.pids.sort.then do |pids|
        case Settings[Settings::SHOW_WHOSE_PROCESSES]
        when "user" then pids.select { |pid| ProcFs.uid(pid) == ::Process.uid }
        else pids
        end
      end
    end

    def tick
      SystemStats.cpu_times.then do |cpus|
        cpus.first.total.then do |total|
          Tick.new(
            Settings.cpu_scale(cpus.length - 1),
            [total - @cpu_total_time_last, 1].max,
            Settings.update_interval,
            boot_time,
          ).tap { @cpu_total_time_last = total }
        end
      end
    end

    # /proc/stat's btime, read once: the process start times in /proc/PID/stat
    # are relative to it.
    def boot_time
      @boot_time ||= ProcFs.read_lines("/proc/stat").to_a
                           .find { |line| line.start_with?("btime ") }.to_s.split[1].to_i
    end

    def add_new(pids, now)
      (pids - processes.keys).each do |pid|
        Process.new.tap do |process|
          process.pid = pid
          process.load_static(now)&.then { processes[pid] = process }
        end
      end
    end

    # Recompute who is a root and who is whose child, then move only the rows
    # that actually changed — splicing the whole store every tick would throw
    # away the selection and the scroll position.
    def rearrange(live)
      visible_processes(live).then do |visible|
        if Settings[Settings::SHOW_DEPENDENCIES]
          arrange_tree(visible)
        else
          arrange_flat(visible)
        end
      end
    end

    def visible_processes(live)
      case Settings[Settings::SHOW_WHOSE_PROCESSES]
      when "active" then live.select(&:active?)
      else live
      end
    end

    def arrange_flat(visible)
      visible.each { |process| process.children = [] }
      sync_store(root_store, visible.sort_by(&:pid))
    end

    # A process whose parent is not itself shown becomes a root, so nothing
    # disappears just because its parent was filtered out.
    def arrange_tree(visible)
      visible.to_h { |process| [process.pid, process] }.then do |by_pid|
        visible.each { |process| process.children = [] }

        visible.each do |process|
          by_pid[process.ppid].then do |parent|
            if parent && parent != process
              parent.children << process
            end
          end
        end

        visible.each do |process|
          if process.child_store
            sync_store(process.child_store, process.children.sort_by(&:pid))
          end
        end

        sync_store(root_store, visible.reject { |process| by_pid[process.ppid] }.sort_by(&:pid))
      end
    end

    # The child model for one row of the dependency view.
    #
    # Each process keeps the same store for its lifetime, so the tree can be
    # updated in place rather than rebuilt. That needs one extra reference per
    # call: GtkTreeListModel takes ownership of whatever this returns and
    # drops it when the row goes away, and handing back a store we also hold —
    # without accounting for that — leaves us using freed memory the second
    # time round.
    def child_store_for(process)
      if process.children.empty?
        nil
      else
        Gio::ListStore.new(Process).tap do |store|
          process.children.sort_by(&:pid).each { |child| store.append(child) }
          process.child_store = store
        end
      end
    end

    # Bring `store` in line with `wanted` by removing and inserting only where
    # they differ.
    # Both lists are in PID order, so dropping what left and then inserting
    # what arrived at its own index lands every row in the right place — and
    # the rows that did not move are never touched, which is what keeps the
    # selection and the scroll position.
    #
    # Rows are matched by PID, not by object identity: get_item() hands back a
    # fresh Ruby wrapper around the same GObject each call.
    def sync_store(store, wanted)
      wanted.map(&:pid).to_set.then do |wanted_pids|
        (store.n_items - 1).downto(0) do |index|
          if !wanted_pids.include?(store.get_item(index).pid)
            store.remove(index)
          end
        end
      end

      wanted.each_with_index do |process, index|
        if index >= store.n_items || store.get_item(index).pid != process.pid
          store.insert(index, process)
        end
      end
    end

    # proctable_refresh_summary_headers(): the totals that sit under the
    # column titles.
    def totals
      processes.values.then do |all|
        {
          pcpu:             all.sum(&:pcpu),
          mem:              all.sum(&:mem),
          vmsize:           all.sum(&:vmsize),
          memres:           all.sum(&:memres),
          memwritable:      all.sum(&:memwritable),
          memshared:        all.sum(&:memshared),
          disk_read_total:  all.sum(&:disk_read_total),
          disk_write_total: all.sum(&:disk_write_total),
          disk_read:        all.sum(&:disk_read),
          disk_write:       all.sum(&:disk_write),
        }
      end
    end
  end
end
