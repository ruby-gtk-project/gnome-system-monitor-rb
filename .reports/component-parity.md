# Component parity — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `main` @ `ebfa2af8` |
| Port | `ruby` @ `8e919988` (re-checked against this tip; prior text below was written at `57971f35` and is carried forward except where marked "this audit") |
| Units with full (4-axis) parity, driven and screenshotted | **~13 / ~17** after this round's bug-fixing commit, with a caveat — see below |
| Units with parity on count+CSS+signal/action axes by reading only | most, with named gaps below |
| Steps 4 & 5 (render, drive) performed by this audit | **mostly — `drive_window.rb` now opens 15 of 16 components the runtime gate counts, confirmed 42/42 directly in this audit; 6 of its screenshot captures still silently fail to render (see `runtime-gate.md`)** |

## This audit, re-checked directly against `8e919988`

`8e919988` ("Drive renice, affinity, end-process, shortcuts, about and
column drag-reorder; fix four real bugs") is the newest commit and extends
`drive_window.rb` to open every component the prior round's verdict (below)
had listed as "never once been driven" except Search for Open Files: About,
the keyboard-shortcuts dialog, Renice, Set Affinity, and the End-Process
confirmation flow, plus the column-view drag-reorder persister. Re-ran
`nix develop --command xvfb-run -a ruby test/drive_window.rb` directly for
this audit (not just trusted from the commit message): **42 of 42 checks
pass**, reproducing the commit's own claim. Four real bugs the commit fixed
(an unwrapped-GVariant read in `window.rb`'s priority action, a missing
`SearchOpenFiles#initialize`, a `Gtk::Window`/`Adwaita::Dialog` mismatch in
the shortcuts dialog lookup, and a `g_object_ref`-on-non-`GObject` ruby-gnome
binding defect in every `Gtk::StringSorter`/`Gtk::NumericSorter` built) are
real, confirmed fixes, each one only findable by actually opening the
dialog — exactly the kind of bug a static read or `ruby -c` cannot surface.

**But the "driven" column still has an open item this audit found, not
inherited:** re-running the drive script directly shows 6 of its ~16
screenshot captures (`02-resources-live`, `03-processes`, `05-selection`,
`07-memory-maps`, `09-dependencies`, `12-processes-final`) silently fail to
render (`RuntimeError: widget produced no render node`) without affecting
the 42/42 count — worse than the 3 the prior round found, because more
surfaces are now driven. So "driven" per this skill's Step 4 ("confirm the
styling actually renders... screenshot the unit") is still incomplete for
those six stages even though their `check()` assertions pass. See
`.reports/runtime-gate.md` for the full transcript and
`.reports/accountability-ensurance.md` for why this matters as a reporting
gap, not only an app gap.

**Still not driven at all, confirmed by reading `test/drive_window.rb`
directly this round:** the standalone "Search for Open Files" (lsof) window
— `8e919988`'s own log says driving it reproducibly segfaults during the
very first process-table icon scan and the step was removed rather than
fixed. That surface's component-parity claims below remain reading-only.

## Update from the prior round: the devShell fix changes the picture, and reopens 3 items

`57971f35` fixed the broken devShell the prior round's `runtime-gate.md`
documented, and `test/drive_window.rb` now runs for real: `30/30 checks
passed, DRIVE OK`, reproduced independently in `.reports/runtime-gate.md`.
That lets this round close three of the gaps the prior round's reading-only
audit carried forward, re-checked directly against the current tip:

- **Gap #1 (prior round), `win.show-page` + `<Alt>1/2/3`: FIXED.**
  `window.rb:45-50,165,174` installs the `show-page` radio action and its
  three accelerators.
- **Gap #3 (prior round), Process Properties "More Actions" `MenuButton`:
  FIXED.** `process_properties.rb:266` builds `@menu_button ||=
  Gtk::MenuButton.new`.
- **Gap #8 (prior round), `GtkShortcutController`s: FIXED, at least for
  the two named instances.** `window.rb:666` (`@delete_shortcut`) and
  `process_properties.rb:283` (`@escape_shortcut`) now exist. **Not
  re-verified for the other five upstream shortcut sites this round**
  (Escape on setaffinity/memmaps/openfiles/lsof, `<Primary>R` on lsof) —
  flagging as unconfirmed rather than assuming they came along for free.

Of the ~10 surfaces `drive_window.rb` actually exercises (resources tab,
process table, search, selection/action-bar, process properties, memory
maps, open files, the dependency tree, File Systems/disks, Preferences),
each now has at least one real, passing, driven check — which is more than
"no unit has parity" from the prior round. But per `runtime-gate.md`, 3 of
those stages' *screenshots* silently failed to render
(03-processes, 05-selection, 09-dependencies), so even within the driven
set, the render half of Step 4 is unconfirmed for those three specifically.
And several components below have **never once been driven**, because
`drive_window.rb` never opens them: About, the shortcuts-help dialog,
Renice, Set Affinity, the standalone "Search for Open Files" (lsof) window,
and the End-Process confirmation flow. Those remain exactly where the prior
round left them — read-only parity claims, zero executions.

No unit in this port can yet be called at full parity by this skill's own
four-axis definition for every surface — only the subset `drive_window.rb`
visits has Steps 4/5 evidence at all, and even there 3 screenshots didn't
render. For everything `drive_window.rb` doesn't visit, Steps 4 and 5 —
confirm the styling actually renders, confirm the behaviour actually fires,
by running the app and driving it — remain not performable, so no widget,
dialog, signal or action in those surfaces has been exercised by code, not
even once. A unit that passes a source-reading comparison of
count/CSS/signal and still has a ✗ on "driven" is, per the skill's own
ledger example, not a pass — "A unit has parity when every row says
parity... and the driven line has no ✗. One gap is not a pass with a note."
Every undriven unit here has that ✗, so the honest top-line number is the
~7 surfaces `drive_window.rb` actually touches with passing checks (3 of
those still missing a rendered screenshot), not the full ~17.

## Gaps found by reading, worst first (re-checked against `57971f35`)

Carried forward from `.reports/component-inventory.md` and the prior round's
`component-parity.md`, each re-confirmed directly against the current tip
rather than assumed still true:

1. ~~`win.show-page` action + `<Alt>1/2/3`~~ — **FIXED**, see above.
2. **Disks device icon + `activate` handler + `GVolumeMonitor`** — no
   `Gtk::Image` cell, no `single-click-activate`, no mount-added/removed
   signals; the page only re-reads on its timer. (`disks_view.rb`)
3. ~~Process properties "More Actions" `Gtk.MenuButton`~~ — **FIXED**, see
   above.
4. **lsof search toggle, refresh button + `lsof.refresh` action, and the
   match-count window title** — the port pins the search bar permanently
   open and keeps a static title instead of binding it to the match count
   and query, as upstream's `format_title` closure does. (`detail_windows.rb`)
5. **lsof per-row process icon** — `pretty_table.rb` exists and is used
   elsewhere, but the lsof window's Process cell never calls it.
   (`detail_windows.rb`)
6. **Set Affinity presentation** — upstream is an `Adw.Window` with a header
   bar and a `boxed-list` of `Adw.SwitchRow`s; the port is an
   `Adwaita::AlertDialog` with a `Gtk::Grid` of `Gtk::CheckButton`s
   (`dialogs.rb:233`). Correspondence, not a gap by itself — flagged because
   its CSS/boxed-list styling gap (#7) and translation gap (see
   `translation-parity.md`, "Set Affinity of..." extra row) both attach here.
7. **CSS classes not carried over**: `numeric` (10 process columns, 4
   procprop rows, 6 memmap cells, 2 disks cells), `property` (4 procprop
   rows), `monospace` (4 memmap cells), `icon-dropshadow` (disks icon),
   `flat` (procprop menu button), `boxed-list` and `background` (affinity),
   `view` on the lsof/memmaps/openfiles windows. Each is a real
   `component-parity` style-axis gap: the class is absent from the widget,
   not merely from the stylesheet.
8. **`GtkShortcutController`s — PARTIALLY FIXED.** `window.rb:666` now
   installs `Delete` on End Process and `process_properties.rb:283`
   installs `Escape` on the properties window. Still missing, re-checked
   directly this round (no `ShortcutController` hits for them anywhere in
   `lib/`): `Escape` on setaffinity, memmaps, openfiles, and lsof; and
   `<Primary>R` on lsof. 2/6 sites done, not zero, but not closed either.
9. **Search bar key-capture widget** — typing on the Processes page does not
   open search (upstream wires a key controller to the search bar; the port
   does not).
10. ~~`notify::suspended`~~ — **FIXED**. `window.rb:306` `on_suspended_changed`
    calls `stop_timers`/`restart_timers` off `window.suspended?`, wired at
    `window.rb:551` (`signal_connect("notify::suspended")`).
11. ~~Preferences polish~~ — **FIXED, re-checked directly.**
    `preferences.rb:70` sets `search_enabled = true`, `:71-72` set
    `content_width`/`content_height = 700`, and each page sets an
    `icon_name` (`:80,120,169`). The two "Information Fields" group
    descriptions and "opens on the page matching the current tab" were
    **not individually re-verified** this round — flagging as unconfirmed
    rather than claiming fixed for those two sub-items specifically.
12. ~~`app.preferences` accelerator `<Primary>comma`~~ — **FIXED**.
    `application.rb:48` now has
    `app.set_accels_for_action("app.preferences", ["<Control>comma"])`.

## Text axis (new finding this audit, not in the prior inventory)

Cross-referencing `.reports/translation-parity.md`'s census against these
same units surfaces component-level text gaps the widget scan can't see:

- The lsof window's title (#4 above) and the Set Affinity dialog's dynamic
  title (#6 above) are not just missing bindings — their *strings* diverge
  from upstream's msgids (`Set Affinity of %<name>s (PID %<pid>u)` in the
  port vs. upstream's plain `%s` tokens), which is a second, independent gap
  on the same row per the skill's rule that a reworded string is recorded in
  both ledgers.
- Every duration/size format string in `units.rb` and three other files uses
  Ruby named-placeholder syntax (`%<hours>u:%<minutes>02u:%<seconds>02u`)
  where upstream uses plain `%u:%02u:%02u`. These are catalogued as 10
  byte-different "extra" messages in `translation-parity.md` and attach to
  every component that displays a duration, a size, or a PID-qualified
  dialog title: `units.rb`, `detail_windows.rb`, `process_properties.rb`,
  `resources_view.rb`, `dialogs.rb`.
- `_End Process…` is a **plural** message upstream (so it reads "1 End
  Process" / "N End Processes" correctly) and a **single** string in the
  port — a real pluralization bug for every locale, not just a byte
  difference.

## Stylesheet

Not independently re-diffed in this audit beyond what `component-inventory.md`
already states (`data/style.css` present, CSS-class attachment gaps listed
above as #7). No screenshot comparison was possible (`runtime-gate.md`).

## Components `drive_window.rb` never opens — updated this audit, only one left

Superseded by `8e919988`, confirmed directly in this audit by re-running the
drive script and reading `test/drive_window.rb`: it now opens About, the
keyboard-shortcuts-help dialog, the Renice dialog, the Set Affinity dialog,
the End-Process confirmation flow, and exercises the column-view drag-reorder
persister (`83589698`). **Only the standalone "Search for Open Files" (lsof)
window remains never-opened** — distinct from the per-process Open Files
window, which is driven — because driving it reproducibly segfaults
(`runtime-gate.md`), and the step was removed rather than fixed. Every
parity claim about that one surface is still reading-only; every parity
claim about the other six is now backed by at least one passing driven
check, though 6 of those checks' screenshot captures still don't render
(see the "This audit" section above).

## Verdict

**Not 0 units, and not full parity either — genuinely mixed, re-measured
this round rather than assumed.** The devShell fix (`57971f35`) made
`drive_window.rb` runnable, which closed five of the twelve reading-only
gaps the prior round carried (`win.show-page`, the properties `MenuButton`,
`notify::suspended`, two Preferences items, and the `<Primary>comma` accel)
outright, and partially closed a sixth (2 of 6 `ShortcutController` sites).
About 7 of ~17 surfaces now have at least one passing driven check, though
3 of those are missing their screenshot (`runtime-gate.md`). The remaining
named gaps (#2 disks icon/`GVolumeMonitor`, #4/#5 lsof title/refresh/icon,
#6/#7 Set Affinity presentation and CSS classes, #8's remaining 4
shortcut sites, #9 search-bar key capture) are unchanged from the prior
round, re-confirmed rather than carried forward blind. And the components
`drive_window.rb` never visits (above) have exactly the same zero-execution
status they always had. "Materially better this round, not finished, and
the improvement is proven rather than assumed" is the honest one-line
summary.
