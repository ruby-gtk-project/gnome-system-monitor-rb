# frozen_string_literal: true

require_relative "i18n"
require_relative "paths"
require_relative "proc_fs"

module GnomeSystemMonitor
  # Sending a signal, changing a priority, setting an affinity — and, when the
  # process belongs to someone else, asking polkit to do it instead.
  #
  # This is gsm-actions.c: try it directly first, and only on a permission
  # error fall back to running the matching helper under pkexec. The helpers
  # are the three scripts in bin/, and the polkit actions that authorise them
  # are upstream's, unchanged.
  module Actions
    include Translations
    extend Translations

    SIGNALS = {
      stop: "STOP",
      cont: "CONT",
      term: "TERM",
      kill: "KILL",
    }.freeze

    Failure = Struct.new(:heading, :message)

    module_function

    # nil when it worked, a Failure to put in front of the user when it did
    # not.
    def send_signal(pid, name)
      ::Process.kill(SIGNALS.fetch(name), pid)
      nil
    rescue Errno::EPERM, Errno::EACCES
      elevate(["gsm-kill", "-s", signal_number(name).to_s, pid.to_s], _("Cannot Kill Process"), _("Kill helper failed"))
    rescue SystemCallError => e
      Failure.new(_("Cannot Kill Process"), e.message)
    end

    def signal_number(name) = Signal.list.fetch(SIGNALS.fetch(name))

    def set_priority(pid, priority)
      ::Process.setpriority(::Process::PRIO_PROCESS, pid, priority)
      nil
    rescue Errno::EPERM, Errno::EACCES
      elevate(
        ["gsm-renice", priority.to_s, pid.to_s],
        _("Cannot Change Priority"),
        _("Priority helper failed"),
      )
    rescue SystemCallError => e
      Failure.new(_("Cannot Change Priority"), e.message)
    end

    # taskset does the work here as it does upstream, since there is no
    # sched_setaffinity in Ruby's standard library and taskset is already a
    # dependency of the privileged path.
    def set_affinity(pid, cpus, child_threads)
      ["-pc#{child_threads ? 'a' : ''}", cpus.join(","), pid.to_s].then do |arguments|
        if run(["taskset", *arguments])
          nil
        else
          elevate(["gsm-taskset", *arguments], _("GNU CPU Affinity error"), _("Affinity helper failed"))
        end
      end
    end

    # /proc/PID/status spells the current mask out as a list, e.g. "0-2,7".
    def affinity(pid)
      ProcFs.read_file("/proc/#{pid}/status").to_s[/^Cpus_allowed_list:\s+(\S+)/, 1].to_s.split(",")
            .flat_map { |part| expand_range(part) }
    end

    def expand_range(part)
      part.split("-").map(&:to_i).then do |(first, last)|
        (first..(last || first)).to_a
      end
    end

    # gsm_pkexec_create_root_password_dialog(): pkexec with its own agent
    # disabled, so the desktop's authentication dialog is the one that shows.
    def elevate(command, heading, message)
      if run(["pkexec", "--disable-internal-agent", helper_path(command.first), *command.drop(1)])
        nil
      else
        Failure.new(heading, message)
      end
    end

    # Installed next to the app's own executable, which is where the polkit
    # policy says the privileged helpers live.
    def helper_path(name) = File.join(Paths.bin_dir, name)

    def run(command)
      system(*command, out: File::NULL, err: File::NULL)
    end
  end
end
