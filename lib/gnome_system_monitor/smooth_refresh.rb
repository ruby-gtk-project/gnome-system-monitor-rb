# frozen_string_literal: true

require "gio2"

require_relative "proc_fs"
require_relative "settings"
require_relative "system_stats"

module GnomeSystemMonitor
  # smooth_refresh.cpp: stretches the process list's refresh interval so that
  # System Monitor is not itself the busiest thing on the machine.
  #
  # The fuzzy logic is upstream's, thresholds and all: the interval only grows
  # when this process has been over PCPU_HI two ticks running, and only shrinks
  # when it has been under PCPU_LO two ticks running, so a single spike either
  # way changes nothing. The result is held between the configured interval and
  # twice it, which is what keeps the smoothing from running away.
  #
  # Upstream reads its own CPU time through glibtop; this reads /proc/self/stat
  # and /proc/stat, which is where glibtop reads them from. Both are in clock
  # ticks, so the ratio between them is the same percentage upstream computes.
  class SmoothRefresh
    # update_interval.h, in milliseconds.
    MIN_UPDATE_INTERVAL = 1 * 1000
    MAX_UPDATE_INTERVAL = 100 * 1000

    # Percentages of one CPU: above HI the interval grows, below LO it
    # shrinks, and between the two it is left alone.
    PCPU_HI = 22
    PCPU_LO = 18

    # The switch behind "Enable Smooth Refresh": with it off, get() never
    # proposes a new interval and the list ticks at whatever the preferences
    # say.
    KEY = Settings::SMOOTH_REFRESH

    def initialize
      @active = Settings.settings.get_boolean(KEY)

      Settings.settings.signal_connect("changed::#{KEY}") do
        @active = Settings.settings.get_boolean(KEY)
      end

      reset
    end

    attr_reader :interval

    def active? = @active

    # Drops the accumulated state and re-reads the configured interval. Called
    # when the preferences change, since the interval it had settled on is
    # measured against the old configured one.
    def reset
      @interval = config_interval
      @last_pcpu = PCPU_LO
      @last_total_time = total_cpu_time
      @last_cpu_time = own_cpu_time
    end

    # The new interval in milliseconds, or nil when it has not moved — which
    # is upstream's boolean return and its out-parameter in one value.
    def get
      if active?
        advance
      end
    end

    def advance
      own_cpu_usage.then do |pcpu|
        next_interval(pcpu, config_interval).then do |candidate|
          @last_pcpu = pcpu

          if candidate == interval
            nil
          else
            @interval = candidate
          end
        end
      end
    end

    # a) over the high mark twice running — the interval is too short, so
    #    lengthen it by a tenth;
    # b) under the low mark twice running, and already stretched — shorten it
    #    by a tenth, back towards what was configured;
    # c) anything else — leave it where it is.
    def next_interval(pcpu, configured)
      case
      when pcpu > PCPU_HI && @last_pcpu > PCPU_HI
        interval * 11 / 10
      when interval != configured && pcpu < PCPU_LO && @last_pcpu < PCPU_LO
        interval * 9 / 10
      else
        interval
      end.clamp(configured, configured * 2).clamp(MIN_UPDATE_INTERVAL, MAX_UPDATE_INTERVAL)
    end

    # What share of one CPU this process has had since the last call. With no
    # time elapsed there is nothing to divide by, and upstream's answer to that
    # is the low threshold — a reading that on its own moves nothing.
    def own_cpu_usage
      elapsed_cpu_time.then do |elapsed|
        if elapsed.positive?
          usage_over(elapsed)
        else
          PCPU_LO
        end
      end
    end

    def elapsed_cpu_time
      total_cpu_time.then do |total|
        (total - @last_total_time).tap { @last_total_time = total }
      end
    end

    def usage_over(elapsed)
      own_cpu_time.then do |own|
        ((own - @last_cpu_time) * 100 / elapsed).clamp(0, 100).tap { @last_cpu_time = own }
      end
    end

    # /proc/stat's aggregate line: every tick every CPU has spent, which is
    # what glibtop's cpu.total carries.
    def total_cpu_time = SystemStats.cpu_times.first.total

    # utime + stime for this process, in those same ticks.
    def own_cpu_time
      ProcFs.process(::Process.pid).then do |stat|
        stat ? stat[:utime] + stat[:stime] : 0
      end
    end

    # The interval the preferences ask for, in milliseconds. The smoothed
    # interval is never shorter than this.
    def config_interval = Settings.settings.get_int(Settings::UPDATE_INTERVAL)
  end
end
