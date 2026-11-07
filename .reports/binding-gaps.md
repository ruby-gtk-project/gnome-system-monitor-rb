# Known ruby-gnome / environment binding gaps

## test/test_binding_limits.rb — no-display (headless) GTK init

`test_binding_limits.rb` forks a subprocess with `DISPLAY` and
`WAYLAND_DISPLAY` unset, on the documented assumption (see its own header
comment, and `test/gtk_driver.rb`'s module comment) that GTK4 falls back to
an offscreen/broadway surface with no display server running at all.

In this fork's nix devShell, that assumption does not hold: the `gtk4`
package nixpkgs builds here has no broadway/headless GDK backend compiled
in, so `Gtk.init` itself raises `Gtk::InitError: failed to initialize GTK`
before any port code runs, for every variant (`safe`, `label`, `item`,
`expr`) — confirmed by running `ruby test/test_binding_limits.rb safe`
directly with `env -u DISPLAY -u WAYLAND_DISPLAY` and by setting
`GDK_BACKEND=broadway` explicitly (same `Gtk::InitError`).

This is an environment/binding gap, not a port bug: the actual invariant the
test exists to check — that filling a `GtkColumnView` cell's label inside
the `bind` callback and keeping no Ruby reference to the cell survives churn
(the pattern `lib/gnome_system_monitor/list_refresh.rb` relies on) —
genuinely holds. Run the same script under a real (virtual) display instead
of none at all and it passes:

```
nix develop --command xvfb-run -a ruby test/test_binding_limits.rb safe
# => survived
```

`test/drive_window.rb`, the primary proof that the port runs, is driven the
way the task requires — `nix develop --command xvfb-run -a ruby
test/drive_window.rb` — and is unaffected by this gap.

## gio2's `Gio::SimpleAction#activate` hands a scalar GVariant parameter to
the signal handler already unwrapped

`window.rb`'s `priority_action` builds a `Gio::SimpleAction.new("priority",
GLib::VariantType.new("i"))` and reads the activated nice value off the
`"activate"` signal's `parameter` as `parameter.value` — treating it as a
`GLib::Variant`. Driving it (`test/drive_window.rb`, the renice-dialog step)
showed this was wrong: for a scalar type ("i" here), the gio2 binding already
unwraps the GVariant to a plain Ruby `Integer` before handing it to the
block, so `parameter.value` raised `NoMethodError: undefined method 'value'
for an instance of Integer` — for *every* activation of `win.priority`,
including the ones the process-list priority submenu sends from the real
UI, not only the renice-dialog sentinel this port added. This was a real
port bug, not a binding gap, and is fixed in this round by reading
`parameter` directly. Noted here because the wrong assumption (scalar
GVariant parameters arrive as `Variant`, not already-unwrapped) is easy to
make again anywhere else a `GVariant`-typed `SimpleAction` is activated with
a parameter.

A side-effect worth recording: this `NoMethodError`, raised inside a GObject
`"activate"` signal callback invoked synchronously from Ruby
(`action.activate(variant)`, not dispatched through the GLib main loop), did
**not** propagate back to the caller as a normal Ruby exception — `gtk_driver.rb`'s
`run_step` never printed its own `ERROR` line for it. Instead
gobject-introspection's loader printed the exception and backtrace itself
and the whole `ruby` process then exited (status 1), skipping every
remaining drive step. A broken signal handler under these bindings can
silently truncate a drive run rather than being caught and reported as one
failed step — worth knowing before trusting a partial step count from a run
that stopped early without a `DRIVE OK`/`DRIVE FAILED` line.

## CONFIRMED: `Gtk::StringSorter.new(expression)` / `Gtk::NumericSorter.new(expression)`
corrupt the heap under these bindings — pass the expression through the
property setter instead

`DetailView#sorter_for`, `DisksView#sorter_for` and `ProcessView#sorter_for`
all built a column's sorter as `Gtk::StringSorter.new(expression)` /
`Gtk::NumericSorter.new(expression)`, handing the `Gtk::PropertyExpression`
to the constructor. Every drive run logs

```
GLib-GObject-CRITICAL **: g_object_ref: assertion 'G_IS_OBJECT (object)' failed
	from .../gobject-introspection/loader.rb:378:in 'block (2 levels) in Gtk::StringSorter#initialize'
```

(and the same for `NumericSorter`) while building these sorters, on every
run, including on the unmodified baseline before this round's changes.
`GtkExpression` is a boxed ref-counted type, not a `GObject`, and this
binding's constructor-argument marshaling calls `g_object_ref` on it
regardless of that — the assertion fires, the proper ref is never taken,
and the sorter is left holding a `GtkExpression*` with the wrong lifetime.

That critical is not just noise: this round, driving the port further than
any previous pass (opening the renice/affinity/end-process dialogs, the
lsof search, the shortcuts and about dialogs, a column drag-reorder) made
it manifest as outright heap corruption — a `[BUG] Segmentation fault`,
sometimes immediately, sometimes several steps later and always inside
*unrelated* code (`pretty_table.rb`'s `Gtk::IconTheme#has_icon?` call, or
deep inside `Array#each`/`Enumerator` internals) — the classic symptom of a
crash site far from the actual corruption. It was not 100% reproducible run
to run (consistent with a dangling-pointer bug whose symptom depends on
what memory gets reused next), and the sandbox this was investigated in was
simultaneously running 20–30 other forks' GTK test suites, adding real
resource contention on top — but the same `g_object_ref` critical reproduces
in total isolation with no other process running, with a two-line repro:

```ruby
expr = Gtk::PropertyExpression.new(Gtk::Label, nil, "label")
Gtk::NumericSorter.new(expr)                 # logs the g_object_ref critical
```

against the confirmed, clean alternative:

```ruby
expr = Gtk::PropertyExpression.new(Gtk::Label, nil, "label")
Gtk::NumericSorter.new(nil).tap { |s| s.expression = expr }   # no critical
```

Passing the expression through the `expression=` property setter instead of
the constructor goes through a different marshaling path that does not make
the bad `g_object_ref` call. All three `sorter_for` methods are fixed this
round to build the sorter with `.new(nil)` and set `.expression =`
afterward. This is a real ruby-gnome/gobject-introspection binding defect
(constructor-argument marshaling for a boxed `GtkExpression` argument
incorrectly treated as an object needing `g_object_ref`), not a port
mistake, but it has a safe, behavior-preserving fix in the port's own code,
so it is fixed rather than only documented — same GObject symbol
(`g_object_ref`) and assertion (`G_IS_OBJECT (object)` failed) named here
per the task's "say so, name the exact symbol" guidance, for whoever hits
the same critical building a `GtkExpression`-based sorter elsewhere in this
fleet.
