# frozen_string_literal: true

require "etc"

module GnomeSystemMonitor
  # Everything the process table needs, read straight out of /proc.
  #
  # Upstream gets this from libgtop. There is no Ruby binding for libgtop, and
  # on Linux libgtop is itself a /proc reader — so the port reads /proc
  # directly and keeps libgtop's field names, units and edge cases (a process
  # that exits mid-read is skipped, not fatal).
  module ProcFs
    # The glibtop_proc_state values, kept as-is: the status column sorts on
    # this number, so the order has to be upstream's.
    RUNNING = 1
    INTERRUPTIBLE = 2
    UNINTERRUPTIBLE = 4
    ZOMBIE = 8
    STOPPED = 16

    STATES = {
      "R" => RUNNING,
      "S" => INTERRUPTIBLE,
      "D" => UNINTERRUPTIBLE,
      "Z" => ZOMBIE,
      "T" => STOPPED,
      "t" => STOPPED,
      "I" => INTERRUPTIBLE,
      "X" => ZOMBIE,
    }.freeze

    PAGE_SIZE = Etc.sysconf(Etc::SC_PAGESIZE)
    CLOCK_TICKS = Etc.sysconf(Etc::SC_CLK_TCK)

    module_function

    def pids = Dir.children("/proc").select { |name| name.match?(/\A\d+\z/) }.map(&:to_i)

    # A process can exit between the readdir and the read; every caller of
    # this treats nil as "it is gone", which is what upstream's libgtop error
    # flags amount to.
    def read_file(path)
      File.read(path)
    rescue SystemCallError
      nil
    end

    def read_lines(path) = read_file(path)&.lines

    # /proc/PID/stat, whose second field is the comm in parentheses and may
    # itself contain spaces and parentheses — so split on the LAST ')'.
    def stat(pid)
      read_file("/proc/#{pid}/stat")&.then do |text|
        text.rindex(")").then do |close|
          if close
            {
              comm:   text[(text.index("(") + 1)...close],
              fields: text[(close + 2)..].split,
            }
          end
        end
      end
    end

    # The full field set for one process, or nil if it vanished. Field
    # positions are the ones proc(5) documents, counting from `state` as 0.
    def process(pid)
      stat(pid)&.then do |parsed|
        parsed[:fields].then do |f|
          {
            pid:         pid,
            comm:        parsed[:comm],
            state:       STATES.fetch(f[0], INTERRUPTIBLE),
            ppid:        f[1].to_i,
            session_id:  f[3].to_i,
            utime:       f[11].to_i,
            stime:       f[12].to_i,
            nice:        f[16].to_i,
            start_ticks: f[19].to_i,
            vmsize:      f[20].to_i,
          }
        end
      end
    end

    # /proc/PID/statm, in pages: size, resident, shared.
    def memory(pid)
      read_file("/proc/#{pid}/statm")&.split&.then do |f|
        {
          vmsize:    f[0].to_i * PAGE_SIZE,
          memres:    f[1].to_i * PAGE_SIZE,
          memshared: f[2].to_i * PAGE_SIZE,
        }
      end
    end

    # get_process_memory_writable(): the sum of Private_Dirty across the
    # mappings. smaps_rollup does the same sum in the kernel, at a fraction of
    # the cost, so try it first and fall back for older kernels.
    def memory_writable(pid)
      read_file("/proc/#{pid}/smaps_rollup")&.then do |text|
        text[/^Private_Dirty:\s+(\d+)/, 1]
      end.then do |rollup|
        if rollup
          rollup.to_i * 1024
        else
          private_dirty_from_smaps(pid)
        end
      end
    end

    def private_dirty_from_smaps(pid)
      read_file("/proc/#{pid}/smaps").to_s.scan(/^Private_Dirty:\s+(\d+)/).sum { |m| m[0].to_i * 1024 }
    end

    def uid(pid)
      read_file("/proc/#{pid}/status")&.then { |text| text[/^Uid:\s+(\d+)/, 1]&.to_i }
    end

    # Bytes this process actually moved to and from storage, which is what the
    # disk columns mean — not the read/write syscall totals above them.
    def io(pid)
      read_file("/proc/#{pid}/io").to_s.then do |text|
        {
          read:  text[/^read_bytes:\s+(\d+)/, 1].to_i,
          write: text[/^write_bytes:\s+(\d+)/, 1].to_i,
        }
      end
    end

    # The argv, NUL-separated. An empty cmdline means a kernel thread.
    def cmdline(pid) = read_file("/proc/#{pid}/cmdline").to_s.split("\0").reject(&:empty?)

    def wchan(pid) = read_file("/proc/#{pid}/wchan").to_s.strip[0, 39]

    def security_context(pid) = read_file("/proc/#{pid}/attr/current").to_s.strip.delete("\0")

    def cgroup_lines(pid) = read_lines("/proc/#{pid}/cgroup").to_a

    # get_process_name(): the comm is truncated to 15 characters, so prefer
    # the basename of argv[0] (or argv[1], for `interpreter /path/script`)
    # when it starts with the comm — that recovers the full name.
    def process_name(comm, arguments)
      arguments.first(2).lazy.map { |argument| File.basename(argument) }
               .find { |basename| basename.start_with?(comm) }
               .then { |basename| basename || comm }
    end

    # gsm_cgroups_get_name(): one entry per distinct cgroup path, each
    # followed by its controllers in brackets. Paths that are empty or "/"
    # say nothing and are dropped, and a "name=" prefix is noise.
    def cgroup_name(pid)
      cgroup_lines(pid).each_with_object({}) do |line, paths|
        line.chomp.split(":", 3).then do |(_hierarchy, controllers, path)|
          if path && !path.empty? && path != "/"
            paths[path] = (paths[path] || []) + controllers.to_s.split(",")
                                                           .map { |name| name.delete_prefix("name=") }
                                                           .reject(&:empty?)
          end
        end
      end.sort.map { |path, controllers| format_cgroup(path, controllers.sort) }.join(", ")
    end

    def format_cgroup(path, controllers)
      if controllers.empty?
        path
      else
        "#{path} (#{controllers.join(', ')})"
      end
    end

    # sd_pid_get_unit()/sd_pid_get_session(): both are read off the systemd
    # cgroup path, which is where systemd records them.
    def systemd_unit(pid)
      unified_cgroup_path(pid).to_s.split("/").reverse
                              .find { |part| part.match?(/\.(service|scope|slice|socket|mount|swap|timer|path)\z/) }
                              .to_s
    end

    def systemd_session(pid)
      unified_cgroup_path(pid).to_s[%r{/session-([^/.]+)\.scope}, 1].to_s
    end

    # The unified hierarchy line ("0::/path"), which is the one systemd owns
    # on any system new enough to have this app's target desktop.
    def unified_cgroup_path(pid)
      cgroup_lines(pid).find { |line| line.start_with?("0::") }&.chomp&.delete_prefix("0::")
    end

    # /run/systemd/sessions/<id> holds the seat and the owner of a session.
    def session_info(session_id)
      read_file("/run/systemd/sessions/#{session_id}").to_s.then do |text|
        {
          seat:  text[/^SEAT=(.*)$/, 1].to_s,
          owner: text[/^UID=(\d+)$/, 1]&.to_i,
        }
      end
    end

    def user_name(uid)
      @user_names ||= {}
      @user_names[uid] ||= lookup_user(uid)
    end

    # A uid with no passwd entry still has to show as something; upstream
    # falls back to the number.
    def lookup_user(uid)
      Etc.getpwuid(uid).name
    rescue ArgumentError, TypeError
      uid.to_s
    end
  end
end
