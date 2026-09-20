# frozen_string_literal: true

require "adwaita"

require_relative "i18n"
require_relative "list_refresh"
require_relative "row"

module GnomeSystemMonitor
  # The shared shape of the three list windows — Memory Maps, Open Files and
  # Search for Open Files. Each is a titled window holding a sortable
  # GtkColumnView over a flat list that is refreshed wholesale.
  #
  # Upstream has three separate widgets for this; they differ only in their
  # columns and where their rows come from, which is what this takes as
  # arguments.
  class DetailView
    include Translations

    # `format` turns the stored value into the text the cell shows; its result
    # lands in a string property of its own, because the GtkExpression that
    # keeps a cell live can read a property but cannot call a formatter.
    Column = Struct.new(
      :key,
      :title,
      :type,
      :align,
      :expand,
      :format,
    )

    TEXT_SUFFIX = "_text"

    # `fetch` is given the current target and returns the rows to show, so
    # one view can be pointed at a different process and reused rather than
    # rebuilt. `title` is given the target too.
    def initialize(type_name:, columns:, title:, fetch:)
      @title = title
      @columns = columns
      @fetch = fetch
      @row_class = Row.define(type_name, row_fields(columns))
    end

    attr_reader :title, :columns, :fetch, :row_class
    attr_accessor :target

    # One property per column to sort on, plus a string one to show for the
    # columns whose text is not simply the value.
    def row_fields(columns)
      columns.each_with_object({}) do |column, fields|
        fields[column.key] = column.type

        if column.type != :string
          fields[:"#{column.key}#{TEXT_SUFFIX}"] = :string
        end
      end
    end

    def build
      window.tap do |win|
        win.title = title.call(target)
        win.content = toolbar_view

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = scrolled_window
        end

        scrolled_window.child = column_view

        column_view.tap do |cv|
          columns.each { |column| cv.append_column(column_widget(column)) }
          cv.model = selection
        end
      end

      refresh
      window
    end

    # Reopening points the same window at a new process rather than building
    # another one. Every window built means another few hundred widgets and
    # row objects for the garbage collector to dispose of later, and disposing
    # of GObjects from Ruby's GC while the main loop is running is exactly
    # what this port has found ruby-gnome to be fragile about.
    def present(parent, target)
      self.target = target
      build
      window.title = title.call(target)
      refresh
      window.transient_for = parent
      window.present
    end

    def store = @store ||= Gio::ListStore.new(row_class)

    # The rows are held here as well as in the store, and that is not
    # redundant: a row's values live in Ruby instance variables, and the store
    # only holds a reference to the underlying GObject. Drop the Ruby
    # reference and the wrapper is collected, then rebuilt blank the next time
    # anything reads it — which shows up as a table full of empty cells.
    def rows = @rows ||= []

    # The window list refreshes every detail window on the process tick; for
    # these that just means re-reading the list.
    def update = refresh

    # A row is filled in before it reaches the store, because GtkListView
    # binds a row the moment it is appended and would otherwise show the
    # blank one. Changes after that reach the cells through their
    # expressions.
    def refresh
      fetch.call(target).then do |records|
        records.each_with_index { |record, index| write_row(record, index) }
        drop_rows_beyond(records.length)
        ListRefresh.announce_all([store], selection: selection)
      end
    end

    # The rows leave the store but not the pool: a Row is a GObject, and
    # freeing a few hundred of them every time a list shortens is churn this
    # view does not need. The pool settles at the longest list it has shown.
    def drop_rows_beyond(length)
      (store.n_items - 1).downto(length) { |index| store.remove(index) }
    end

    def write_row(record, index)
      row_at(index).assign(record.merge(text_for(record)))

      if index >= store.n_items
        store.append(rows[index])
      end
    end

    def text_for(record)
      columns.each_with_object({}) do |column, text|
        if column.type != :string
          record[column.key].then do |value|
            if column.format
              text[:"#{column.key}#{TEXT_SUFFIX}"] = column.format.call(value)
            else
              text[:"#{column.key}#{TEXT_SUFFIX}"] = value.to_s
            end
          end
        end
      end
    end

    def row_at(index) = rows[index] ||= row_class.new

    # Widgets
    def window
      @window ||= Adwaita::Window.new.tap do |win|
        win.set_default_size(700, 500)
      end
    end

    def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
    def header_bar = @header_bar ||= Adwaita::HeaderBar.new

    def scrolled_window
      @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |sw|
        sw.hexpand = true
        sw.vexpand = true
      end
    end

    def column_view
      @column_view ||= Gtk::ColumnView.new(nil).tap do |cv|
        cv.show_column_separators = true
        cv.add_css_class("data-table")
      end
    end

    def sorter_model
      @sorter_model ||= Gtk::SortListModel.new(store, nil).tap do |model|
        model.sorter = column_view.sorter
      end
    end

    def selection = @selection ||= Gtk::SingleSelection.new(sorter_model)

    def column_widget(column)
      Gtk::ColumnViewColumn.new(column.title, factory_for(column)).tap do |widget|
        widget.resizable = true
        widget.expand = column.expand
        widget.sorter = sorter_for(column)
      end
    end

    def sorter_for(column)
      Gtk::PropertyExpression.new(row_class, nil, column.key.to_s).then do |expression|
        case column.type
        when :string then Gtk::StringSorter.new(expression)
        else Gtk::NumericSorter.new(expression)
        end
      end
    end

    def factory_for(column)
      Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect("setup") do |_f, item|
          item.child = Gtk::Label.new.tap do |label|
            label.xalign = alignment(column)
            label.ellipsize = :end
            label.attributes = tabular_figures
          end
        end

        factory.signal_connect("bind") do |_f, item|
          item.child.label = item.item.send(display_property(column))
        end
      end
    end

    # 1.0 is right-aligned, 0.0 left.
    def alignment(column)
      case column.align
      when :end then 1.0
      else 0.0
      end
    end

    def display_property(column)
      case column.type
      when :string then column.key.to_s
      else "#{column.key}#{TEXT_SUFFIX}"
      end
    end

    def tabular_figures
      @tabular_figures ||= Pango::AttrList.new.tap do |attributes|
        attributes.insert(Pango::AttrFontFeatures.new("tnum=1"))
      end
    end
  end
end
