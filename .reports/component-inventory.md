# Component inventory — gnome-system-monitor-rb vs upstream `main`

Survey only. No app code was written for this pass. Built with the
`component-identification` skill's method: upstream's `.ui` files are read
first as the component map (GNOME System Monitor ships no blueprint), then
the `src/*.cpp`/`.c` files that back each template, then the menus, schema,
gresource manifest and `po/` catalogue. Compared file-by-file against what
`lib/` on `ruby` already has (`git ls-tree -r --name-only origin/main`
against `lib/gnome_system_monitor/*.rb`, read 2026-11-07).

Upstream is C/C++ (GTK4 port of the historical C app), not Vala/blueprint —
most "components" below are declared in a `data/*.ui` `<template>` and backed
by a `.cpp`/`.c` file of the same stem (`lsof.ui` + `lsof.cpp`, etc). Both
halves are listed as the upstream side of one row, per the skill's file-union
rule.

## Legend

- **exists** — a `lib/*.rb` file already carries this component (named by its
  own "ported from" comment or by its class name matching the upstream
  widget).
- **missing** — no `lib/*.rb` file covers it yet.
- **partial** — some of the upstream file's responsibility is covered
  elsewhere in `lib/`, but not all of it (noted).

## Windows, views and dialogs

| Upstream file(s) | Kind | → `lib/*.rb` | Status |
|---|---|---|---|
| `data/interface.ui` + `src/interface.cpp` | main window UI + wiring | `lib/gnome_system_monitor/window.rb` | exists |
| `src/application.cpp` + `src/main.cpp` | `Adw.Application` subclass, entry point | `lib/gnome_system_monitor/application.rb` | exists |
| `data/preferences.ui` + `src/prefsdialog.cpp` | preferences dialog (`AdwPreferencesDialog`) | `lib/gnome_system_monitor/preferences.rb` | exists |
| `data/renice.ui` (part of `src/procdialogs.cpp`) | "Change Priority" alert dialog | `lib/gnome_system_monitor/dialogs.rb` (`ReniceDialog`) | exists |
| `data/setaffinity.ui` + `src/setaffinity.cpp` | Set Affinity window | `lib/gnome_system_monitor/dialogs.rb` (`AffinityDialog`) | exists |
| `data/procproperties.ui` + `src/procproperties.cpp` | Process Properties window | `lib/gnome_system_monitor/process_properties.rb` | exists |
| `data/memmaps.ui` + `src/memmaps.cpp`/`src/mem-map.c` | Memory Maps per-process window | `lib/gnome_system_monitor/detail_windows.rb` | exists |
| `data/openfiles.ui` + `src/openfiles.cpp`/`src/open-file.cpp` | Open Files per-process window | `lib/gnome_system_monitor/detail_windows.rb` | exists |
| `data/lsof.ui` + `src/lsof.cpp` | "Search for Open Files" (cross-process) window | `lib/gnome_system_monitor/detail_windows.rb` (`SearchOpenFiles`) | exists |
| `data/disks.ui` + `src/disks.cpp`/`src/disk.c` | Disks tab view | `lib/gnome_system_monitor/disks_view.rb` | exists |
| `data/shortcuts-dialog.ui` | `AdwShortcutsDialog` ("Keyboard Shortcuts") | `lib/gnome_system_monitor/about.rb` (`ShortcutsDialog`) | exists |
| (no `.ui`; built from `GtkAboutDialog`/`AdwAboutWindow` in code, via `gtk_show_about_dialog`/menu action) + `AUTHORS` | About dialog | `lib/gnome_system_monitor/about.rb` (`About`) | exists |
| `data/menus.ui` | `generic-window-menu`, `process-window-menu`, `process-popup-menu` menu models | `lib/gnome_system_monitor/window.rb` + `lib/gnome_system_monitor/actions.rb` | exists |

## Process list / resources / tables

