# Component inventory — gnome-system-monitor-rb

Survey of upstream (`origin/main`, the C/C++ GNOME System Monitor) against the
Ruby port on `ruby`. Produced per the `component-identification` skill, as
the opening survey of the fork: a file-level map of every user-facing unit,
not a per-widget scan — the app is already substantially ported, so the
useful artifact here is "what exists and where", for `component-parity` to
work from next.

Legend for **kind**: `window`, `dialog`, `page`, `view`, `row`/`model`,
`menu`, `shortcuts`, `preferences`, `actions`, `settings`, `data`
(GObject record with no on-screen widget of its own), `resource` (gschema /
gresource / stylesheet, not a widget).

## Windows, pages and views

| Upstream file(s) | → `lib/*.rb` | Kind | Present |
|---|---|---|---|
| `src/application.cpp`, `src/application.h` | `lib/gnome_system_monitor/application.rb` | app class (actions, accelerators, About/Preferences entry points) | yes |
| `src/interface.cpp`, `src/interface.h`, `data/interface.ui` | `lib/gnome_system_monitor/window.rb` | window (view switcher, search bar, primary menu, action bar) | yes |
| `data/menus.ui`, `src/interface.cpp` (menu wiring) | `lib/gnome_system_monitor/window.rb` (`main_menu`, `generic_menu`, `page_menu`, `process_popup_menu`, `priority_menu`) | menu | yes |
| `src/load-graph.cpp`, `src/load-graph.h`, `src/gsm-graph.c`, `src/gsm-graph.h` | `lib/gnome_system_monitor/graph.rb`, `lib/gnome_system_monitor/resources_view.rb` | page (Resources) + graph widget | yes |
| `src/proctable.cpp`, `src/proctable.h`, `src/prettytable.cpp`, `src/prettytable.h` | `lib/gnome_system_monitor/process_table.rb`, `lib/gnome_system_monitor/pretty_table.rb` | page (Processes) model/columns | yes |
| `src/proclist.cpp`, `src/proclist.h` | `lib/gnome_system_monitor/list_refresh.rb` | process list refresh | yes |
| `src/procinfo.cpp`, `src/procinfo.h` | `lib/gnome_system_monitor/process.rb`, `lib/gnome_system_monitor/proc_files.rb`, `lib/gnome_system_monitor/proc_fs.rb` | row/model (per-process data, read from `/proc`) | yes |
| `src/process_view` equivalent (split across `interface.cpp`/`proctable.cpp`) | `lib/gnome_system_monitor/process_view.rb` | view (Processes page UI: toolbar, search, column view) | yes |
| `src/disks.c`, `src/disks.h`, `data/disks.ui` | `lib/gnome_system_monitor/disks_view.rb` | page (File Systems) | yes |
| `src/disk.c`, `src/disk.h` | `lib/gnome_system_monitor/disks_view.rb` (disk row) | row/model | yes |
| `src/smooth_refresh.cpp`, `src/smooth_refresh.h` | `lib/gnome_system_monitor/smooth_refresh.rb` | behaviour (refresh pacing) | yes |
| `src/defaulttable.h` | `lib/gnome_system_monitor/columns.rb` | data (default column set) | yes |
| `src/column-view-persister.c`, `src/column-view-persister.h` | `lib/gnome_system_monitor/settings.rb` / `lib/gnome_system_monitor/process_table.rb` (column width/order/visibility persisted to GSettings) | behaviour | yes |
| `src/row.rb` equivalent — `src/mem-map.c`/`.h`, `src/open-file.cpp`/`.h` (GObject row records) | `lib/gnome_system_monitor/row.rb` | data (generic row for the three detail windows) | yes |

## Dialogs and secondary windows

| Upstream file(s) | → `lib/*.rb` | Kind | Present |
|---|---|---|---|
| `src/procdialogs.cpp`, `src/procdialogs.h` (confirm-signal dialog, failure report) | `lib/gnome_system_monitor/dialogs.rb` (`confirm_signal`, `alert_dialog`, `report`) | dialog | yes |
| `data/renice.ui`, `src/action-impls/gsm-setpriority.c`/`.h` | `lib/gnome_system_monitor/dialogs.rb` (`ReniceDialog`) | dialog | yes |
| `data/setaffinity.ui`, `src/setaffinity.cpp`/`.h`, `src/action-impls/gsm-setaffinity.c`/`.h` | `lib/gnome_system_monitor/dialogs.rb` (`AffinityDialog`) | dialog | yes |
| `src/action-impls/gsm-kill.c`/`.h` | `lib/gnome_system_monitor/dialogs.rb` (`confirm_signal`) + `lib/gnome_system_monitor/actions.rb` | dialog + action | yes |
| `data/procproperties.ui`, `src/procproperties.cpp`/`.h` | `lib/gnome_system_monitor/process_properties.rb` | dialog (process properties, incl. systemd/cgroup/SELinux fields) | yes |
| `data/memmaps.ui`, `src/memmaps.cpp`/`.h`, `src/mem-map.c`/`.h` | `lib/gnome_system_monitor/detail_windows.rb` (`memory_maps`) | window (uses `DetailView`) | yes |
| `data/openfiles.ui`, `src/openfiles.cpp`/`.h`, `src/open-file.cpp`/`.h` | `lib/gnome_system_monitor/detail_windows.rb` (`open_files`) | window (uses `DetailView`) | yes |
| `data/lsof.ui`, `src/lsof.cpp`/`.h` | `lib/gnome_system_monitor/detail_windows.rb` (search for open files) | window (uses `DetailView`) | yes |
| shared shape of the three above | `lib/gnome_system_monitor/detail_view.rb` | view (shared titled window + sortable `GtkColumnView`) | yes |
| `data/preferences.ui`, `src/prefsdialog.cpp`/`.h`, `src/update_interval.cpp`/`.h` | `lib/gnome_system_monitor/preferences.rb` | dialog (`AdwPreferencesDialog`, 3 pages) | yes |
| `data/shortcuts-dialog.ui` | `lib/gnome_system_monitor/about.rb` (`ShortcutsDialog`) | shortcuts window | yes |
| About dialog wiring in `src/interface.cpp`/`application.cpp` | `lib/gnome_system_monitor/about.rb` (`About`) | dialog | yes |

