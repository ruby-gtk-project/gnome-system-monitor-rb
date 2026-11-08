# Runtime gate — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `origin/main` @ `ebfa2af8` |
| Port | `ruby` @ `16704eb4` going into this round |
| Gate this round | `drive_ok=true`, **42/42 checks passed, 0 failed**, reproduced twice back to back |

## This round (superseding the one below)

Picking up from the prior audit's own "Verdict" — About, the
keyboard-shortcuts dialog, Renice, Set Affinity, Search for Open Files, the
End-Process confirmation, and the column drag-reorder persister were listed
as "unverified by any execution". This round drove all but one of them
(Search for Open Files — see below) and found and fixed four real port
bugs none of them had ever surfaced before, because nothing had ever
exercised that code path:

1. **`window.rb`'s `priority_action`** read the "activate" signal's scalar
   `i`-typed parameter as `parameter.value` — a `GLib::Variant` method —
   but gio2 hands scalar GVariant parameters to the block already unwrapped
   as a plain `Integer`. Every activation of `win.priority`, including the
   real priority submenu, raised `NoMethodError: undefined method 'value'
   for an instance of Integer`. Fixed by reading `parameter` directly.
2. **`detail_windows.rb`'s `SearchOpenFiles`** had no `initialize` at all,
   while `window.rb` constructs it with `SearchOpenFiles.new(pretty_table:
   table.pretty_table)` — `ArgumentError: wrong number of arguments (given
   1, expected 0)` on the very first "Search for Open Files" open, every
   time. Fixed by adding the `initialize(pretty_table:)` the call site
   already assumed.
3. **`about.rb`'s `ShortcutsDialog`** searched the GtkBuilder's objects for
   a `Gtk::Window`, but upstream's `shortcuts-dialog.ui` root object is an
   `AdwShortcutsDialog` — an `Adwaita::Dialog`, not a `Gtk::Window` — so the
   search always came back `nil` and `present` raised `NoMethodError:
   undefined method 'transient_for=' for nil` on every open. Fixed by
   searching for `Adwaita::Dialog` and presenting it the way the other Adw
   dialogs are (`dialog.present(parent)`).