| Upstream file(s) | Kind | → `lib/*.rb` | Status |
|---|---|---|---|
| `src/proctable.cpp`/`src/proctable.h` | process `GtkColumnView`/tree model build | `lib/gnome_system_monitor/process_table.rb` | exists |
| `src/procinfo.cpp` | per-process field collection from `/proc` (libgtop upstream) | `lib/gnome_system_monitor/proc_fs.rb` | exists (reads `/proc` directly — see gem note below) |
| `src/proclist.cpp`/`.h` | process list container/model | `lib/gnome_system_monitor/process.rb` + `lib/gnome_system_monitor/process_view.rb` | exists |
| `src/column-view-persister.c`/`.h` | column width/order persistence | `lib/gnome_system_monitor/columns.rb` / `lib/gnome_system_monitor/settings.rb` | partial — persistence of user-resized columns not confirmed; needs a focused parity pass |
| `src/prettytable.cpp`/`.h` | process icon lookup (desktop files, theme fallback) | `lib/gnome_system_monitor/pretty_table.rb` | exists |
| `src/defaulttable.h` | default column set | `lib/gnome_system_monitor/columns.rb` | exists |
| `src/procactions.cpp`/`.h` | kill/stop/cont/renice/affinity actions on selection | `lib/gnome_system_monitor/actions.rb` | exists |
| `src/procdialogs.cpp`/`.h` | kill-confirmation and renice dialog wiring | `lib/gnome_system_monitor/dialogs.rb` | exists |
| `src/procproperties.cpp`/`.h` | process properties table data | `lib/gnome_system_monitor/process_properties.rb` | exists |
| `src/smooth_refresh.cpp`/`.h` | adaptive refresh-interval logic | `lib/gnome_system_monitor/smooth_refresh.rb` | exists |
| `src/update_interval.cpp`/`.h` | update-interval spin button helper (used in prefs/renice) | `lib/gnome_system_monitor/preferences.rb` | partial — confirm the shared spin-button widget (not just the setting) is reproduced |
| `src/legacy/treeview.c`/`.h` | legacy GtkTreeView helpers (sort indicator persistence, etc.) | — | missing — unclear whether `GtkColumnView` in the port needs an equivalent; needs a decision, not silent drop |
| `src/legacy/e_date.c`/`.h` | smart date formatting for process start time | `lib/gnome_system_monitor/units.rb` | partial — confirm date (not just byte/percent) formatting is ported; `units.rb`'s own comment only claims upstream's number formatting from `util.cpp` |
| `src/legacy/gsm_color_button.c`/`.h` | custom color-picker button (used in preferences for graph colors) | `lib/gnome_system_monitor/preferences.rb` | missing/unconfirmed — no `lib/*.rb` names this widget; preferences.rb needs to be read against it specifically |
| `src/util.cpp`/`.h` | number formatting (bytes, percentages) | `lib/gnome_system_monitor/units.rb` | exists |

## Resources tab (graphs)

| Upstream file(s) | Kind | → `lib/*.rb` | Status |
|---|---|---|---|
| `src/load-graph.cpp`/`.h` + `src/gsm-graph.c`/`.h` | CPU/memory/network/disk graph drawing | `lib/gnome_system_monitor/graph.rb` | exists |
| (no separate `.ui`; built in `interface.cpp`) | Resources tab container (per-CPU rows, legend, labels) | `lib/gnome_system_monitor/resources_view.rb` | exists |

## System stats / data sources

| Upstream file(s) | Kind | → `lib/*.rb` | Status |
|---|---|---|---|
| libgtop calls throughout `procinfo.cpp`, `load-graph.cpp`, `disks.c` | process/CPU/mem/net/disk stats | `lib/gnome_system_monitor/proc_fs.rb` + `lib/gnome_system_monitor/system_stats.rb` + `lib/gnome_system_monitor/proc_files.rb` | exists, but **not via the `GTop` gem** — `libgtop`'s gem loads but its functions are not callable (ruby-gnome resolves argument types by the raw lowercase GI name and every call raises `NameError`). The port reads `/proc` directly instead; this is a confirmed gem-unusability finding, not a silent workaround — flag again at parity review time, do not let it read as "libgtop ported." |
| `src/open-file.cpp`/`.h` | open-file / socket enumeration for a process | `lib/gnome_system_monitor/proc_files.rb` | exists |
| `src/mem-map.c`/`.h` | memory-map row parsing | `lib/gnome_system_monitor/proc_files.rb` or `detail_windows.rb` | needs confirmation — not clearly named in either file's header comments |
| `src/cgroups/gsm-cgroups.c`/`.h` | cgroup lookup for a process (shown in process properties / columns) | — | missing |
| `src/systemd/gsm-systemd.c`/`.h` | systemd unit lookup for a process | — | missing |
| `src/selinux/gsm-selinux.c`/`.h` | SELinux context column (conditional build upstream) | — | missing (upstream itself builds this conditionally; still a gap to record, not assume irrelevant) |

## Privilege-escalation actions (root kill/renice)

| Upstream file(s) | Kind | → `lib/*.rb` | Status |
|---|---|---|---|
| `src/action-impls/gsm-kill.c`/`.h` | privileged kill helper (polkit) | `lib/gnome_system_monitor/actions.rb` | partial — confirm polkit/pkexec path, not just unprivileged kill |
| `src/action-impls/gsm-setpriority.c`/`.h` | privileged renice helper | `lib/gnome_system_monitor/actions.rb` | partial — same |
| `src/action-impls/gsm-setaffinity.c`/`.h` | privileged affinity helper | `lib/gnome_system_monitor/dialogs.rb` | partial — same |
| `src/actions/gsm-actions.c`/`.h` | action dispatch/registration for the above | `lib/gnome_system_monitor/actions.rb` | exists |
| `src/actions/gsm_pkexec.cpp`/`.h` | pkexec escalation path | — | missing/unconfirmed |
| `src/actions/gsm_gksu.cpp`/`.h`, `gsm_gnomesu.cpp`/`.h` | legacy gksu/gnomesu escalation paths | — | not applicable to a from-scratch port of a current GNOME app — gksu/gnomesu are long-dead upstream legacy fallbacks; confirm pkexec-only is the right scope before assuming, don't silently drop |
| `scripts/gsm_execute_helper.c` | setuid helper binary for the GTK3-era escalation path | — | needs a decision: does the Ruby port need an equivalent privileged helper, or does it rely solely on polkit via `gsm-kill.c`'s current path? Not yet answered. |

