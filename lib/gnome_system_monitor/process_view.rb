# frozen_string_literal: true

require "adwaita"

require_relative "columns"
require_relative "list_refresh"
require_relative "i18n"
require_relative "process_table"
require_relative "settings"
require_relative "units"

module GnomeSystemMonitor
  # The Processes tab: a GtkColumnView over the ProcessTable.
  #
  # Upstream uses a GtkTreeView, whose per-column cell data functions turn a
  # raw number into the text in the cell. The equivalent here is a
  # SignalListItemFactory per column whose bind handler calls the same
  # formatter — Columns::DEFINITIONS names which one, so the two views agree
  # column for column.
  class ProcessView
    include Translations

    # The column titles that carry a running total under them, as upstream's
    # two-line column headers do. A GtkColumnView header is a plain label, so
    # the total goes on a second line of the title rather than in a widget of
    # its own.
    TOTAL_SEPARATOR = "\n"

    def initialize(table:, on_selection_changed:, on_context_menu:)
      @table = table
      @on_selection_changed = on_selection_changed
      @on_context_menu = on_context_menu
    end

    attr_reader :table, :on_selection_changed, :on_context_menu

    def build
      scrolled_window.tap do |sw|
        sw.child = column_view

        column_view.tap do |cv|
          cv.append_column(name_column)

          Columns.visible.each { |column| cv.append_column(column_widget(column)) }

          cv.model = selection
          cv.add_controller(context_gesture)

          context_gesture.signal_connect("pressed") do |_gesture, _n, x, y|
            on_context_menu.call(x, y)
          end
        end

        selection.signal_connect("selection-changed") { on_selection_changed.call }
        sorter_model.signal_connect("items-changed") { on_selection_changed.call }
      end

      restore_columns

      scrolled_window
    end

    # The rows the user has picked, as Process objects. A GtkTreeListRow wraps
    # each one when the dependency view is on, so unwrap before handing them
    # out.
    # GtkBitset holds the selected positions; get_nth walks them without
    # touching the rows in between, which matters with a few hundred
    # processes and one selected.
    def selected
      selection.selection.then do |bits|
        (0...bits.size).map { |nth| unwrap(selection.get_item(bits.get_nth(nth))) }
      end
    end

    def unwrap(item)
      case item
      when Gtk::TreeListRow then item.item
      else item
      end
    end

    # Render every showing column for every process, then put the totals under
    # the column titles. Called after every refresh of the table.
    #
    # The rendering happens here rather than in the cells because the cells
    # are bound to the row's text properties with a GtkExpression, which can
    # read a property but cannot call a formatter. Only the columns actually
    # on screen are rendered, so the default six columns cost six strings per
    # process per tick.
    def refresh_headers
      announce_rows(render_text)
      refresh_totals
    end

    # Returns the keys of the processes whose text actually moved, which is
    # what the view has to be told about.
    def render_text
      showing_columns.then do |columns|
        table.processes.each_value.select do |process|
          columns.count { |column| process.set_text(column.key, render(column, process)) }.positive?
        end.map(&:key).to_set
      end
    end

    def showing_columns
      Columns.visible.select { |column| column_widget(column).visible? }
    end

    # Tell the view which rows moved, so it binds them again — see ListRefresh
    # for why that is the only mechanism available.
    def announce_rows(keys)
      ListRefresh.announce(
        table.stores,
        keys,
        selection: selection,
        tree:      expandable_tree,
      )
    end

    # Only the dependency view has rows that can be expanded; the flat view
    # has no expansion to put back, so it is not worth walking for.
    def expandable_tree
      if Settings[Settings::SHOW_DEPENDENCIES]
        table.tree_model
      end
    end

    def refresh_totals
      table.totals.then do |totals|
        total_columns.each do |column, widget|
          widget.title = [column.title.call, total_text(column, totals)].join(TOTAL_SEPARATOR)
        end
      end
    end

    def total_text(column, totals)
      case column.render
      when :percentage then Units.percentage(totals.fetch(column.key))
      when :io_rate then Units.rate(totals.fetch(column.key), false)
      else Units.byte_size(totals.fetch(column.key), Settings[Settings::PROCESS_MEMORY_IN_IEC])
      end
    end

    # Column visibility, width and order come back from the same gschema keys
    # upstream writes, and go back into them whenever the user changes one.
    def restore_columns
      Columns.visible.each do |column|
        column_widget(column).tap do |widget|
          widget.visible = Settings.column_visible?(column.index)
          Settings.column_width(column.index).then do |width|
            if width.positive?
              widget.fixed_width = width
            end
          end
        end
      end

      restore_sort
    end

    def restore_sort
      Columns.all.find { |column| column.index == Settings.sort_column }.then do |column|
        if column
          column_view.sort_by_column(
            sortable_widget(column),
            Settings.sort_order.zero? ? :ascending : :descending,
          )
        end
      end
    end

    def sortable_widget(column)
      case column.key
      when :name then name_column
      else column_widget(column)
      end
    end

    def save_sort
      column_view.sorter.then do |sorter|
        sorter.primary_sort_column.then do |widget|
          widget_column(widget).then do |column|
            if column
              Settings.set_sort(column.index, sorter.primary_sort_order == :ascending ? 0 : 1)
            end
          end
        end
      end
    end

    def widget_column(widget)
      case widget
      when nil then nil
      when name_column then Columns.find(:name)
      else column_widgets.key(widget)
      end
    end

    def save_column_widths
      Columns.visible.each do |column|
        column_widget(column).then do |widget|
          if widget.visible? && widget.fixed_width.positive?
            Settings.set_column_width(column.index, widget.fixed_width)
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

    # tree, then search, then the sort the header clicks decide, then the
    # selection the view reads back.
    def sorter_model
      @sorter_model ||= Gtk::SortListModel.new(table.model, nil).tap do |model|
        model.sorter = Gtk::TreeListRowSorter.new(column_view.sorter)
      end
    end

    def selection = @selection ||= Gtk::MultiSelection.new(sorter_model)

    def context_gesture
      @context_gesture ||= Gtk::GestureClick.new.tap do |gesture|
        gesture.button = 3
      end
    end

    # The name column carries the icon and the tree expander, which is why it
    # is built by hand rather than from the table.
    def name_column
      @name_column ||= Gtk::ColumnViewColumn.new(Columns.find(:name).title.call, name_factory).tap do |column|
        column.resizable = true
        column.expand = true
        column.sorter = Gtk::StringSorter.new(Gtk::PropertyExpression.new(Process, nil, "name"))
      end
    end

    def name_factory
      @name_factory ||= Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect("setup") { |_f, item| setup_name(item) }
        factory.signal_connect("bind") { |_f, item| bind_name(item) }
      end
    end

    def setup_name(item)
      item.child = Gtk::TreeExpander.new.tap do |expander|
        expander.child = Gtk::Box.new(:horizontal, 6).tap do |box|
          box.append(Gtk::Image.new.tap { |image| image.icon_name = "application-x-executable-symbolic" })
          box.append(
            Gtk::Label.new.tap do |label|
                        label.xalign = 0
                        label.ellipsize = :end
                      end,
          )
        end
      end
    end

    # Everything the cell shows is written here and nothing is kept: a Ruby
    # reference to a list item or its child that outlives this callback
    # corrupts the heap under these bindings.
    def bind_name(item)
      item.item.then do |row|
        item.child.list_row = row

        item.child.child.last_child.tap do |label|
          label.label = row.item.name
          label.tooltip_text = row.item.tooltip
        end
      end
    end

    def column_widgets = @column_widgets ||= {}

    def column_widget(column)
      column_widgets[column] ||= build_column(column)
    end

    def total_columns
      @total_columns ||= Columns.visible.select(&:total).to_h { |column| [column, column_widget(column)] }
    end

    def build_column(column)
      Gtk::ColumnViewColumn.new(column.title.call, value_factory(column)).tap do |widget|
        widget.resizable = true
        widget.sorter = sorter_for(column)
      end
    end

    # A GtkStringSorter for the text columns and a GtkNumericSorter for the
    # rest, both reading the GObject property the row installs — so the
    # comparing happens in C and a changed value re-sorts the view by itself.
    def sorter_for(column)
      Gtk::PropertyExpression.new(Process, nil, Columns.sort_key(column).to_s).then do |expression|
        case column.type
        when :string then Gtk::StringSorter.new(expression)
        else Gtk::NumericSorter.new(expression)
        end
      end
    end

    def value_factory(column)
      Gtk::SignalListItemFactory.new.tap do |factory|
        factory.signal_connect("setup") { |_f, item| setup_value(item, column) }
        factory.signal_connect("bind") { |_f, item| bind_value(item, column) }
      end
    end

    def setup_value(item, column)
      item.child = Gtk::Label.new.tap do |label|
        label.xalign = alignment(column)
        label.ellipsize = :end

        if column.tnum
          label.attributes = tabular_figures
        end
      end
    end

    # render_text() has already worked out the string; this only has to put it
    # in the cell.
    def bind_value(item, column)
      item.child.label = unwrap(item.item).send(:"#{column.key}#{Process::TEXT_SUFFIX}")
    end

    # 1.0 is right-aligned, 0.0 left.
    def alignment(column)
      case column.align
      when :end then 1.0
      else 0.0
      end
    end

    # The cell data functions of util.cpp, one branch each.
    def render(column, process)
      process.send(Columns.sort_key(column)).then do |value|
        case column.render
        when :size_na then Units.size_or_na(value, Settings[Settings::PROCESS_MEMORY_IN_IEC])
        when :io_rate then Units.rate_or_na(value)
        when :percentage then Units.percentage(value)
        when :duration then Units.duration(value)
        when :time then Units.start_time(value)
        when :status then status_text(process.status)
        when :priority then Units.nice_level(value)
        else value.to_s
        end
      end
    end

    # format_process_state().
    def status_text(status)
      case status
      when ProcFs::RUNNING then _("Running")
      when ProcFs::STOPPED then _("Stopped")
      when ProcFs::ZOMBIE then _("Zombie")
      when ProcFs::UNINTERRUPTIBLE then _("Uninterruptible")
      else _("Sleeping")
      end
    end

    # make_tnum_attr_list(): tabular figures, so the digits in a column do not
    # jitter sideways as the numbers change.
    def tabular_figures
      @tabular_figures ||= Pango::AttrList.new.tap do |attributes|
        attributes.insert(Pango::AttrFontFeatures.new("tnum=1"))
      end
    end
  end
end
