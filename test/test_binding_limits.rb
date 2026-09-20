# frozen_string_literal: true

# The three obvious ways to keep a GtkColumnView's cells up to date are, under
# these Ruby bindings, memory-corruption bugs. This is the reproducer, and the
# guard on the one way that works — which is why the process table renders the
# way it does (see lib/gnome_system_monitor/list_refresh.rb).
#
# Run with a variant name to drive one of them by hand:
#
#   safe    set the cell's text inside the bind callback and keep nothing
#   label   keep the cell's label to re-render it later
#   item    keep the list item to re-render it later
#   expr    bind the label with gtk_expression_bind, as upstream's .ui files do
#
# The churn is the same in all four: rows leaving and rejoining the model
# while their values change, which is what a process table does every tick.
# `safe` survives it; the other three segfault, usually within a few hundred
# rounds. Only `safe` is asserted here, because a crash that takes a few
# seconds to arrive is not something to hang a test result on — the other
# three are reported for information.

require "tmpdir"

VARIANT = ARGV[0]

if VARIANT
  $LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
  require "gnome_system_monitor/row"

  ROUNDS = 120
  ROWS = 200

  R = GnomeSystemMonitor::Row.define("GsmBindingLimits", name: :string, text: :string)

  rows = ROWS.times.map { |i| R.new.tap { |row| row.assign(name: "row#{i}", text: "t#{i}") } }
  store = Gio::ListStore.new(R)
  rows.each { |row| store.append(row) }

  tree = Gtk::TreeListModel.new(store, false, false) { |_item| nil }
  view = Gtk::ColumnView.new(Gtk::MultiSelection.new(Gtk::SortListModel.new(tree, nil)))
  kept = {}

  def expression
    Gtk::PropertyExpression.new(
      R,
      Gtk::PropertyExpression.new(
        Gtk::TreeListRow,
        Gtk::PropertyExpression.new(Gtk::ListItem, nil, "item"),
        "item",
      ),
      "text",
    )
  end

  3.times do
    factory = Gtk::SignalListItemFactory.new.tap do |f|
      f.signal_connect("setup") do |_f, item|
        item.child = Gtk::Label.new

        if VARIANT == "expr"
          expression.bind(item.child, "label", item)
        end
      end

      f.signal_connect("bind") do |_f, item|
        item.item.item.then do |row|
          item.child.label = row.text

          case VARIANT
          when "label" then kept[item.child] = -> { item.child.label = row.text }
          when "item" then kept[item.child] = -> { item.child.label = item.item.item.text }
          end
        end
      end

      f.signal_connect("unbind") { |_f, item| kept.delete(item.child) }
    end

    view.append_column(Gtk::ColumnViewColumn.new("c", factory))
  end

  app = Gtk::Application.new("org.gnome.SystemMonitor.BindingLimits", Gio::ApplicationFlags::NON_UNIQUE)
  round = 0

  app.signal_connect("activate") do
    Gtk::ApplicationWindow.new(app).tap do |window|
      window.set_default_size(800, 600)
      window.child = Gtk::ScrolledWindow.new.tap { |scrolled| scrolled.child = view }
      window.present
    end

    GLib::Timeout.add(20) do
      store.remove_all
      rows.each_with_index do |row, i|
        if round.even? || i.even?
          store.append(row)
        end
      end

      rows.each_with_index { |row, i| row.assign(text: "t#{i}-#{round}") }
      kept.each_value(&:call)
      round += 1

      if round > ROUNDS
        puts("survived")
        app.quit
        false
      else
        true
      end
    end
  end

  app.run([$PROGRAM_NAME])
else
  def run(variant)
    IO.popen(
      [RbConfig.ruby, __FILE__, variant, { err: File::NULL }],
      "r",
      unsetenv_others: false,
    ) { |io| io.read.to_s.include?("survived") }
  end

  def check(what)
    if yield
      puts("    ok   #{what}")
    else
      puts("    FAIL #{what}")
      @failed = true
    end
  end

  ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir
  ENV["GSETTINGS_BACKEND"] = "memory"
  ENV.delete("DISPLAY")
  ENV.delete("WAYLAND_DISPLAY")

  check("filling the cell inside bind and keeping nothing survives churn") { run("safe") }

  %w[label item expr].each do |variant|
    if run(variant)
      puts("    note #{variant} survived this run; it does not always")
    else
      puts("    note #{variant} crashed, as expected")
    end
  end

  exit(@failed ? 1 : 0)
end