## Settings / schema / data files

| Upstream file(s) | Kind | → `lib/*.rb` | Status |
|---|---|---|---|
| `src/org.gnome.gnome-system-monitor.gschema.xml.in` | GSettings schema | `lib/gnome_system_monitor/settings.rb` | exists |
| `src/gsm.gresource.xml.in` | GResource manifest (all `.ui` files, icons, `style.css`) | n/a (Ruby port has no `.ui`/gresource by design) | exists in spirit — confirm every resource it lists (icons, `pixmaps/arrow_mask.svg`, `pixmaps/arrow_overlay.svg`, `src/style.css`) has a Ruby-side equivalent, not just the `.ui` files |
| `src/style.css` | GTK CSS (process-row styling, etc.) | — | missing/unconfirmed — no `lib/*.rb` or asset file found carrying upstream's custom CSS classes |
| `data/org.gnome.SystemMonitor.metainfo.xml.in.in` | AppStream metadata (description, screenshots, release notes) | — | missing — no equivalent found under `lib/` or elsewhere on `ruby` |
| `data/org.gnome.SystemMonitor.desktop.in.in` + `-kde.desktop.in.in` | desktop launcher entries | — | missing — not yet checked for a packaged equivalent |
| `data/org.gnome.gnome-system-monitor.policy.in.in` | polkit policy file (for the kill/renice/affinity privileged actions) | — | missing — needed if `gsm-kill.c` parity requires a real polkit action |
| `data/icons/**` | app icon (regular + symbolic + Devel variant) | — | not checked this pass |

## Help (`help/C/*.page`)

Upstream ships a full Mallard help manual (`help/C/*.page`, 20 pages:
commandline, cpu-check, cpu-mem-normal, cpu-multicore, fs-device,
fs-diskusage, fs-info, fs-showall, mem-check, mem-swap, memory-map-use,
memory-map-what, net-bits, net-check, process-columns, process-explain,
process-files, process-forcequit, process-identify-file,
process-identify-hog, process-kill, process-loadaverage (stub),
process-many, process-priority-change, process-priority-what,
process-status, process-update-speed, solaris-mode, units) plus `index.page`
and `legal.xml`, translated into ~30 languages under `help/<lang>/`. No
equivalent found anywhere on `ruby`. This is a user-facing component (the
in-app Help action in `menus.ui` — `app.help` — points at this manual) and is
entirely missing, not out of scope by default.

## `po/` translation catalogue

`po/` carries ~180 `.po` files (full list in `po/LINGUAS`) plus
`po/POTFILES.in` naming 41 source files with translatable strings
(enumerated above under "Help" is separate; this is the app UI catalogue).
Translation parity is its own skill (`translation-parity`) and was not run
in this pass — flagging only that `po/` exists upstream at this size and
needs its own census, not a parity verdict here.

## Summary

- **Already exists and looks complete at the file-mapping level:** main
  window, application/entry point, preferences, renice dialog, affinity
  dialog, process properties window, memory-maps/open-files/search-open-files
  windows, disks view, shortcuts dialog, about dialog, menus, process table,
  process list/view, pretty table (icons), default columns, proc actions,
  proc dialogs, smooth refresh, number formatting, graph drawing, resources
  view, GSettings schema, `/proc` data gathering (via direct `/proc` reads,
  not the `GTop` gem — see finding below).
- **Missing outright:** cgroups column, systemd-unit column, SELinux column,
  custom GTK CSS (`src/style.css`), AppStream metainfo, desktop launcher
  files, polkit policy file, the entire Mallard help manual.
- **Partial / needs a focused read before calling it done:** column
  width/order persistence, the shared update-interval spin button widget,
  legacy treeview sort-indicator behavior, `e_date.c` smart date formatting,
  the custom color-picker button (`gsm_color_button.c`) used for graph colors
  in preferences, privileged kill/renice/affinity via polkit/pkexec (vs.
  unprivileged-only today), mem-map row parsing ownership.
- **Binding-gem finding (not a workaround to quietly keep):** `GTop` loads
  but every call raises `NameError` because ruby-gnome resolves libgtop's
  argument types by the raw lowercase GI name. `lib/gnome_system_monitor/proc_fs.rb`
  and friends read `/proc` directly instead, and say so in their own
  comments. This is confirmed unusable, not unexplored — record it, don't
  re-attempt it, and don't let "proc_fs.rb exists" read as "libgtop ported."
