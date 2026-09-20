# frozen_string_literal: true

require "gio2"

require_relative "proc_fs"

module GnomeSystemMonitor
  # The machine-wide numbers behind the Resources tab and the File Systems
  # tab. Upstream reads these through libgtop; the field names and the
  # arithmetic here are libgtop's, off /proc and statfs.
  module SystemStats
    # glibtop's linux/cpu.c totals the first seven fields of a /proc/stat cpu
    # line — steal and the guest columns are deliberately left out — and calls
    # user+nice+sys the used part.
    CPU_FIELDS = 7

    # glibtop_get_mountlist(all_fs = false) drops the kernel's own
    # filesystems. Without this the File Systems tab is a wall of cgroup
    # mounts.
    VIRTUAL_FILESYSTEMS = %w[
      autofs binfmt_misc bpf cgroup cgroup2 configfs debugfs devfs devpts
      devtmpfs efivarfs fuse.gvfs-fuse-daemon fuse.gvfsd-fuse fusectl
      gvfs-fuse-daemon hugetlbfs kernfs mqueue nfsd none proc pstore
      rpc_pipefs securityfs subfs sunrpc sysfs tracefs tmpfs ramfs
      binder bpffs nsfs overlay squashfs
    ].freeze

    # A unix sector is 512 bytes here regardless of the disk's own geometry,
    # which is the unit /proc/diskstats counts in.
    SECTOR_SIZE = 512

    Cpu = Struct.new(:total, :used)

    module_function

    # One Cpu per line of /proc/stat: index 0 is the aggregate, the rest are
    # the individual cores.
    def cpu_times
      ProcFs.read_lines("/proc/stat").to_a.select { |line| line.start_with?("cpu") }.map do |line|
        line.split[1, CPU_FIELDS].map(&:to_i).then do |fields|
          Cpu.new(fields.sum, fields[0] + fields[1] + fields[2])
        end
      end
    end

    def cpu_count = cpu_times.length - 1

    # glibtop_get_mem(): `user` is what the memory graph plots — the total
    # less everything the kernel can hand back on demand.
    def memory
      meminfo.then do |info|
        {
          total:  info["MemTotal"],
          free:   info["MemFree"],
          buffer: info["Buffers"],
          cached: info["Cached"] + info["SReclaimable"],
        }.then do |mem|
          mem.merge(user: mem[:total] - mem[:free] - mem[:cached] - mem[:buffer])
        end
      end
    end

    def swap
      meminfo.then do |info|
        info["SwapTotal"].then do |total|
          { total: total, free: info["SwapFree"], used: total - info["SwapFree"] }
        end
      end
    end

    # /proc/meminfo is in kB, and every key is read as a byte count.
    def meminfo
      ProcFs.read_lines("/proc/meminfo").to_a.each_with_object(Hash.new(0)) do |line, info|
        line.split(/:\s+/).then { |(key, value)| info[key] = value.to_i * 1024 }
      end
    end

    # get_net(): loopback never counts, and neither does an interface with no
    # address — but its counters are still remembered, so bringing it up does
    # not read as a spike.
    def network
      addressed_interfaces.then do |addressed|
        ProcFs.read_lines("/proc/net/dev").to_a.drop(2).each_with_object({ in: 0, out: 0 }) do |line, totals|
          line.split(":", 2).then do |(name, counters)|
            if addressed.include?(name.strip)
              counters.split.then do |fields|
                totals[:in] += fields[0].to_i
                totals[:out] += fields[8].to_i
              end
            end
          end
        end
      end
    end

    # The interfaces that hold an address, which is what libgtop checks the
    # netload flags for. A link-local IPv6 address alone does not count.
    def addressed_interfaces
      (ipv4_interfaces + ipv6_interfaces).to_set - ["lo"]
    end

    # /proc/net/route lists one line per route, so an interface with an IPv4
    # address appears at least once.
    def ipv4_interfaces
      ProcFs.read_lines("/proc/net/route").to_a.drop(1).map { |line| line.split.first }
    end

    # /proc/net/if_inet6 is address, index, prefix length, scope, flags, name.
    # Scope 20 is link-local, which get_net() skips.
    def ipv6_interfaces
      ProcFs.read_lines("/proc/net/if_inet6").to_a.filter_map do |line|
        line.split.then do |fields|
          if fields[3] != "20"
            fields[5]
          end
        end
      end
    end

    # get_disk(): whole disks only — counting partitions as well would count
    # the same bytes twice.
    def disk
      whole_disks.then do |disks|
        ProcFs.read_lines("/proc/diskstats").to_a.each_with_object({ read: 0, write: 0 }) do |line, totals|
          line.split.then do |fields|
            if disks.include?(fields[2])
              totals[:read] += fields[5].to_i * SECTOR_SIZE
              totals[:write] += fields[9].to_i * SECTOR_SIZE
            end
          end
        end
      end
    end

    # /sys/block holds exactly the whole disks; partitions live inside them.
    def whole_disks
      Dir.children("/sys/block").to_set
    rescue SystemCallError
      Set.new
    end

    Mount = Struct.new(
      :device,
      :directory,
      :type,
      :total,
      :free,
      :available,
      :used,
      :percentage,
    )

    # glibtop_get_mountlist() plus glibtop_get_fsusage() for each entry.
    # `show_all` keeps the kernel's own filesystems and the zero-sized
    # entries that disks.c otherwise drops.
    def mounts(show_all)
      mount_entries(show_all).filter_map { |entry| usage(entry, show_all) }
    end

    # /proc/mounts escapes spaces and tabs in the device and directory as
    # octal, and nothing else does that unescaping for us.
    def mount_entries(show_all)
      ProcFs.read_lines("/proc/mounts").to_a.filter_map do |line|
        line.split.then do |(device, directory, type)|
          if show_all || !VIRTUAL_FILESYSTEMS.include?(type)
            [unescape(device), unescape(directory), type]
          end
        end
      end
    end

    def unescape(field) = field.gsub(/\\(\d{3})/) { Regexp.last_match(1).to_i(8).chr }

    # GLib reports f_bavail as the free space and f_blocks - f_bfree as the
    # used space, which is the pair fsusage_stats() works from. A mount that
    # cannot be queried at all (a stale network mount, say) is dropped
    # rather than shown as zeroes.
    def usage(entry, show_all)
      filesystem_info(entry[1])&.then do |(total, available, used)|
        if total.zero? && !show_all
          nil
        else
          Mount.new(
            entry[0],
            entry[1],
            entry[2],
            total,
            total - used,
            available,
            used,
            percentage(used, available),
          )
        end
      end
    end

    def filesystem_info(directory)
      Gio::File.open(path: directory).query_filesystem_info("filesystem::*").then do |info|
        [
          info.get_attribute_uint64("filesystem::size"),
          info.get_attribute_uint64("filesystem::free"),
          info.get_attribute_uint64("filesystem::used"),
        ]
      end
    rescue StandardError
      nil
    end

    # fsusage_stats(): the bar is used over used-plus-available, not over the
    # total — the blocks reserved for root are nobody's to fill.
    def percentage(used, available)
      (used + available).then do |usable|
        if usable.zero?
          0
        else
          (100 * used / usable).clamp(0, 100)
        end
      end
    end
  end
end
