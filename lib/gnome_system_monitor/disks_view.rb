# frozen_string_literal: true

require "adwaita"

require_relative "i18n"
require_relative "list_refresh"
require_relative "settings"
require_relative "system_stats"
require_relative "units"

module GnomeSystemMonitor
  # One mounted filesystem, as a row of the File Systems tab.
  #
  # The same reasoning as Process: GtkColumnView sorts on GObject properties,
  # so the fields the columns sort on are installed as properties. Upstream's
  # GsmDisk carries exactly these.
  class Disk < GLib::Object
    type_register

    PROPERTIES = {
      "device"    => :string,
      "directory" => :string,
      "type"      => :string,
      "total"     => :uint64,
      "free"      => :uint64,
      "available" => :uint64,
      "used"      => :uint64,
      "perc"      => :int,
    }.freeze

    # What each size column shows. The columns sort on the byte counts above
    # and the cells bind to these, because the GtkExpression that keeps a cell
    # live can read a property but cannot call a formatter.
    TEXT_PROPERTIES = %w[total_text free_text available_text used_text perc_text].freeze

    TEXT_PROPERTIES.each do |name|
      attr_accessor name.to_sym

      install_property(
        GLib::Param::String.new(
          name,
          name,
          name,
          "",
          GLib::Param::READWRITE,
        ),
      )
    end

    PROPERTIES.each do |name, kind|
      attr_accessor name.to_sym

      case kind
      when :string
        install_property(
          GLib::Param::String.new(
            name,
            name,
            name,
            "",
            GLib::Param::READWRITE,
          ),
        )
      when :int
        install_property(
          GLib::Param::Int.new(
            name,
            name,
            name,
            0,
            100,
            0,
            GLib::Param::READWRITE,
          ),
        )
      else
        install_property(
          GLib::Param::UInt64.new(
            name,
            name,
            name,
            0,
            2**63 - 1,
            0,
            GLib::Param::READWRITE,
          ),
        )
      end
    end

    def initialize
      super
      @device = ""
      @directory = ""
      @type = ""
      @total = 0
      @free = 0
      @available = 0
      @used = 0
      @perc = 0
      TEXT_PROPERTIES.each { |name| send(:"#{name}=", "") }
    end

    # What identifies this row across a refresh.
    def key = directory

    def set_text(name, text)
      if send(name) != text
        send(:"#{name}=", text)
        notify(name)
      end
    end

    # Named `perc` as a property because `percentage` collides with nothing
    # but reads better in the column table; the column still says Used.
    def update(mount)
      {
        device:    mount.device,
        directory: mount.directory,
        type:      mount.type,
        total:     mount.total,
        free:      mount.free,
        available: mount.available,
        used:      mount.used,
        perc:      mount.percentage,
      }.each do |key, value|
        if send(key) != value
          send(:"#{key}=", value)
          notify(key.to_s)
        end
      end
    end
  end

  # The File Systems tab.
  class DisksView
    include Translations

    Column = Struct.new(
      :id,
      :title,
      :type,
      :render,
      :expand,
    )

    # disks.ui's columns, in its order. The settings keys are named after the
    # id rather than numbered, which is how the disksview schema stores them.
    def columns
      @columns ||= [
        Column.new(
          "device",
          _("Device"),
          :string,
          :text,
          true,
        ),
        Column.new(
          "directory",
          _("Directory"),
          :string,
          :text,
          false,
        ),
        Column.new(
          "type",
          _("Type"),
          :string,
          :text,
          false,
        ),
        Column.new(
          "total",
          _("Total"),
          :uint64,
          :size,
          false,
        ),
        Column.new(
          "free",
          _("Free"),
          :uint64,
          :size,
          false,
        ),
        Column.new(
          "available",
          _("Available"),
          :uint64,
          :size,
          false,
        ),
        Column.new(
          "used",
          _("Used"),
          :uint64,
          :usage,
          false,
        ),
      ]
    end

    def build
      scrolled_window.tap do |sw|
        sw.child = column_view

        column_view.tap do |cv|
          columns.each { |column| cv.append_column(column_widget(column)) }
          cv.model = selection
        end
      end

      restore_columns
      refresh
      scrolled_window
    end

    def disks = @disks ||= {}

    def store = @store ||= Gio::ListStore.new(Disk)

    # A row is keyed by its mount point, so a filesystem that is still mounted
    # keeps its row — and its place in the sort — across a refresh.
    def refresh
      SystemStats.mounts(Settings[Settings::SHOW_ALL_FS]).then do |mounts|
        mounts.to_h { |mount| [mount.directory, mount] }.then do |wanted|
          remove_unmounted(wanted)
          update_mounted(wanted)
          render_text
          ListRefresh.announce_all([store], selection: selection)
        end
      end
    end

    def remove_unmounted(wanted)
      (store.n_items - 1).downto(0) do |index|
        store.get_item(index).directory.then do |directory|
          if !wanted.key?(directory)
            store.remove(index)
            disks.delete(directory)
          end
        end
      end
    end

    def update_mounted(wanted)
      wanted.each do |directory, mount|
        disks[directory].then do |disk|
          if disk
            disk.update(mount)
          else
            Disk.new.tap do |fresh|
              fresh.update(mount)
              disks[directory] = fresh
              store.append(fresh)
            end
          end
        end
      end
    end

    # The size columns' text, rendered once per refresh into the properties
    # the cells are bound to.
    def render_text
      Settings[Settings::RESOURCES_MEMORY_IN_IEC].then do |iec|
        disks.each_value do |disk|
          %i[total free available used].each do |key|
            disk.set_text("#{key}_text", Units.byte_size(disk.send(key), iec))
          end

          disk.set_text("perc_text", format("%i%%", disk.perc))
        end
      end
    end

    def restore_columns
      columns.each do |column|
        column_widget(column).tap do |widget|
          widget.visible = Settings.disks_column_visible?(column.id)
          Settings.disks_column_width(column.id).then do |width|
            if width.positive?
              widget.fixed_width = width
            end
          end
        end
      end

      restore_sort
    end

    def restore_sort
      columns.find { |column| column.id == Settings.disksview.get_string("sort-col") }.then do |column|
        if column
          column_view.sort_by_column(
            column_widget(column),
            Settings.disksview.get_int("sort-order").zero? ? :ascending : :descending,
          )
        end
      end
    end

    def save_sort
      column_view.sorter.primary_sort_column.then do |widget|
        column_widgets.key(widget).then do |column|
          if column
            Settings.disksview.set_string("sort-col", column.id)
            Settings.disksview.set_int(
              "sort-order",
              column_view.sorter.primary_sort_order == :ascending ? 0 : 1,
            )
          end
        end
      end
    end

    def save_column_widths
      columns.each do |column|
        column_widget(column).then do |widget|
          if widget.visible? && widget.fixed_width.positive?
            Settings.set_disks_column_width(column.id, widget.fixed_width)
          end
        end
      end
    end

    # Widgets
    def scrolled_window
      @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |sw|
        sw.hexpand = true
        sw.vexpand = true
        sw.margin_bottom = 12
        sw.margin_start = 12
        sw.margin_end = 12
      end
    end

    def column_view
      @column_view ||= Gtk::ColumnView.new(nil).tap do |cv|
        cv.show_column_separators = true
        cv.reorderable = true
        cv.add_css_class("data-table")
      end
    end

    def sorter_model
      @sorter_model ||= Gtk::SortListModel.new(store, nil).tap do |model|
        model.sorter = column_view.sorter
      end
    end

    def selection = @selection ||= Gtk::SingleSelection.new(sorter_model)

    def column_widgets = @column_widgets ||= {}

    def column_widget(column) = column_widgets[column] ||= build_column(column)

    def build_column(column)
      Gtk::ColumnViewColumn.new(column.title, factory_for(column)).tap do |widget|
        widget.resizable = true
        widget.expand = column.expand
        widget.sorter = sorter_for(column)
      end
    end

    def sorter_for(column)
      Gtk::PropertyExpression.new(Disk, nil, column.id).then do |expression|
        case column.type
        when :string then Gtk::StringSorter.new(expression)
        else Gtk::NumericSorter.new(expression)
        end
      end
    end

    def factory_for(column)
      case column.render
      when :usage then usage_factory
      else text_factory(column)
      end
    end

    def text_factory(column)
      Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect("setup") do |_f, item|
          item.child = Gtk::Label.new.tap do |label|
            label.xalign = alignment(column)
            label.ellipsize = :end
          end
        end

        factory.signal_connect("bind") do |_f, item|
          item.child.label = item.item.send(display_property(column))
        end
      end
    end

    # The size columns are right-aligned, the rest left.
    def alignment(column)
      case column.render
      when :size then 1.0
      else 0.0
      end
    end

    # A text column shows its own value; a size column shows the string that
    # render_text put beside it.
    def display_property(column)
      case column.render
      when :size then "#{column.id}_text"
      else column.id
      end
    end

    # The Used column is a size, a percentage and a bar showing the same
    # fraction, exactly as disks.ui lays it out.
    def usage_factory
      @usage_factory ||= Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect("setup") { |_f, item| setup_usage(item) }
        factory.signal_connect("bind") { |_f, item| bind_usage(item) }
      end
    end

    def setup_usage(item)
      item.child = Gtk::Box.new(:vertical, 6).tap do |box|
        box.valign = :center

        box.append(
          Gtk::Box.new(:horizontal, 0).tap do |line|
                    line.hexpand = true
                    line.append(
                      Gtk::Label.new.tap do |label|
                                  label.hexpand = true
                                  label.halign = :start
                                  label.width_chars = 15
                                  label.xalign = 0
                                end,
                    )
                    line.append(
                      Gtk::Label.new.tap do |label|
                                  label.halign = :end
                                  label.hexpand = true
                                  label.width_chars = 5
                                  label.xalign = 1
                                end,
                    )
                  end,
        )

        box.append(
          Gtk::LevelBar.new.tap do |bar|
                    bar.hexpand = true
                    bar.valign = :center
                    bar.min_value = 0
                    bar.max_value = 100
                  end,
        )
      end
    end

    def bind_usage(item)
      item.item.then do |disk|
        item.child.first_child.tap do |line|
          line.first_child.label = disk.used_text
          line.last_child.label = disk.perc_text
        end

        item.child.last_child.value = disk.perc
      end
    end
  end
end
