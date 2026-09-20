# frozen_string_literal: true

require_relative "detail_view"
require_relative "i18n"
require_relative "proc_files"
require_relative "settings"
require_relative "units"

module GnomeSystemMonitor
  # The three list windows, each a DetailView with its own columns and its own
  # source: memmaps.ui, openfiles.ui and lsof.ui.
  module DetailWindows
    include Translations
    extend Translations

    # memmaps.ui. The addresses are shown as the 16-digit hex that
    # /proc/PID/smaps prints them as, and sort on the number.
    def memory_maps
      DetailView.new(
        type_name: "GsmMemoryMapRow",
        columns:   memory_map_columns,
        title:     ->(process) { process_title(process) },
        fetch:     ->(process) { process ? memory_map_rows(process) : [] },
      )
    end

    def process_title(process)
      if process
        format(_("%<name>s (PID %<pid>u)"), name: process.name, pid: process.pid)
      else
        ""
      end
    end

    # memmaps.ui renders the addresses as 16-digit hex and the counters as
    # sizes; both sort on the number behind the text.
    def memory_map_columns
      address = ->(value) { format("%016x", value) }
      size = ->(value) { Units.byte_size(value, Settings[Settings::PROCESS_MEMORY_IN_IEC]) }

      [
        DetailView::Column.new(
          :filename,
          _("Filename"),
          :string,
          :start,
          true,
          nil,
        ),
        # virtual memory start
        DetailView::Column.new(
          :vm_start,
          _("VM Start"),
          :uint64,
          :end,
          false,
          address,
        ),
        # virtual memory end
        DetailView::Column.new(
          :vm_end,
          _("VM End"),
          :uint64,
          :end,
          false,
          address,
        ),
        # virtual memory syze
        DetailView::Column.new(
          :vm_size,
          _("VM Size"),
          :uint64,
          :end,
          false,
          size,
        ),
        DetailView::Column.new(
          :flags,
          _("Flags"),
          :string,
          :start,
          false,
          nil,
        ),
        # virtual memory offset
        DetailView::Column.new(
          :vm_offset,
          _("VM Offset"),
          :uint64,
          :end,
          false,
          address,
        ),
        # memory that has not been modified since it has been allocated
        DetailView::Column.new(
          :private_clean,
          _("Private Clean"),
          :uint64,
          :end,
          false,
          size,
        ),
        # memory that has been modified since it has been allocated
        DetailView::Column.new(
          :private_dirty,
          _("Private Dirty"),
          :uint64,
          :end,
          false,
          size,
        ),
        # shared memory that has not been modified since it has been allocated
        DetailView::Column.new(
          :shared_clean,
          _("Shared Clean"),
          :uint64,
          :end,
          false,
          size,
        ),
        # shared memory that has been modified since it has been allocated
        DetailView::Column.new(
          :shared_dirty,
          _("Shared Dirty"),
          :uint64,
          :end,
          false,
          size,
        ),
        DetailView::Column.new(
          :device,
          _("Device"),
          :string,
          :start,
          false,
          nil,
        ),
        DetailView::Column.new(
          :inode,
          _("Inode"),
          :uint64,
          :end,
          false,
          nil,
        ),
      ]
    end

    def memory_map_rows(process)
      ProcFiles.maps(process.pid).map do |map|
        map.to_h
      end
    end

    # openfiles.ui.
    def open_files
      DetailView.new(
        type_name: "GsmOpenFileRow",
        columns:   [
          # FD here means File Descriptor. Use a short translation if
          # possible, and at most 2-3 characters
          DetailView::Column.new(
            :fd,
            _("FD"),
            :uint,
            :end,
            false,
            nil,
          ),
          DetailView::Column.new(
            :type,
            _("Type"),
            :string,
            :start,
            false,
            nil,
          ),
          DetailView::Column.new(
            :object,
            _("Object"),
            :string,
            :start,
            true,
            nil,
          ),
        ],
        title:     ->(process) { process_title(process) },
        fetch:     ->(process) { process ? ProcFiles.open_files(process.pid).map(&:to_h) : [] },
      )
    end

    module_function :memory_maps, :memory_map_columns, :memory_map_rows, :open_files, :process_title
  end

  # lsof.ui: the same table, over every process, with a search box above it.
  class SearchOpenFiles
    include Translations

    def build
      view.build.tap do |win|
        view.toolbar_view.add_top_bar(search_bar)

        search_bar.tap do |bar|
          bar.child = search_box
          bar.search_mode_enabled = true

          search_box.tap do |box|
            box.append(entry)
            box.append(case_check)

            entry.signal_connect("search-changed") { view.refresh }
            case_check.signal_connect("toggled") { view.refresh }
          end
        end
      end
    end

    def present(parent)
      build
      view.window.transient_for = parent
      view.window.present
      entry.grab_focus
    end

    def update = view.update

    def view
      @view ||= DetailView.new(
        type_name: "GsmSearchResultRow",
        columns:   [
          DetailView::Column.new(
            :process,
            _("Process"),
            :string,
            :start,
            false,
            nil,
          ),
          DetailView::Column.new(
            :pid,
            _("PID"),
            :uint,
            :end,
            false,
            nil,
          ),
          DetailView::Column.new(
            :filename,
            _("Filename"),
            :string,
            :start,
            true,
            nil,
          ),
        ],
        # Window title for Search for Open Files dialog
        title:     ->(_target) { _("Search for Open Files") },
        fetch:     ->(_target) { results },
      )
    end

    # An empty box searches nothing: matching every open file on the machine
    # would be a very long list and a very slow one.
    def results
      entry.text.then do |text|
        if text.empty?
          []
        else
          ProcFiles.search(text, case_check.active?).map(&:to_h)
        end
      end
    end

    def search_bar = @search_bar ||= Gtk::SearchBar.new

    def search_box
      @search_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
        box.margin_start = 6
        box.margin_end = 6
      end
    end

    def entry
      @entry ||= Gtk::SearchEntry.new.tap do |e|
        e.width_request = 300
      end
    end

    def case_check = @case_check ||= Gtk::CheckButton.new(_("Case Insensitive"))
  end
end
