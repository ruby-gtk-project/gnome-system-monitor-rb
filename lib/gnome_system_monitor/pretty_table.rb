# frozen_string_literal: true

require "adwaita"

require_relative "proc_fs"

module GnomeSystemMonitor
  # prettytable.cpp: the icon that sits next to a process in the process
  # table.
  #
  # The lookup order is upstream's — the installed application that owns the
  # executable, then the icon theme under the process's own name, then the
  # table of well-known commands from defaulttable.h, then the kernel-thread
  # icon, and finally a plain executable icon so every row has something.
  #
  # Upstream resolves each candidate all the way to a Gdk::Texture, because
  # GtkCellView cannot draw a GdkPaintable and so cannot take a themed icon;
  # its own comment says a GtkColumnView would not need that. This port is a
  # GtkColumnView, so a candidate is resolved only as far as a Gio::Icon and
  # the cell's GtkImage does the drawing — which also means a theme that
  # changes under us redraws rather than having to be re-rasterised.
  class PrettyTable
    # The size upstream rasterises a process icon at, and so the size the
    # cell's image asks the theme for.
    APP_ICON_SIZE = 16

    # The icon every row falls back to.
    FALLBACK_ICON = "application-x-executable"

    # has_kthreadd(): on Linux PID 2 is kthreadd, and then every kernel thread
    # is either it or one of its children.
    KTHREADD_PID = 2

    # Executables too generic to identify an application by: a .desktop file
    # whose Exec is a shell or env says nothing about which process is which.
    GENERIC_EXECUTABLES = %w[sh env].freeze

    # The group every key of a desktop entry lives in.
    DESKTOP_GROUP = "Desktop Entry"

    # defaulttable.h: icons for well-known commands that ship no .desktop
    # file of their own. Upstream anchors each pattern with ^(...)$, so these
    # match the whole process name and nothing less.
    DEFAULT_TABLE = [
      # GNOME services
      [/\A(?:.*applet(-?2)?|gnome-panel)\z/, "gnome-panel"],
      [/\A(?:evolution.*)\z/, "emblem-mail"],
      [/\A(?:gconfd-2|dconf-service)\z/, "preferences-desktop"],
      [/\A(?:metacity|gnome-shell)\z/, "gnome-window-manager"],
      [/\A(?:vino.*)\z/, "gnome-remote-desktop"],
      # Other processes
      [/\A(?:(ba|z|tc|c|k)?sh)\z/, "utilities-terminal"],
      [/\A(?:(k|sys|u)logd|logger)\z/, "internet-news-reader"],
      [/\A(?:X(org)?)\z/, "display"],
      [/\A(?:apache2?|httpd|lighttpd)\z/, "internet-web-browser"],
      [/\A(?:atd|cron|CRON|ntpd)\z/, "date"],
      [/\A(?:cupsd|lpd?)\z/, "printer"],
      [/\A(?:cvsd|mtn|git|svn)\z/, "file-manager"],
      [/\A(?:emacs(server|\d+)?)\z/, "gnome-emacs"],
      [/\A(?:famd|gam_server)\z/, "file-manager"],
      [/\A(?:getty)\z/, "input-keyboard"],
      [/\A(?:gdb|((gcc|g\+\+)(-.*)?)|ar|ld|make)\z/, "applications-development"],
      [/\A(?:sendmail|exim\d?)\z/, "internet-mail"],
      [/\A(?:squid)\z/, "proxy"],
      [/\A(?:ssh(d|-agent))\z/, "ssh-askpass-gnome"],
      [/\A(?:top|vmstat)\z/, "system-monitor"],
      [/\A(?:vim?)\z/, "vim"],
      [/\A(?:x?inetd)\z/, "internet-web-browser"],
    ].freeze

    def initialize
      @gio_apps = {}
      @defaults = {}
      @monitors = {}
      @kthreadd = ProcFs.stat(KTHREADD_PID)&.fetch(:comm) == "kthreadd"

      refresh_app_cache
      watch_desktop_directories
    end

    attr_reader :gio_apps, :defaults, :monitors

    def kthreadd? = @kthreadd

    # set_icon(): the first candidate that resolves wins, and a candidate that
    # raises is skipped rather than taking the refresh down with it — a
    # malformed .desktop file or a broken theme entry is upstream's reason for
    # the same try/catch.
    def set_icon(process)
      process.icon = candidates.lazy.filter_map { |getter| resolve(getter, process) }.first
    end

    # The theme decides what a name resolves to, so a theme change invalidates
    # every cached answer.
    def forget
      defaults.clear
      @icon_theme = nil
    end

    # get_icon_from_theme and get_icon_from_name are the same lookup twice in
    # upstream's list, so the name is tried once here. The kernel-thread icon
    # is only worth trying when kthreadd is actually running.
    def candidates
      @candidates ||= [
        :icon_from_gio,
        :icon_from_theme,
        :icon_from_default,
      ] + (kthreadd? ? [:icon_for_kernel] : []) + [:icon_dummy]
    end

    def resolve(getter, process)
      send(getter, process)
    rescue StandardError => e
      warn("Failed to load icon for #{process.name}(#{process.pid}): #{e.message}")
      nil
    end

    # get_icon_from_gio(): the .desktop file that owns this executable, or the
    # flatpak whose app id the process's cgroup carries.
    def icon_from_gio(process)
      app_info_for(process)&.icon
    end

    def app_info_for(process)
      gio_apps[executable_of(process)] || gio_apps[flatpak_id_of(process)]
    end

    # A process name can carry arguments; the executable is what comes before
    # the first space.
    def executable_of(process) = process.name.to_s.split(" ").first.to_s

    # Extract a flatpak app id from the cgroup's last path component. systemd
    # names a flatpak's scope "app-flatpak-<app id>-<pid>.scope", so the id is
    # the component between the last two dashes — too few dashes and this is
    # not a flatpak scope at all.
    def flatpak_id_of(process)
      process.cgroup_name.to_s.split("/").last.to_s.split("-").then do |parts|
        if parts.length >= 3
          parts[-2]
        end
      end
    end

    # get_icon_from_theme()/get_icon_from_name(): the process name taken as an
    # icon name.
    def icon_from_theme(process) = themed_icon(process.name)

    # get_icon_from_default(): the defaulttable.h match, remembered by icon
    # name — including when it did not resolve, so a miss is looked up once
    # rather than once per process.
    def icon_from_default(process)
      default_icon_name(process.name)&.then do |name|
        if defaults.key?(name)
          defaults[name]
        else
          defaults[name] = themed_icon(name)
        end
      end
    end

    def default_icon_name(command)
      DEFAULT_TABLE.find { |(pattern, _icon)| pattern.match?(command.to_s) }&.last
    end

    # get_icon_for_kernel(): kthreadd and its children all show the plain
    # executable icon, since none of them is an application.
    def icon_for_kernel(process)
      if process.pid == KTHREADD_PID || process.ppid == KTHREADD_PID
        Gio::ThemedIcon.new(FALLBACK_ICON)
      end
    end

    # get_icon_dummy(): the last resort, and so the one candidate that is not
    # allowed to come back empty.
    def icon_dummy(_process) = Gio::ThemedIcon.new(FALLBACK_ICON)

    # A themed icon only if the theme actually has it: handing the cell a name
    # nothing resolves would show a broken-image icon rather than falling
    # through to the next candidate.
    def themed_icon(name)
      if !name.to_s.empty? && icon_theme&.has_icon?(name)
        Gio::ThemedIcon.new(name)
      end
    end

    # Resolved lazily and only once there is a display: the table is built
    # before the window is, and there is no icon theme before then.
    def icon_theme
      @icon_theme ||= Gdk::Display.default&.then do |display|
        Gtk::IconTheme.get_for_display(display)
      end
    end

    # init_gio_app_cache(): every installed application indexed by the
    # executable name that will turn up in /proc, and flatpaks by their app id
    # instead — a flatpak's executable is the sandbox launcher, which is the
    # same for all of them.
    def refresh_app_cache
      @gio_apps = Gio::AppInfo.all.each_with_object({}) do |app, cache|
        flatpak_id(app).then do |flatpak|
          if flatpak
            cache[flatpak] = app
          else
            index_by_executable(cache, app)
          end
        end
      end
    end

    def index_by_executable(cache, app)
      app.executable.to_s.then do |executable|
        if !executable.empty? && !GENERIC_EXECUTABLES.include?(executable) && app.should_show
          cache[executable] = app
        end
      end
    end

    # X-Flatpak carries the app id of the flatpak a desktop entry was exported
    # from, and is on no other entry.
    #
    # Upstream reads it off the GDesktopAppInfo, which ruby-gnome does not
    # bind get_string on, so it is read out of the desktop file instead — the
    # same gap the Junction port works around for the desktop actions. An
    # entry without the key, or without a file behind it at all, is not a
    # flatpak.
    def flatpak_id(app)
      desktop_key(app, "X-Flatpak")
    end

    def desktop_key(app, key)
      app.filename.then do |filename|
        if filename
          key_file(filename).get_string(DESKTOP_GROUP, key).then do |value|
            value.to_s.empty? ? nil : value
          end
        end
      end
    rescue StandardError
      nil
    end

    def key_file(filename)
      GLib::KeyFile.new.tap { |file| file.load_from_file(filename, :none) }
    end

    # file_monitor_event(): applications come and go while the monitor runs,
    # so every applications directory is watched and the cache rebuilt rather
    # than left to go stale. The rate limit is upstream's one second, which
    # keeps a package install from rebuilding the cache once per file.
    def watch_desktop_directories
      desktop_directories.each { |path| watch(path) }
    end

    def watch(path)
      Gio::File.new_for_path(path).monitor_directory(:none).tap do |monitor|
        monitor.rate_limit = 1000
        monitor.signal_connect("changed") { refresh_app_cache }
        monitors[path] = monitor
      end
    rescue StandardError => e
      warn("Could not watch #{path} for application changes: #{e.message}")
    end

    def desktop_directories
      GLib.system_data_dirs.map { |dir| File.join(dir, "applications") }
    end
  end
end
