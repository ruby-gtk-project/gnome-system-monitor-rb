# frozen_string_literal: true

require "glib2"

require_relative "i18n"

module GnomeSystemMonitor
  # The number formatting upstream keeps in util.cpp. Sizes go through GLib's
  # own g_format_size so the units, the rounding and the localised decimal
  # separator all match the C app exactly.
  module Units
    include Translations
    extend Translations
    module_function

    # A dash, not "0 bytes": the columns use it for "nothing to report".
    NA = "—"

    DAY = 60 * 60 * 24

    # format_byte_size(): IEC (KiB) or SI (kB), the memory columns' choice.
    def byte_size(size, iec)
      if iec
        GLib.format_size(size, flags: GLib::FormatSizeFlags::IEC_UNITS)
      else
        GLib.format_size(size, flags: GLib::FormatSizeFlags::DEFAULT)
      end
    end

    # procman::format_size(): bits are the byte count times eight, and
    # everything else is IEC. Network and disk volumes use this one.
    def size(size, bits)
      if bits
        GLib.format_size(size * 8, flags: GLib::FormatSizeFlags::BITS)
      else
        GLib.format_size(size, flags: GLib::FormatSizeFlags::IEC_UNITS)
      end
    end

    def volume(bytes, bits) = size(bytes, bits)

    # xgettext: rate, 10MiB/s or 10Mbit/s
    def rate(bytes_per_second, bits) = format(_("%s/s"), size(bytes_per_second, bits))

    # A size column that shows the dash rather than a zero.
    def size_or_na(bytes, iec)
      if bytes.zero?
        NA
      else
        byte_size(bytes, iec)
      end
    end

    def rate_or_na(bytes_per_second)
      if bytes_per_second.zero?
        NA
      else
        rate(bytes_per_second, false)
      end
    end

    # procman::format_duration_for_display(), in centiseconds. The units
    # collapse to the two largest that are non-zero.
    def duration(centiseconds)
      seconds, centiseconds = centiseconds.divmod(100)
      minutes, seconds = seconds.divmod(60)
      hours, minutes = minutes.divmod(60)
      days, hours = hours.divmod(24)
      weeks, days = days.divmod(7)

      case
      when weeks.positive?
        # xgettext: weeks, days
        format(_("%<weeks>uw%<days>ud"), weeks: weeks, days: days)
      when days.positive?
        # xgettext: days, hours (0 -> 23)
        format(_("%<days>ud%<hours>02uh"), days: days, hours: hours)
      when hours.positive?
        # xgettext: hours (0 -> 23), minutes, seconds
        format(_("%<hours>u:%<minutes>02u:%<seconds>02u"), hours: hours, minutes: minutes, seconds: seconds)
      else
        # xgettext: minutes, seconds, centiseconds
        format(
          _("%<minutes>u:%<seconds>02u.%<centiseconds>02u"),
          minutes:      minutes,
          seconds:      seconds,
          centiseconds: centiseconds,
        )
      end
    end

    # procman::get_nice_level(): the five buckets the priority column shows.
    def nice_level(nice)
      case
      when nice < -7 then _("Very High")
      when nice < -2 then _("High")
      when nice < 3 then _("Normal")
      when nice < 7 then _("Low")
      else _("Very Low")
      end
    end

    # The same buckets, worded for the renice dialog's label.
    def nice_level_with_priority(nice)
      case
      when nice < -7 then _("Very High Priority")
      when nice < -2 then _("High Priority")
      when nice < 3 then _("Normal Priority")
      when nice < 7 then _("Low Priority")
      else _("Very Low Priority")
      end
    end

    def percentage(value) = format("%.1f%%", value)

    # procman_format_date_for_display(): today and yesterday get named, the
    # rest of the last week gets its weekday, and older than that gets a date.
    # The literal ∶ is U+2236, as upstream — not a colon.
    def start_time(unix_time)
      case
      when unix_time.zero?
        # xgettext: ? stands for unknown
        _("?")
      else
        Time.at(unix_time).then { |then_| filter_date(then_, Time.now) }
      end
    end

    def filter_date(then_, now)
      case
      when same_day?(then_, now)
        then_.strftime(_("Today %l∶%M %p"))
      when same_day?(then_, now - DAY)
        then_.strftime(_("Yesterday %l∶%M %p"))
      when (2..6).any? { |days| same_day?(then_, now - (DAY * days)) }
        then_.strftime(_("%a %l∶%M %p"))
      when then_.year == now.year
        then_.strftime(_("%b %d %l∶%M %p"))
      else
        then_.strftime(_("%b %d %Y"))
      end
    end

    def same_day?(a, b) = a.day == b.day && a.month == b.month && a.year == b.year
  end
end
