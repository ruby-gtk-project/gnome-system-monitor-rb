# Test parity — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `main` @ `ebfa2af8` |
| Port | `ruby` @ `57971f35` |
| Upstream tests | 3 |
| Ported | **0** (unchanged this round) |
| Gaps | **3** cgroup tests (unchanged), plus a broken/empty `rspec` entry point (new this round) |
| Test command | `make test` (declared) — **now runs; 3/4 files pass, 1 inconclusive; see below** |

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

## Step 3 — is there a suite to run at all? (re-run this round, devShell now fixed)

The prior round's blocker — `bundle install` failing outright, documented in
the prior `runtime-gate.md` — is fixed as of `57971f35` (see
`.reports/runtime-gate.md`, "Confirmed independently"). Re-run directly in
this audit, under `nix develop --command xvfb-run -a ruby <file>`:

- `test/test_units.rb` — **runs clean, 29/29 checks pass** (no GTK import;
  not the cgroup tests, see census above).
- `test/test_procfs.rb` — **runs clean, all checks pass** (confirmed this
  round; the prior round's `LoadError` on `gio2` is gone now that the
  binding gems actually install).
- `test/test_binding_limits.rb` — **inconclusive this round.** The
  no-variant (default) invocation reliably fails for a documented
  environment reason (`.reports/binding-gaps.md`: it force-deletes
  `DISPLAY`/`WAYLAND_DISPLAY` before forking, and this nixpkgs `gtk4` has no
  broadway backend). Running the `safe` variant directly under `xvfb-run`
  to check that documented claim did not finish inside a 120s timeout in
  this sandbox — killed mid-run, not confirmed pass or fail. Flagged, not
  asserted either way.
- `test/drive_window.rb` — **runs, 30/30 checks pass, `DRIVE OK`**,
  independently reproduced (`.reports/runtime-gate.md`). 3 of its 12
  screenshot captures silently fail to render (same report) without
  affecting this pass/fail count.

**New this round: the project's `rspec` entry point is a separate, still-
broken gap the Makefile-based `make test` doesn't even touch.** The devShell
banner advertises `ruby -e '... RSpec::Core::Runner.run(...)'` as how to
"run the specs." Run as given, it produces `0 examples, 0 failures, 2
errors occurred outside of examples` — `spec/spec_helper.rb:23` requires
`kettle/test/rspec`, which is not installed, so the helper can't even load;
and independent of that, **`spec/` holds no `*_spec.rb` file at all**, only
`spec_helper.rb` and a `README.md`. Even a fixed helper would run zero
examples. This means **no component in this port has ever been covered by
an example-based (`rspec`) test** — only by the three plain-Ruby scripts
above and the hand-rolled `drive_window.rb`. That is a real, currently-true
gap, not inherited language from the prior round.

**A suite that has never been executed is still a gap where it applies:**
`test/test_binding_limits.rb`'s specific environment-dependent claim is
unconfirmed this round (inconclusive, not failing), and the `rspec` entry
point has 0 examples full stop. The cgroup-test gap below (upstream's only
real tests) is **unchanged** — nothing ported them this round either.

## Step 4 — what's extra (re-counted against passing runs this round)

- `test/test_units.rb` — 29 checks, **confirmed passing**.
- `test/test_procfs.rb` — 52 `check(...)` sites, **confirmed passing this
  round** (previously never-executed; devShell fix changes this).
- `test/test_binding_limits.rb` — 1 `check(...)` site, **inconclusive this
  round** (timed out before completing under `xvfb-run safe`).
- `test/drive_window.rb` — 30 `check(...)` sites driving the live window,
  **confirmed passing, `DRIVE OK`** (3 of 12 screenshots silently fail to
  render; does not affect the check count).
- `spec/` (rspec) — 0 spec files, 0 examples, helper fails to load. **Not a
  parity gap in the ledger-row sense (upstream has no rspec suite to port
  against), but a real gap in the port's own test tooling worth stating
  plainly rather than leaving silent.**

## Rules this ledger follows

- No third state: every upstream test is `ported` or `gap`. All three are `gap`.
- A note that the port's logic "looks equivalent" is not a reason to mark a
  row `ported`; it is restated above as the behaviour owed.
- A suite that has never run is called out by name, per file, not folded into
  a vague "tests exist" claim.