## Actions, settings and privilege escalation

| Upstream file(s) | → `lib/*.rb` | Kind | Present |
|---|---|---|---|
| `src/actions/gsm-actions.c`/`.h` | `lib/gnome_system_monitor/actions.rb` | actions | yes |
| `src/actions/gsm_gksu.cpp`, `gsm_gnomesu.cpp`, `gsm_pkexec.cpp` (+`.h`) | `lib/gnome_system_monitor/actions.rb` (root-escalated kill via `pkexec`) | actions (privilege escalation) | yes |
| `src/settings-keys.h`, `src/org.gnome.gnome-system-monitor.gschema.xml.in` | `lib/gnome_system_monitor/settings.rb` | settings (GSettings wrapper) | yes — all ~80 keys accounted for (window/maximized, process/disk/graph behaviour, per-column width/visible × 27 process columns + per-column × disks, sort, graph colors `cpu-colors`/`mem-color`/`swap-color`/`net-in-color`/`net-out-color`/`disk-read-color`/`disk-write-color`, panel-expanded flags) |
| `src/util.cpp`, `src/util.h` (unit formatting, misc helpers) | `lib/gnome_system_monitor/units.rb`, `lib/gnome_system_monitor/system_stats.rb` | utility | yes |
| `src/legacy/e_date.c`/`.h` (date formatting) | covered by `lib/gnome_system_monitor/units.rb` / `process_properties.rb` formatting | utility | yes |
| `src/legacy/gsm_color_button.c`/`.h` | `lib/gnome_system_monitor/resources_view.rb` (`color_button`, per-series color buttons) | widget helper | yes |
| `src/legacy/treeview.c`/`.h` | superseded by `GtkColumnView` throughout (`process_table.rb`, `disks_view.rb`, `detail_view.rb`) — no direct port needed, behaviour reproduced | n/a | yes (via GtkColumnView) |
| `src/cgroups/gsm-cgroups.c`/`.h` | `lib/gnome_system_monitor/process.rb`, `process_properties.rb`, `columns.rb` | data + column | yes |
| `src/systemd/gsm-systemd.c`/`.h` | `lib/gnome_system_monitor/process.rb`, `process_properties.rb`, `columns.rb` | data + column | yes |
| `src/selinux/gsm-selinux.c`/`.h` | `lib/gnome_system_monitor/process.rb`, `process_properties.rb`, `columns.rb` | data + column | yes |
| `src/main.cpp` | `lib/gnome_system_monitor.rb` | entry point | yes |

## Resources (non-widget, still user-facing)

| Upstream file(s) | → port location | Kind | Present |
|---|---|---|---|
| `src/style.css` | `data/style.css` | stylesheet | yes |
| `src/org.gnome.gnome-system-monitor.gschema.xml.in` | `lib/gnome_system_monitor/settings.rb` + GSettings schema install (`lib/gnome_system_monitor/paths.rb` `install_schemas!`) | GSettings schema | yes |
| `src/gsm.gresource.xml.in` | n/a — Ruby port has no `.ui`/GResource bundle by house style (widgets built declaratively in code) | resource manifest | n/a by design |
| `data/org.gnome.SystemMonitor.metainfo.xml.in.in`, `.desktop.in.in`, `.policy.in.in`, `.service.in` | not yet surveyed — packaging metadata, out of scope for widget parity | packaging | not surveyed |
| `help/C/*.page` (user documentation) | not ported | documentation | no — out of scope unless requested |
| `po/*.po` (translation catalogue, ~140 locales) | `lib/gnome_system_monitor/i18n.rb` provides the `_()`/`Translations` mechanism; no locale catalogue has been ported yet | i18n | partial — mechanism exists, catalogue not ported |

## Gaps found

None of the user-facing component files are missing a `lib/*.rb` counterpart.
Two items are explicitly out of scope by design or not yet addressed, not
mis-ported:

- **Translation catalogue** (`po/*.po`): the `i18n.rb` machinery (`_()`
  lookup) exists but no `.po`/`.mo` catalogue has been carried over, so the
  port is English-only. This is a `translation-parity` concern, not a
  component gap.
- **Packaging/metadata files** (`.desktop.in.in`, `.metainfo.xml.in.in`,
  `.policy.in.in`, `.service.in`, Flatpak manifest): not surveyed here since
  they produce no widget; flag for a separate packaging pass if the port
  needs to be distributable.
- **Help pages** (`help/C/*.page`): user documentation, not UI; not ported
  and not required for UI parity.

Everything else — every window, dialog, page, row kind, menu, the shortcuts
window, preferences, GSettings-backed behaviour, and the three
action-implementation dialogs (kill/renice/setaffinity) including the
pkexec/gksu/gnomesu privilege-escalation path — already has a corresponding
file in `lib/`. The next useful step is `component-parity` on individual
units (starting with `window.rb` and `process_table.rb`, the two largest) to
check CSS classes, signals and action names match upstream widget-for-widget,
not file inventory.
