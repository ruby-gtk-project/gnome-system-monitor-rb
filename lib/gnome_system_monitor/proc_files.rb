# frozen_string_literal: true

require "ipaddr"
require "socket"

require_relative "i18n"
require_relative "proc_fs"

module GnomeSystemMonitor
  # The per-process detail behind the Memory Maps, Open Files and Search for
  # Open Files dialogs.
  #
  # Upstream reads these through libgtop's proc_map and open_files; both are
  # /proc readers on Linux, so this reads /proc/PID/smaps and /proc/PID/fd
  # directly.
  module ProcFiles
    include Translations
    extend Translations

    Map = Struct.new(
      :filename,
      :vm_start,
      :vm_end,
      :vm_size,
      :flags,
      :vm_offset,
      :private_clean,
      :private_dirty,
      :shared_clean,
      :shared_dirty,
      :device,
      :inode,
    )

    OpenFile = Struct.new(:fd, :type, :object)

    # The smaps counters this reads, in kB.
    COUNTERS = {
      "Private_Clean" => :private_clean,
      "Private_Dirty" => :private_dirty,
      "Shared_Clean"  => :shared_clean,
      "Shared_Dirty"  => :shared_dirty,
    }.freeze

    module_function

    # /proc/PID/smaps: a header line per mapping, then that mapping's
    # counters, until the next header.
    def maps(pid)
      [].tap do |maps|
        ProcFs.read_lines("/proc/#{pid}/smaps").to_a.each do |line|
          parse_map_header(line).then do |map|
            if map
              maps << map
            else
              add_counter(maps.last, line)
            end
          end
        end
      end
    end

    # "7f2c0a000000-7f2c0a021000 r-xp 00000000 fd:00 1234  /usr/lib/libc.so"
    MAP_HEADER = /\A(\h+)-(\h+) (\S{4}) (\h+) (\S+) (\d+)\s*(.*)\z/

    def parse_map_header(line)
      MAP_HEADER.match(line.chomp)&.then do |match|
        Map.new(
          match[7],
          match[1].to_i(16),
          match[2].to_i(16),
          match[2].to_i(16) - match[1].to_i(16),
          match[3],
          match[4].to_i(16),
          0,
          0,
          0,
          0,
          match[5],
          match[6].to_i,
        )
      end
    end

    def add_counter(map, line)
      if map
        line.split(/:\s+/).then do |(key, value)|
          COUNTERS[key].then do |field|
            if field
              map[field] = value.to_i * 1024
            end
          end
        end
      end
    end

    # /proc/PID/fd: one symlink per descriptor, pointing at the file, socket
    # or pipe it holds open.
    def open_files(pid)
      Dir.children("/proc/#{pid}/fd").sort_by(&:to_i).filter_map do |fd|
        describe_fd(pid, fd)
      end
    rescue SystemCallError
      []
    end

    SOCKET_LINK = /\Asocket:\[(\d+)\]\z/
    PIPE_LINK = /\Apipe:\[\d+\]\z/
    ANON_LINK = /\Aanon_inode:(.*)\z/

    # The match data is pulled out before anything else is called: gettext
    # runs regexps of its own, so `$~` cannot be relied on across a `_()`.
    def describe_fd(pid, fd)
      File.readlink("/proc/#{pid}/fd/#{fd}").then do |target|
        case
        when SOCKET_LINK.match(target) then socket_file(fd, SOCKET_LINK.match(target)[1].to_i)
        when PIPE_LINK.match?(target) then OpenFile.new(fd.to_i, _("pipe"), target)
        when ANON_LINK.match(target) then anon_file(fd, ANON_LINK.match(target)[1])
        else OpenFile.new(fd.to_i, _("file"), target)
        end
      end
    rescue SystemCallError
      nil
    end

    def socket_file(fd, inode)
      socket_description(inode).then do |(type, object)|
        OpenFile.new(fd.to_i, type, object)
      end
    end

    def anon_file(fd, description) = OpenFile.new(fd.to_i, _("unknown type"), description)

    # The socket's inode is the key into /proc/net; which table it turns up in
    # says what kind of socket it is.
    def socket_description(inode)
      unix_sockets[inode].then do |path|
        if path
          [_("local socket"), path]
        else
          inet_socket_description(inode)
        end
      end
    end

    def inet_socket_description(inode)
      inet_sockets[inode].then do |socket|
        case socket
        when nil then [_("unknown type"), ""]
        when ->(s) { s[:family] == :inet6 } then [_("IPv6 network connection"), tcp_description(socket)]
        else [_("IPv4 network connection"), tcp_description(socket)]
        end
      end
    end

    # friendlier_hostname(): upstream resolves the peer's name and the port's
    # service name. The name lookup is left out here — it is a blocking DNS
    # round trip on the UI thread — but the service name comes from
    # /etc/services, which costs nothing.
    def tcp_description(socket)
      service_name(socket[:port]).then do |service|
        if service
          format(
            "%s, TCP port %d (%s)",
            socket[:address],
            socket[:port],
            service,
          )
        else
          format("%s, TCP port %d", socket[:address], socket[:port])
        end
      end
    end

    def service_name(port)
      Socket.getservbyport(port, "tcp")
    rescue SocketError, StandardError
      nil
    end

    # /proc/net/unix: the inode is the seventh field and the path, when the
    # socket has one, is the eighth.
    def unix_sockets
      refresh_socket_tables
      @unix_sockets
    end

    def inet_sockets
      refresh_socket_tables
      @inet_sockets
    end

    # The tables are shared by every descriptor of every process in one pass,
    # so they are parsed once and held for a moment rather than per lookup.
    CACHE_SECONDS = 1.0

    def refresh_socket_tables
      ::Process.clock_gettime(::Process::CLOCK_MONOTONIC).then do |now|
        if @tables_read_at.nil? || now - @tables_read_at > CACHE_SECONDS
          @tables_read_at = now
          @unix_sockets = read_unix_sockets
          @inet_sockets = read_inet_sockets
        end
      end
    end

    def read_unix_sockets
      ProcFs.read_lines("/proc/net/unix").to_a.drop(1).each_with_object({}) do |line, table|
        line.split.then do |fields|
          if fields.length >= 8
            table[fields[6].to_i] = fields[7]
          end
        end
      end
    end

    def read_inet_sockets
      {
        "/proc/net/tcp"  => :inet,
        "/proc/net/tcp6" => :inet6,
        "/proc/net/udp"  => :inet,
        "/proc/net/udp6" => :inet6,
      }.each_with_object({}) do |(path, family), table|
        ProcFs.read_lines(path).to_a.drop(1).each do |line|
          parse_inet_line(line, family).then do |entry|
            if entry
              table[entry[:inode]] = entry
            end
          end
        end
      end
    end

    # "sl local_address rem_address st ... inode", the addresses being
    # hex, little-endian and colon-separated from the port.
    def parse_inet_line(line, family)
      line.split.then do |fields|
        if fields.length > 9
          fields[2].split(":").then do |(address, port)|
            {
              inode:   fields[9].to_i,
              family:  family,
              address: decode_address(address, family),
              port:    port.to_i(16),
            }
          end
        end
      end
    end

    # The kernel prints each 32-bit word of the address in host byte order, so
    # every group of eight hex digits is reversed byte by byte.
    def decode_address(hex, family)
      hex.scan(/\h{8}/).flat_map { |word| [word].pack("H8").unpack("C4").reverse }.then do |bytes|
        case family
        when :inet6 then IPAddr.new(bytes.pack("C16").unpack1("H32").scan(/\h{4}/).join(":")).to_s
        else bytes.join(".")
        end
      end
    rescue StandardError
      hex
    end

    # Search for Open Files: every process's open files, filtered by name.
    def search(pattern, case_insensitive)
      build_search_regexp(pattern, case_insensitive).then do |regexp|
        ProcFs.pids.flat_map { |pid| search_one(pid, regexp) }
      end
    end

    def build_search_regexp(pattern, case_insensitive)
      Regexp.new(pattern, case_insensitive ? Regexp::IGNORECASE : 0)
    rescue RegexpError
      Regexp.new(Regexp.escape(pattern), case_insensitive ? Regexp::IGNORECASE : 0)
    end

    Match = Struct.new(:process, :pid, :filename)

    def search_one(pid, regexp)
      open_files(pid).select { |file| regexp.match?(file.object.to_s) }.then do |matches|
        if matches.empty?
          []
        else
          process_name(pid).then do |name|
            matches.map { |file| Match.new(name, pid, file.object) }
          end
        end
      end
    end

    def process_name(pid)
      ProcFs.stat(pid).then do |stat|
        if stat
          ProcFs.process_name(stat[:comm], ProcFs.cmdline(pid))
        else
          ""
        end
      end
    end
  end
end
