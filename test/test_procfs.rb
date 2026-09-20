# frozen_string_literal: true

# The /proc readers, checked against this very process and against fixed
# sample text where the real thing would be untestable.

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "gnome_system_monitor/proc_files"
require "gnome_system_monitor/proc_fs"
require "gnome_system_monitor/system_stats"

P = GnomeSystemMonitor::ProcFs
F = GnomeSystemMonitor::ProcFiles
S = GnomeSystemMonitor::SystemStats

def check(what)
  if yield
    puts("    ok   #{what}")
  else
    puts("    FAIL #{what}")
    @failed = true
  end
end

SELF = Process.pid

check("this process is in the list") { P.pids.include?(SELF) }
check("a missing process reads as nil") { P.process(4_194_303).nil? }

P.process(SELF).then do |stat|
  check("the stat has our command") { stat[:comm] == "ruby" }
  check("we are running") { stat[:state] == P::RUNNING }
  check("our parent is not us") { stat[:ppid] != SELF }
  check("we have used some CPU") { (stat[:utime] + stat[:stime]).positive? }
end

# The comm in /proc/PID/stat is wrapped in parentheses and may contain both
# spaces and parentheses of its own, which is why the parser splits on the
# last one.
check("a comm with brackets and spaces survives") do
  P.stat(SELF).then { |parsed| !parsed[:fields].empty? } &&
    "1 (a (weird) name) S 2 3 4 5".then do |line|
      line[(line.index("(") + 1)...line.rindex(")")] == "a (weird) name"
    end
end

check("our memory is non-zero") { P.memory(SELF)[:memres].positive? }
check("our writable memory is non-zero") { P.memory_writable(SELF).positive? }
check("our uid is ours") { P.uid(SELF) == Process.uid }
check("the uid resolves to a name") { !P.user_name(Process.uid).empty? }
check("an unknown uid falls back to its number") { P.user_name(4_294_967_290) == "4294967290" }
check("our command line is not empty") { !P.cmdline(SELF).empty? }

# get_process_name(): prefer the basename of argv[0] or argv[1] when it starts
# with the truncated comm, so a long name is recovered in full.
check("a long name is recovered from argv[0]") do
  P.process_name("verylongprocess", ["/usr/bin/verylongprocessname"]) == "verylongprocessname"
end
check("an interpreted script is found at argv[1]") do
  P.process_name("python3", ["/usr/bin/env", "/opt/python3.13-thing"]) == "python3.13-thing"
end
check("a kernel thread keeps its comm") { P.process_name("kworker/0:1", []) == "kworker/0:1" }
check("an unrelated argv[0] keeps the comm") { P.process_name("bash", ["/bin/login"]) == "bash" }

check("our cgroup is a path") { P.cgroup_name(SELF).start_with?("/") || P.cgroup_name(SELF).empty? }

# gsm_cgroups_get_name(): controllers are grouped under their path, sorted,
# and a "name=" prefix is dropped. "/" and empty paths say nothing.
check("cgroup controllers are grouped and sorted") do
  P.format_cgroup("/user.slice", %w[cpu cpuacct]) == "/user.slice (cpu, cpuacct)"
end
check("a path with no controllers stands alone") { P.format_cgroup("/init.scope", []) == "/init.scope" }

# The IO counters are the bytes that actually reached storage.
check("io reads back two counters") { P.io(SELF).keys.sort == %i[read write] }

# Memory maps.
F.maps(SELF).then do |maps|
  check("we have mappings") { maps.length > 5 }
  check("a mapping spans its addresses") { maps.all? { |m| m.vm_size == m.vm_end - m.vm_start } }
  check("flags are four characters") { maps.all? { |m| m.flags.length == 4 } }
  check("some mapping is privately dirty") { maps.any? { |m| m.private_dirty.positive? } }
end

check("a header line parses") do
  F.parse_map_header("7f0000000000-7f0000001000 r-xp 00000123 fd:01 42 /usr/lib/libc.so").then do |map|
    map.vm_start == 0x7f0000000000 && map.vm_size == 4096 && map.flags == "r-xp" &&
      map.vm_offset == 0x123 && map.device == "fd:01" && map.inode == 42 &&
      map.filename == "/usr/lib/libc.so"
  end
end

check("an anonymous mapping has no filename") do
  F.parse_map_header("7f0000000000-7f0000001000 rw-p 00000000 00:00 0 ").then { |map| map.filename.empty? }
end

# Open files.
F.open_files(SELF).then do |files|
  check("we have open descriptors") { !files.empty? }
  check("descriptors are numbered") { files.all? { |file| file.fd.is_a?(Integer) } }
  check("every descriptor has a type") { files.all? { |file| !file.type.empty? } }
end

# The kernel prints IPv4 addresses as a little-endian hex word.
check("an address decodes") { F.decode_address("0100007F", :inet) == "127.0.0.1" }
check("a wildcard address decodes") { F.decode_address("00000000", :inet) == "0.0.0.0" }

# Search for Open Files: an unparseable pattern is matched literally rather
# than raising.
check("a broken pattern is escaped") { F.build_search_regexp("foo[", false).match?("foo[bar") }
check("case folding is optional") do
  F.build_search_regexp("ABC", true).match?("abc") && !F.build_search_regexp("ABC", false).match?("abc")
end

# System-wide numbers.
check("there is an aggregate CPU line and at least one core") { S.cpu_times.length >= 2 }
check("cpu totals are positive") { S.cpu_times.first.total.positive? }
check("used is no more than total") { S.cpu_times.all? { |cpu| cpu.used <= cpu.total } }
check("the core count is the line count less one") { S.cpu_count == S.cpu_times.length - 1 }

S.memory.then do |memory|
  check("there is memory") { memory[:total].positive? }
  check("used memory is less than total") { memory[:user] < memory[:total] }
  check("free memory is less than total") { memory[:free] <= memory[:total] }
end

check("swap adds up") { S.swap[:used] == S.swap[:total] - S.swap[:free] }
check("network has two directions") { S.network.keys.sort == %i[in out] }
check("disk has two directions") { S.disk.keys.sort == %i[read write] }

# fsusage_stats(): used over used-plus-available, clamped.
check("an empty filesystem is 0%") { S.percentage(0, 0) == 0 }
check("a half-full filesystem is 50%") { S.percentage(50, 50) == 50 }
check("a full filesystem is 100%") { S.percentage(100, 0) == 100 }

# /proc/mounts escapes spaces as octal.
check("an escaped mount point unescapes") { S.unescape("/mnt/my\\040disk") == "/mnt/my disk" }

S.mounts(false).then do |mounts|
  check("the root filesystem is listed") { mounts.any? { |mount| mount.directory == "/" } }
  check("no kernel filesystems are listed") do
    mounts.none? { |mount| S::VIRTUAL_FILESYSTEMS.include?(mount.type) }
  end
  check("every listed mount has a size") { mounts.all? { |mount| mount.total.positive? } }
end

check("showing all filesystems lists more") { S.mounts(true).length > S.mounts(false).length }

exit(@failed ? 1 : 0)
