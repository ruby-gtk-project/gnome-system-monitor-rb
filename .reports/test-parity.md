# Test parity — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `main` @ `ebfa2af8` |
| Port | `ruby` @ `844ed8ec` |
| Upstream tests | 3 |
| Ported | **0** |
| Gaps | **3** |
| Test command | `make test` (declared) — **does not complete; see below** |

## Step 1 — upstream census

Upstream's entire GLib test suite is `src/cgroups/test.c`, registered via
`g_test_add_func` and wired into `meson.build` via the one real `test(...)`
call in `src/cgroups/meson.build` (the top-level `meson.build`'s only other
`test(...)` is a code-formatting check, not a test case):

```
src/cgroups/test.c   /gnome-system-monitor/cgroups/v2                 43
src/cgroups/test.c   /gnome-system-monitor/cgroups/v1/one-entry       44
src/cgroups/test.c   /gnome-system-monitor/cgroups/v1/multiple-entry  46
```

That is the entirety of upstream's test suite: **3 tests**, all pinning
`extract_name()`'s parsing of a raw `/proc/<pid>/cgroup` line — the cgroup v2
unified-hierarchy empty-root cases (`NULL`, `""`, `"0::/"`, `"0::/\n"` all →
`""`; `"0::/a\n"` → `"/a"`), the cgroup v1 single-entry case with and without
a `name=` prefix, and the cgroup v1 multi-entry case (two lines, output
sorted and joined).

## Step 2 — the ledger

| # | Upstream test | Purpose | Port test | State |
|---|---|---|---|---|
| 1 | `/gnome-system-monitor/cgroups/v2` | cgroup v2's single unified line: `NULL`/empty/root-only input all collapse to `""`; a real subpath survives | — | **gap** |
| 2 | `/gnome-system-monitor/cgroups/v1/one-entry` | one cgroup v1 line, with and without a `name=` controller prefix, formats as `path (controller)` | — | **gap** |
| 3 | `/gnome-system-monitor/cgroups/v1/multiple-entry` | two cgroup v1 lines sort and join as `path0 (c0), path1 (c1)` | — | **gap** |

**Behaviour still owed, all three rows:** `GnomeSystemMonitor::ProcFs.cgroup_name`
(`lib/gnome_system_monitor/proc_fs.rb:156`) implements logic that looks
equivalent by reading — it drops empty/`/`-only paths, strips a `name=`
prefix, sorts and joins multi-entry output — but **no port test feeds it
upstream's exact fixture lines** (`"0::/"`, `"0::/\n"`, `"0::/a\n"`,
`"0:a1:/b1\n"`, `"0:name=a2:/b2\n"`, `"1:a1:/b1\n0:a0:/b0\n"`) and asserts the
same outputs. `test/test_procfs.rb:69-72` tests a different, lower-level
method (`format_cgroup`, which takes already-parsed `(path, controllers)`
pairs) and never calls `cgroup_name` with raw cgroup-file text at all, so the
one thing upstream's tests actually pin — the *parsing* of the raw line,
including the `NULL`/empty/root edge cases — has no port test watching it.
Equivalent-looking code with no test pinning it is not the same claim as a
ported test, and per the skill there is no partial-credit state for this.

**0/3, not "close enough."** A reader might object that the port's behaviour
probably matches; that is exactly the gap the skill exists to catch — nobody
has written down that it does, and "probably" is not census output.

## Step 3 — is there a suite to run at all?

`make test` (the declared command, `Makefile:31-36`) is:

```
bundle exec ruby test/test_units.rb
bundle exec ruby test/test_procfs.rb
env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/test_binding_limits.rb
env -u DISPLAY -u WAYLAND_DISPLAY bundle exec ruby test/drive_window.rb
```

Every line is prefixed `bundle exec`, and `bundle install` fails outright on
this project's own `nix develop` shell (Ruby-version conflict introduced by
the `kettle-family` packaging gem — full detail in
`.reports/runtime-gate.md`). **`make test` has not completed successfully in
this audit and could not be made to.** Run without `bundle exec` directly:

- `test/test_units.rb` — runs clean, 29/29 checks pass (no GTK import; not
  the cgroup tests, see census below).
- `test/test_procfs.rb` — fails to load: `require "gio2"`
  (`system_stats.rb:3`) raises `LoadError`, because no GTK/GIO binding gem is
  installed at all. **This is the file that would carry the cgroup tests if
  they existed, and it cannot even be parsed-and-required, let alone run.**
- `test/test_binding_limits.rb`, `test/drive_window.rb` — not run; both
  `require "gtk4"`/`"adwaita"` directly and hit the same `LoadError`.

**A suite that has never been executed is a gap, stated plainly: three of
this port's four test files have never once completed a run in this
environment**, and the fourth (`test_units.rb`) covers none of the three
upstream tests this ledger owes. "The suite is green" cannot be claimed for
any file that imports GTK, because none of them have ever finished running.

## Step 4 — what's extra

None of this is parity work, and none of it is free of the runtime gate
above — every count below is "lines of code that exist," not "checks that
have passed," except where marked:

- `test/test_units.rb` — 29 checks, **confirmed passing**, no GTK.
- `test/test_procfs.rb` — 52 `check(...)` sites, **never executed**
  (`LoadError` on `require "gio2"`).
- `test/test_binding_limits.rb` — 1 `check(...)` site, **never executed**.
- `test/drive_window.rb` — 65 `check(...)` sites driving the live window,
  **never executed**.

## Rules this ledger follows

- No third state: every upstream test is `ported` or `gap`. All three are `gap`.
- A note that the port's logic "looks equivalent" is not a reason to mark a
  row `ported`; it is restated above as the behaviour owed.
- A suite that has never run is called out by name, per file, not folded into
  a vague "tests exist" claim.
