# Runtime gate — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `origin/main` @ `ebfa2af8` |
| Port | `ruby` @ `844ed8ec` |
| Gate this round | `drive_ok=false`, 0 checks passed, 0 failed, 0 components covered |

## Root cause, reproduced

`bundle install` (and therefore `make test`, `rake test`, `test/drive_window.rb`,
`test/test_binding_limits.rb`, and anything else that goes through the
project's own `Gemfile`) fails on a clean `nix develop` shell:

```
$ nix develop --command bundle install
Resolving dependencies...
Could not find compatible versions

Because kettle-family >= 1.0.0 depends on Ruby >= 4.0.0
  and Gemfile depends on kettle-family >= 1.3.37, < 2.A,
  Ruby >= 4.0.0 is required.
So, because current Ruby version is = 3.4.9,
  version solving has failed.
```

`Gemfile:21` pins `gem "kettle-family", "~> 1.3", ">= 1.3.37"`, added by the
four commits titled "Package the app with kettle-jem" — pure gem-packaging
scaffolding, unrelated to the GTK/Adwaita port — and that gem transitively
requires Ruby ≥ 4.0. The flake's devShell (`flake.nix`) provides Ruby 3.4.9.
`Gemfile.lock`'s own `DEPENDENCIES` block only lists
`adwaita, gem_kit, gettext, gtk4, rubocop` — it predates the kettle-family
addition and was never regenerated, so the repository has been uninstallable
since whichever commit added `kettle-family` to the `Gemfile` without
re-running `bundle lock`.

Consequence, checked directly:

```
$ nix develop --command gem list gtk4 adwaita
(nothing — only gettext 3.5.2 is present as a system gem)
$ nix develop --command ruby -e 'require "gtk4"'
cannot load such file -- gtk4 (LoadError)
```

**No GTK, Adwaita, GLib or GIO binding is installed in the dev shell at all.**
Every file under `lib/` that `require`s any of them — which is effectively
every file except `units.rb` and the pure-text halves of `proc_fs.rb` /
`proc_files.rb` — cannot be loaded, driven, screenshotted, or unit-tested.
This is the entire explanation for `drive_ok=false` and 0 components covered:
it is not that the drive script found nothing to check, it is that nothing in
the port can be required at all.

## What does and does not run, checked directly (no bundler, plain `ruby`)

| File | Result |
|---|---|
| `test/test_units.rb` | **runs, 29/29 checks pass** — no GTK import |
| `test/test_procfs.rb` | **fails to load**: `require "gio2"` in `system_stats.rb:3` raises `LoadError` |
| `test/test_binding_limits.rb` | not run — requires `gtk4`/`adwaita` per its own `require`s, same `LoadError` expected |
| `test/drive_window.rb` | not run — same |
| `exe/gnome-system-monitor` | not run — same |

So the honest state of the runtime gate is **29 checks ran and passed, out of
a suite whose other four files cannot even be parsed-and-required**, not 0
checks total. The harness's `0 checks passed` figure is consistent with
`make test`'s first GTK-touching line (`ruby test/test_procfs.rb`, which pulls
in `system_stats.rb` → `gio2`) aborting the whole run before any check output
is produced, which is what `make test`'s plain sequential `sh` lines do on a
non-zero exit.

## Verdict

**This is a parity gap in its own right**, per the task's own framing: a
component no check exercises is unverified, not done. Concretely, *every*
widget, dialog, signal, action, and shortcut this audit's other four reports
discuss is unverified by execution — the `component-parity` skill's Steps 4
and 5 (render it, screenshot it, drive the signals) could not be performed at
all, for any component, because the runtime that would do that cannot start.
The three other GTK-touching test files are likewise unverified, not merely
"not yet run for lack of time."

This is fixable without touching the port: either pin `kettle-family` back to
a version that supports Ruby 3.4, drop it from the `Gemfile` entirely (it is
release/packaging tooling, not a runtime dependency of the app), or raise the
devShell's Ruby to 4.0. None of those were done as part of this audit, per
instructions to audit rather than fix; the fix is one line in `Gemfile` or
`flake.nix` and is the single highest-leverage thing anyone touching this
port should do next.