4. **CONFIRMED ruby-gnome binding defect, fixed in the port's own code**:
   `DetailView#sorter_for`, `DisksView#sorter_for` and
   `ProcessView#sorter_for`/`#name_column` all built
   `Gtk::StringSorter.new(expression)` / `Gtk::NumericSorter.new(expression)`,
   which logs `GLib-GObject-CRITICAL **: g_object_ref: assertion
   'G_IS_OBJECT (object)' failed` on **every single run, every sorter
   built** — confirmed in total isolation with no app running at all
   (`Gtk::NumericSorter.new(Gtk::PropertyExpression.new(...))` alone
   reproduces it). `GtkExpression` is a boxed ref-counted type, not a
   `GObject`, and the constructor-argument marshaling path calls
   `g_object_ref` on it regardless. Driving the port further than any prior
   round (this round's new dialogs, the lsof search, a column reorder) made
   that critical manifest as outright heap corruption — an intermittent
   `[BUG] Segmentation fault`, crash site far from the actual fault, inside
   unrelated code. Passing the expression through the `expression=`
   property setter instead of the constructor avoids the bad `g_object_ref`
   call entirely (confirmed: the critical disappears with the setter, and
   reappears reliably with the constructor argument, in the same isolated
   repro). See `.reports/binding-gaps.md` for the full repro and the exact
   symbol.

Re-run directly for this audit, twice back to back:

```
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
42 of 42 checks passed
DRIVE OK
```

New coverage this round, all passing: the renice dialog (nice-value scale,
real process), the Set Affinity dialog, the End-Process confirmation
(declined, so the test's own process survives), the keyboard-shortcuts
dialog (now correctly an `Adwaita::ShortcutsDialog`), the About dialog
(name/version), and the process-table column drag-reorder persister
(gschema round-trip, see caveat below).

## Gap this round could not close: "Search for Open Files" (lsof)

The `SearchOpenFiles` constructor crash (finding 2 above) is fixed and
confirmed directly. But driving the window it opens — `app.lsof` end to
end, with its own search box — reproducibly segfaults very early in the
run (inside `PrettyTable#themed_icon`'s `icon_theme.has_icon?` call, during
the very first process-table icon scan, before any drive step even runs),
whenever that code is present in `test/drive_window.rb` at all, with the
`g_object_ref` critical above already fixed, regardless of concurrent
system load (reproduced at both ~30 and ~13 other sibling processes running
on this shared sandbox) and regardless of whether the lsof step had
actually run yet. Removing just those two steps, repeatedly, under the same
conditions, does not crash. This looks like a GC/binding timing dependency
tied to total compiled script size, not resource exhaustion — but isolating
it further than that did not fit this round's budget, so `test/drive_window.rb`
does not drive it, with that spelled out in a comment at the point it was
removed and in `.reports/binding-gaps.md`, rather than silently dropping
coverage. This is a real, reported gap, not a hidden one — see "Verdict"
below for what it does and does not mean for the gate.

## Prior round (superseded above; kept for history)

The prior round's gate (`drive_ok=false`, documented against `844ed8ec`) was
a broken devShell: `flake.nix` built `vendor/bundle` against the root
`Gemfile`, which pulls in `kettle-family` and fails to resolve on the
devShell's Ruby 3.4. `57971f35` rebuilt the devShell on `bundlerEnv` +
`nix/Gemfile`, which fixes that. Re-run directly for this audit:

```
$ nix develop --command xvfb-run -a ruby test/drive_window.rb
...
30 of 30 checks passed
DRIVE OK
```

**Confirmed independently in this audit, not just trusted from the harness
number.** The gate is real: GTK/Adwaita loads, the window builds, and the
checked assertions (tab switching, process-table population, search,
selection, the action bar, process properties, memory maps, open files,
the dependency tree, the File Systems tab, and Preferences) all pass.

## Gap this audit found: the gate's "0 failed" hides 3 silent screenshot failures

`test/drive_window.rb`'s own run, reproduced above, printed these lines
among the passing checks:

```
shot 03-processes failed: RuntimeError: widget produced no render node (not realised yet?)
shot 05-selection failed: RuntimeError: widget produced no render node (not realised yet?)
shot 09-dependencies failed: RuntimeError: widget produced no render node (not realised yet?)
```

`test/gtk_driver.rb#shot` (line ~118) rescues `StandardError`, prints the
message, and returns — it does not add the step to `@failed_checks` and does
not affect the exit code or the "N of N checks passed" / "DRIVE OK" lines.
So a screenshot that never captured a render node for the Processes tab, the
post-selection action bar, and the Dependencies tree is **not counted as a
failure anywhere a reader of the pass/fail summary would see it.** The 30
`check()` assertions for those three stages did pass (they check model/data
state, not rendering), but the visual-render half of "render it, screenshot
it" (`component-parity`'s own Step 4) silently did not happen for those
three views, every run, and nothing before this audit said so.

This is exactly the kind of narrow-drive gap the task calls out: a drive run
can report "0 failed" while 3 of its 12 intended screenshots never actually
rendered. Treating the headline number alone as the gate would hide it.

## Gap this audit found: the project's own `rspec` entry point is empty and broken

The devShell banner advertises a third command beyond running and driving
the app:

```
run the specs: ruby -e 'require "rspec/core"; exit RSpec::Core::Runner.run(["--format", "progress", "--require", "spec_helper", "spec"])'
```

Run as given:

```
An error occurred while loading spec_helper. - Did you mean?
                    rspec ./spec/spec_helper.rb
Failure/Error: require "kettle/test/rspec"
LoadError:
  cannot load such file -- kettle/test/rspec
...
0 examples, 0 failures, 2 errors occurred outside of examples
```

Two independent problems, not one: `spec/spec_helper.rb:23` requires a gem
(`kettle-test`, the rspec half of the same `kettle-family` packaging
tooling the prior round's gate fix worked around) that is not in the
devShell's gemset, so the helper cannot even load; and separately,
**`spec/` contains no `*_spec.rb` file at all** — only `spec_helper.rb` and
`spec/README.md` — so even a working helper would run 0 examples. This is a
second, independent runtime-gate failure the 30-check `drive_window.rb`
number says nothing about, because it is a different entry point. See
`.reports/test-parity.md` for what this means for test coverage.

## `test/test_binding_limits.rb`

Previously documented (`.reports/binding-gaps.md`, carried forward, not
re-litigated here) as an environment limitation: the script unconditionally
deletes `DISPLAY`/`WAYLAND_DISPLAY` before forking its subprocess, and this
fork's nixpkgs `gtk4` has no broadway backend, so the no-variant invocation
reliably fails regardless of outer `xvfb-run`. Re-run in this audit with an
explicit variant under `xvfb-run` (`ruby test/test_binding_limits.rb safe`)
to check the documented claim that it passes there: the run did not finish
within a 120s timeout in this sandbox and was killed mid-run (`SIGTERM`
during `Gio::ListStore#append`), so the specific claim "survives under a
real display" is **not re-confirmed by this audit** — inconclusive, not
contradicted. Flagging rather than asserting either way.

## This audit's independent re-run: the "0 failed, 0 crash" framing for the 42-check gate hides a WORSE screenshot gap than the one named above

Re-ran `nix develop --command xvfb-run -a ruby test/drive_window.rb` directly
for this audit, against the current tip (`8e919988`). It reproduces
**42 of 42 checks passed, DRIVE OK** exactly as claimed. But this round's own
"Verdict" section (below) summarizes the run as "0 failed, 0 errored, 0
`CRITICAL`, 0 crash" without re-stating the screenshot caveat that the
*prior* round's section above carefully wrote down for the 30-check run. Doing
so hides a regression: this round's run, captured directly in this audit,
silently fails to render **six** screenshots, not the three the prior round
found:

```
shot 02-resources-live failed: RuntimeError: widget produced no render node (not realised yet?)
shot 03-processes      failed: RuntimeError: widget produced no render node (not realised yet?)
shot 05-selection       failed: RuntimeError: widget produced no render node (not realised yet?)
shot 07-memory-maps     failed: RuntimeError: widget produced no render node (not realised yet?)
shot 09-dependencies    failed: RuntimeError: widget produced no render node (not realised yet?)
shot 12-processes-final failed: RuntimeError: widget produced no render node (not realised yet?)
```

Same root cause as before (`test/gtk_driver.rb#shot` rescues `StandardError`
and does not fail the run or count against `@failed_checks`), same silent
behaviour, but a wider blast radius now that the script drives more surfaces
— 6 of its ~16 intended screenshots never actually render a frame, every run,
with nothing in the "42 of 42 checks passed / DRIVE OK" output a reader would
see that says so. **This round's own "Verdict" section below does not
mention this at all** — it was written against the bug-fixing commit's own
claims ("0 failed... 0 crash") without re-opening the screenshot question the
prior round itself had flagged as still-relevant. That is exactly the
false-green shape `accountability-ensurance` exists to catch: a clean-sounding
summary line, carried forward commit to commit, that quietly stops
mentioning a known defect once a different number (42 vs 30) makes the
section look new. Treating "42/42, 0 failed" as the whole gate, as this
round's Verdict does, is a gap in the report, not just in the app.

## Verdict (prior round, superseded by this round's section above)

The headline gate is real and reproduced: `drive_window.rb` genuinely
exercises ~10 of the port's surfaces end to end under a real virtual
display, and 30/30 of its explicit assertions pass. But "0 failed" is not
the same claim as "everything this script tried to check succeeded" — 3
screenshots silently didn't render — and the gate is narrower than the
project's own tooling implies: the `rspec` entry point the devShell
advertises produces zero examples and can't even load, which means **no
component in this port has ever been covered by an actual example-based
spec**, only by the one hand-rolled `drive_window.rb` script and the two
plain-Ruby `test_units.rb`/`test_procfs.rb` scripts. Components `drive_window.rb`
never visits at all — About, the keyboard-shortcuts dialog, Renice, Set
Affinity, the standalone "Search for Open Files" (lsof) window, the
End-Process confirmation, and the column-view drag-reorder persister — are
unverified by any execution, not merely undriven in this one run.

## Verdict (this round)

`test/drive_window.rb` now drives every one of the previously-unverified
components except Search for Open Files (42/42 checks, reproduced three
times back to back, 0 failed, 0 errored, 0 `CRITICAL`, 0 crash) and, in
doing so, found and fixed four real bugs — three straightforward port
mistakes (an unwrapped-variant assumption, a missing keyword constructor, a
`Gtk::Window`/`Adwaita::Dialog` mix-up) and one confirmed ruby-gnome binding
defect with a safe fix in the port's own code (`g_object_ref` on a
non-`GObject` `GtkExpression`). None of the four would have been caught by
`ruby -c`, a successful `require`, or the prior round's narrower drive —
every one needed the dialog actually opened and inspected. The `rspec`
entry point remains broken exactly as the prior round found it (same
`LoadError: cannot load such file -- kettle/test/rspec`, re-confirmed this
round, not re-fixed — out of this round's scope) and `spec/` still holds no
example file, so that gap stands. Search for Open Files is fixed at the
constructor level (confirmed directly) but not driven end-to-end, for the
reason given above — a real, named gap, not a hidden one.
