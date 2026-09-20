# frozen_string_literal: true

# The number formatting, which the columns, the graphs and the dialogs all
# read through. No widgets involved, so these run in milliseconds.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_system_monitor/units"

U = GnomeSystemMonitor::Units

# GLib separates a number from its unit with a non-breaking space in some
# locales and a plain one in others, and these run in whatever locale the
# machine has. The unit itself is what is being checked, not the spacing.
def same(actual, expected)
  actual.to_s.gsub("\u00A0", " ") == expected
end

def check(what)
  if yield
    puts("    ok   #{what}")
  else
    puts("    FAIL #{what}")
    @failed = true
  end
end

# format_byte_size(): IEC for the memory columns, SI otherwise.
check("1.5 KiB in IEC") { same(U.byte_size(1536, true), "1.5 KiB") }
check("1.5 kB in SI") { same(U.byte_size(1536, false), "1.5 kB") }
check("zero bytes") { same(U.byte_size(0, true), "0 bytes") }

# procman::format_size(): bits are eight times the bytes.
check("bits multiply by eight") { same(U.size(1536, true), "12.3 kbit") }
check("bytes stay IEC") { same(U.size(1536, false), "1.5 KiB") }
check("a rate has a per-second suffix") { U.rate(1536, false).end_with?("/s") }

# The dash the columns show instead of a zero.
check("a zero size is a dash") { U.size_or_na(0, true) == U::NA }
check("a non-zero size is not") { same(U.size_or_na(1024, true), "1.0 KiB") }
check("a zero rate is a dash") { U.rate_or_na(0) == U::NA }

# format_duration_for_display(), in centiseconds, collapsing to the two
# largest non-zero units.
check("under a minute") { U.duration(0) == "0:00.00" }
check("minutes and centiseconds") { U.duration(12_345) == "2:03.45" }
check("hours, minutes, seconds") { U.duration(1_234_567) == "3:25:45" }
check("days and hours") { U.duration(100 * 60 * 60 * 24 * 3) == "3d00h" }
check("weeks and days") { U.duration(100 * 60 * 60 * 24 * 10) == "1w3d" }

# procman::get_nice_level()'s five bands.
check("-20 is very high") { U.nice_level(-20) == "Very High" }
check("-5 is high") { U.nice_level(-5) == "High" }
check("0 is normal") { U.nice_level(0) == "Normal" }
check("5 is low") { U.nice_level(5) == "Low" }
check("19 is very low") { U.nice_level(19) == "Very Low" }
check("the renice dialog says Priority") { U.nice_level_with_priority(0) == "Normal Priority" }

# The band edges, which are < not <=.
check("-8 is still very high") { U.nice_level(-8) == "Very High" }
check("-7 has dropped to high") { U.nice_level(-7) == "High" }
check("2 is still normal") { U.nice_level(2) == "Normal" }
check("3 has dropped to low") { U.nice_level(3) == "Low" }

# procman_format_date_for_display().
check("an unknown start time is a question mark") { U.start_time(0) == "?" }
check("today is named") { U.start_time(Time.now.to_i).start_with?("Today") }
check("yesterday is named") { U.start_time(Time.now.to_i - 86_400).start_with?("Yesterday") }
# The exact shape is the locale's; what matters is that it is neither
# "Today" nor "Yesterday" and carries a month and a time.
check("a month ago is a date") do
  U.start_time(Time.now.to_i - (30 * 86_400)).then do |text|
    !text.start_with?("Today", "Yesterday") && text.match?(/\d/) && text.length > 5
  end
end

check("a percentage keeps one decimal") { U.percentage(12.34) == "12.3%" }

exit(@failed ? 1 : 0)
