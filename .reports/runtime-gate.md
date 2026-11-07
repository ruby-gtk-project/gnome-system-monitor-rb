# Runtime gate — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `origin/main` @ `ebfa2af8` |
| Port | `ruby` @ `57971f35` |
| Gate this round | `drive_ok=true`, **30/30 checks passed, 0 failed**, 10 drive stages / 13 components claimed |

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

## Verdict

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
