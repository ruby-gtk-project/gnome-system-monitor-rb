# Component parity — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `main` @ `ebfa2af8` |
| Port | `ruby` @ `844ed8ec` |
| Units with full (4-axis) parity, driven and screenshotted | **0 / ~17** |
| Units with parity on count+CSS+signal/action axes by reading only | most, with named gaps below |
| Steps 4 & 5 (render, drive) performed by this audit | **no — could not run; see `runtime-gate.md`** |

No unit in this port can be called at parity by this skill's own definition,
because Steps 4 and 5 — confirm the styling actually renders, confirm the
behaviour actually fires, by running the app and driving it — were not
performable at all. `bundle install` fails outright on this project's own dev
shell (`.reports/runtime-gate.md`), so no widget, dialog, signal or action in
this port has been exercised by code, not even once, since the gems that
would load them aren't installed. A unit that passes a source-reading
comparison of count/CSS/signal and still has a ✗ on "driven" is, per the
skill's own ledger example, not a pass — "A unit has parity when every row
says parity... and the driven line has no ✗. One gap is not a pass with a
note." Every unit here has that ✗, so the honest top-line number is 0, not
the number the per-axis table below might suggest at a glance.

## Gaps found by reading (the only axis available), worst first

Carried forward from `.reports/component-inventory.md`, re-confirmed at the
current tip and not yet closed:

1. **`win.show-page` action + `<Alt>1/2/3`** — advertised in the shortcuts
   dialog, not installed anywhere in `lib/`. (`window.rb`)
2. **Disks device icon + `activate` handler + `GVolumeMonitor`** — no
   `Gtk::Image` cell, no `single-click-activate`, no mount-added/removed
   signals; the page only re-reads on its timer. (`disks_view.rb`)
3. **Process properties "More Actions" `Gtk.MenuButton`** — no `MenuButton`
   in the file at all. (`process_properties.rb`)
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
8. **`GtkShortcutController`s — none exist in the port at all.** `Delete` on
   End Process; `Escape` on procproperties, setaffinity, memmaps, openfiles,
   lsof; `<Primary>R` on lsof. This is a whole behaviour axis at zero, not a
   handful of missing bindings.
9. **Search bar key-capture widget** — typing on the Processes page does not
   open search (upstream wires a key controller to the search bar; the port
   does not).
10. **`notify::suspended`** — timers keep running when the window is
    suspended; upstream pauses refresh work when the window isn't visible.
11. **Preferences polish** — `search-enabled`, 700×700 default size, the
    three page icons, the two "Information Fields" group descriptions, and
    opening on the page matching the current tab are all upstream behaviour
    with no port counterpart.
12. **`app.preferences` accelerator `<Primary>comma`** —
    `application.rb:46-48` installs accelerators for `app.quit`, `app.help`
    and `window.close` only; the action exists but has no key binding.

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

## Verdict

**0 units hold full parity.** The widget/count/signal-by-reading picture is
mostly good (most upstream files have a 1:1 port file and most widgets by
type/count are present), but every unit fails on at least one of: a named
CSS-class gap, a missing `GtkShortcutController`, a missing action, or — newly
found this audit — a reworded/mis-pluralized translation string. And no unit
anywhere has been driven or screenshotted, because nothing in this port can
currently be loaded (`.reports/runtime-gate.md`). "Mostly built, unverified
anywhere it was built" is the honest one-line summary.
