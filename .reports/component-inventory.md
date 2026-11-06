# Component inventory — gnome-system-monitor → gnome-system-monitor-rb

Upstream spec: `origin/main` (C/C++ + GtkBuilder `.ui`). Port: `ruby` branch,
`lib/gnome_system_monitor/*.rb`.

Method: the `component-identification` skill. Upstream's declarative UI
(`data/*.ui`, `data/menus.ui`, `data/shortcuts-dialog.ui`) was read first since
it *is* the component inventory; the `.cpp`/`.c` siblings were then read for the
actions, accelerators, dynamic rows and CSS the builder files do not cover.
Upstream splits almost every component across two files (`data/foo.ui` + its
`src/foo.cpp`), so rows are unioned per port file before comparing.

The raw scan is in the scratchpad, not here: its `css` stream is contaminated by
`#define` resolution from unrelated trees on this machine (it reported
`spotify`, `lyrics-label`, `applemusic`), so CSS below comes from reading the
`.ui` files, not from the TSV.

---

## Scale

Re-surveyed at `1204f8bb` (after `eed22dda`, which closed four of the
previous survey's top gaps).

| | Upstream | Port |
|---|---:|---:|
| widget rows (scan) | 478 | 142 |
| distinct widget types | 79 | 47 |
| distinct CSS classes applied | 11 | 5 |
| source files contributing UI | 10 `.ui` + 14 `.cpp`/`.c` | 27 `.rb` |

Every upstream component now has a port file: all three pages, all three detail
windows, all four dialogs, both primary-menu variants, the process-icon table
and the smooth-refresh governor. What remains is not missing components but
missing *facets* of present ones — CSS classes, `GtkShortcutController`
shortcuts, one action (`win.show-page`), and a handful of per-row widgets
(disks device icon, lsof process icon) and live-update signal sources.

---

## Component map

Ordered as a user meets them: the application, the main window, its three
pages, its menus, then the dialogs and detail windows.

### Application

#### `src/application.cpp`, `src/main.cpp` → `lib/gnome_system_monitor/application.rb` — present

The `Gtk::Application`, the four app actions behind the primary menu, the CSS
provider and the icon theme search path.

| Component | × | CSS | Signals / actions | Notes |
|---|---:|---|---|---|
| `Gtk.Application` | 1 | — | `startup`, `activate` | port uses `Gtk::Application`, not `Adwaita::Application` (binding quirk) |
| `app.quit` action | 1 | — | `<Control>Q` | present |
| `app.help` action | 1 | — | `F1` | present, via `Gtk::UriLauncher` |
| `app.lsof` action | 1 | — | — | present |
| `app.preferences` action | 1 | — | `<Primary>comma` | action present, **accelerator missing** |
| `window.close` accel | 1 | — | `<Control>W` | present |
| `Gtk.CssProvider` (`style.css`) | 1 | `loadgraph` | — | present |

**Gap:** `app.preferences` is not given `<Primary>comma`
(`src/application.cpp:548`).

#### `src/prettytable.cpp`, `src/prettytable.h`, `src/defaulttable.h` → `lib/gnome_system_monitor/pretty_table.rb` — present

Upstream's per-process icon lookup, in upstream's order: the installed
application owning the executable (flatpaks by the app id in their cgroup), the
icon theme under the process's own name, the well-known-command table from
`defaulttable.h`, the kernel-thread icon, then a plain executable icon. The
applications directories are watched so an install or removal rebuilds the
cache, and an icon-theme change re-resolves every process. Candidates stop at
`Gio::Icon` rather than `Gdk::Texture` because the port's name cell is a
`Gtk::Image` in a `Gtk::ColumnView`, not a `GtkCellView`.

**Remaining:** the lsof window's Process cell still does not use it.

#### `src/smooth_refresh.cpp`, `src/smooth_refresh.h` → `lib/gnome_system_monitor/smooth_refresh.rb` — present

Upstream's adaptive refresh, with its thresholds and fuzzy logic: this
process's CPU time from `/proc/self/stat` and the machine's from `/proc/stat`,
stretching the process-list interval when System Monitor's own CPU share runs
high. `window.rb:237` ticks at whatever it settles on, standing the old
`GLib::Timeout` source down when the interval moves. Behind the "Enable
_Smooth Refresh" switch (`preferences.rb`) and the `smooth-refresh` key
(`settings.rb`).

#### `src/update_interval.cpp` → folded into `window.rb` (`start_timers`/`restart_timers`) — present

#### `src/util.cpp`, `src/legacy/e_date.c` → `lib/gnome_system_monitor/units.rb` — present

Size, rate, volume, percentage and nice-level formatting, plus the date
formatting `e_date.c` does.

---

### Main window

#### `data/interface.ui` + `src/interface.cpp` → `lib/gnome_system_monitor/window.rb` — present

The window shell: toolbar view, header bar, view switcher, search bar, primary
menu button, the view stack and the processes action bar.

| Widget | × | CSS | Signals / actions | Port |
|---|---:|---|---|---|
| `Adw.ApplicationWindow` | 1 | `view` | `close-request`, `notify::suspended` | present (`notify::suspended` **missing**) |
| `Adw.ToolbarView` (620×480) | 1 | — | — | present |
| `Adw.HeaderBar` | 1 | — | — | present |
| `Adw.ViewSwitcher` (policy wide) | 1 | — | — | present |
| `Gtk.ToggleButton` search | 1 | — | `win.search` | present |
| `Gtk.MenuButton` primary | 1 | — | menu model swapped per page | present, **always the process menu** |
| `Gtk.SearchBar` | 1 | — | bound bidirectionally to search button; `key-capture-widget` = window | present; **key capture widget not set** |
| `Gtk.SearchEntry` | 1 | — | `search-changed` | present |
| `Adw.ViewStack` | 1 | — | `notify::visible-child` | present |
| `Adw.ViewStackPage` | 3 | — | `_Resources` / `_Processes` / `_File Systems`, `use-underline` | present |
| `Gtk.Revealer` (slide-up) | 1 | — | revealed on selection | present |
| `Gtk.ActionBar` | 1 | — | — | present |
| `Gtk.Button` End Process | 1 | `destructive-action` | `win.send-signal-term`, `GtkShortcut` `Delete` | button present, **`Delete` shortcut missing** |
| `Gtk.Button` properties | 1 | — | `win.process-properties` | present |
| `Gtk.PopoverMenu` process popup | 1 | no arrow | parented to the scrolled window | present |

Window actions (`src/interface.cpp:873`, 17 entries):

| Action | State | Accel | Port |
|---|---|---|---|
| `win.about` | — | — | present |
| `win.shortcuts` | — | `<Control>question` | present |
| `win.search` | — | `<Control>F` | present |
| `win.send-signal-stop` | — | `<Primary>s` | present |
| `win.send-signal-cont` | — | `<Primary>c` | present |
| `win.send-signal-term` | — | `<Primary>t` | present |
| `win.send-signal-kill` | — | `<Primary>k` | present |
| `win.priority` | `i`, default `0` | — | present (32 = custom → renice) |
| `win.set-affinity` | — | `<Alt>s` | present |
| `win.memory-maps` | — | `<Control>m` | present |
| `win.open-files` | — | `<Control>o` | present |
| `win.process-properties` | — | `<Alt>Return` | present |
| `win.refresh` | — | `<Control>r` | present |
| `win.show-page` | `s`, default `'resources'` | `<Alt>1/2/3` | **missing** |
| `win.show-whose-processes` | `s`, default `'all'` | — | present |
| `win.show-dependencies` | boolean, default `false` | `<Primary>d` | present |

**Gaps in this component:**
1. `win.show-page` radio action and the `<Alt>1` / `<Alt>2` / `<Alt>3`
   accelerators — the shortcuts dialog advertises all three.
2. `gtk_search_bar_set_key_capture_widget` — typing in the Processes page does
   not open the search bar.
4. The `Delete` `GtkShortcutController` on the End Process button.
5. `notify::suspended` handling (upstream stops its timers when the window is
   suspended).

#### `data/menus.ui` → `lib/gnome_system_monitor/window.rb` (`main_menu`, `process_popup_menu`, `priority_menu`) — partial

Three menu models, 27 items total.

| Menu | Items | Port |
|---|---:|---|
| `generic-window-menu` | 5 (Search for Open Files, Preferences, Help, Keyboard Shortcuts, About) | present as `Window#generic_menu`; shared sections built once |
| `process-window-menu` | 9 (Refresh; Active/All/My Processes; Show Dependencies; + the generic 5) | present as `main_menu` |
| `process-popup-menu` | 13 incl. `_Change Priority` submenu (Very High/High/Normal/Low/Very Low/Custom) and Set Affinity, Pause, Resume, End, Force Stop | present |

#### `data/shortcuts-dialog.ui` → `lib/gnome_system_monitor/about.rb` (`ShortcutsDialog`) — present

`Adw.ShortcutsDialog` with 6 `Adw.ShortcutsSection`s and 21
`Adw.ShortcutsItem`s. The port loads upstream's `.ui` through `Gtk::Builder`
(the bindings cannot construct the dialog directly), and `data/shortcuts-dialog.ui`
is vendored into the port. Three of its items (`<Alt>1/2/3`) point at the
missing `win.show-page` action.

---

### Resources page

#### `data/interface.ui` (resources subtree) + `src/load-graph.cpp` + `src/gsm-graph.c` + `src/legacy/gsm_color_button.c` → `lib/gnome_system_monitor/resources_view.rb` + `lib/gnome_system_monitor/graph.rb` — present

| Widget | × | CSS | Signals | Port |
|---|---:|---|---|---|
| `Gtk.ScrolledWindow` | 1 | — | — | present |
| `Gtk.Box` vertical (12/30/24/24 margins) | 1 | — | — | present |
| `Gtk.Expander` | 4 | — | `notify::expanded` → settings | present (CPU, Memory and Swap, Network, Disk) |
| `Gtk.Label` bold section header | 4 | — | — | present |
| `Gtk.Grid` legend table | 4 | — | — | present |
| `Gtk.Label` legend | 10 fixed + 1 per CPU | `dim-label` | — | present |
| `GsmGraph` / `Gtk.DrawingArea` | 4 | `loadgraph` | `css-changed`, draw func | present as `LoadGraph` (Cairo draw func) |
| `GsmColorButton` | 2 + 4 + 1/CPU | — | `color-set` → settings | present |
| `Gtk.LevelBar` | — | — | — | n/a |

Dynamic: one CPU row (color button + label) per core, built in a loop — a
repeater. Strings: `CPU`, `CPU%d`, `%.1f%%`, `not available`,
`%s (%.1f%%) of %s`, `Cache %s`.

The arrow overlay `gsm_color_button.c` draws on the colour swatch
(`pixmaps/arrow_mask.svg`, `arrow_overlay.svg`) is now vendored at
`data/pixmaps/`.

---

### Processes page

#### `src/proctable.cpp`, `src/proclist.cpp`, `src/procinfo.cpp` → `lib/gnome_system_monitor/process_view.rb`, `process_table.rb`, `columns.rb`, `row.rb`, `process.rb`, `list_refresh.rb`, `proc_fs.rb` — present

Upstream still builds this page in source (a `GtkTreeView` with 27 columns);
the port rebuilt it as a `Gtk::ColumnView`.

| Component | × | CSS | Signals | Port |
|---|---:|---|---|---|
| `Gtk.ColumnView` (upstream: `Gtk.TreeView`) | 1 | `data-table` (port only) | `activate`, right-click → popup | present |
| column | 27 | `numeric` on the numeric ones | sortable, resizable, reorderable, per-column visibility | present; **`numeric` CSS class missing** |
| icon + name cell | 1 | — | — | present, **but a single generic icon** (see `prettytable.cpp`) |
| summed column headers (`Gtk.Box` + 2 labels) | 10 | — | — | present (`process_view.rb:23`) |
| tooltip | per row | — | `COL_TOOLTIP` | present |

The 27 column titles — Name, User, Status, Virtual Memory, Resident Memory,
Writable Memory, Shared Memory, X Server Memory, CPU, CPU Time, Started, Nice,
ID, Security Context, Command Line, Memory, Waiting Channel, Control Group,
Unit, Session, Seat, Owner, Disk Read Total, Disk Write Total, Disk Read, Disk
Write, Priority — are all in `columns.rb`.

#### `src/column-view-persister.c` → folded into `process_view.rb` / `disks_view.rb` (`restore_columns`, `save_column_widths`, `save_sort`) — present

---

### File Systems page

#### `data/disks.ui` + `src/disks.c` + `src/disk.c` → `lib/gnome_system_monitor/disks_view.rb` — partial

| Widget | × | CSS | Signals | Port |
|---|---:|---|---|---|
| `Adw.Bin` template root | 1 | — | — | present (plain `Gtk::ScrolledWindow` root) |
| `Gtk.ColumnView` `single-click-activate` | 1 | — | `activate` → `activate_disk` | present, **`single-click-activate` and `activate` handler missing** |
| `Gtk.SingleSelection` / `Gtk.SortListModel` / `GListStore` | 1 each | — | — | present |
| `Gtk.ColumnViewColumn` | 7 (Device, Directory, Type, Total, Free, Available, Used) | — | string/numeric sorters | present |
| `Gtk.Image` device icon (pixel-size 32) | 1/row | `icon-dropshadow` | `gicon` from `GsmDisk:icon` | **missing** |
| `Gtk.Label` | 1–2/row | — | — | present |
| `Gtk.LevelBar` 0–100 | 1/row | — | bound to `percentage` | present |
| `GsmColumnViewPersister` | 1 | — | `disksview` schema | present |
| `GSignalGroup` on `GVolumeMonitor` | 1 | — | mount added/removed | **missing** — the port only re-reads on its timer |

**Gaps:** the per-row device icon and its `icon-dropshadow` class; the
`activate` handler that opens the mount point; live `GVolumeMonitor` updates.

---

### Dialogs

#### `data/preferences.ui` + `src/prefsdialog.cpp` → `lib/gnome_system_monitor/preferences.rb` — partial

| Widget | × | CSS | Signals | Port |
|---|---:|---|---|---|
| `Adw.PreferencesDialog` 700×700, `search-enabled` | 1 | — | opens on the page matching the current tab | present; **`search-enabled`, the 700×700 size and the page-follows-tab behaviour missing** |
| `Adw.PreferencesPage` | 3 (Resources, Processes, File Systems) | — | `icon-name` | present; **page icons missing** |
| `Adw.PreferencesGroup` | 8 | — | — | present; **the two "Information Fields" descriptions missing** |
| `Adw.SpinRow` update interval | 3 | — | `notify::value` → settings | present |
| `Adw.SwitchRow` | 10 | — | `g_settings_bind` | present |
| `Gtk.Scale` chart data points | 1 | — | `value-changed` → settings | present |
| `Adw.SwitchRow` per column (Information Fields) | 27 + 7 | — | bound to `col-N-visible` / `col-<id>-visible` | present, both repeaters |

Missing group descriptions: "Process information shown in list", "File system
information shown in list".

#### `src/procdialogs.cpp` (kill confirmation) → `lib/gnome_system_monitor/dialogs.rb` (`Dialogs.confirm_signal`) — present

`Adw.AlertDialog`, `cancel` + `apply` (`destructive`), with the singular and
plural headings for Force Stop / End / Temporarily Stop, and the three bodies.
Also carries `Dialogs.report` for the failure alert.

#### `data/renice.ui` + `src/procdialogs.cpp` → `lib/gnome_system_monitor/dialogs.rb` (`ReniceDialog`) — present

`Adw.AlertDialog` with `cancel` / `change` (`destructive`), the nice-value
`Gtk.Scale` on a `Gtk.Adjustment` (−20…19), the mnemonic label and the live
priority label.

#### `data/setaffinity.ui` + `src/setaffinity.cpp` → `lib/gnome_system_monitor/dialogs.rb` (`AffinityDialog`) — partial

Upstream is an `Adw.Window` with a header bar (Cancel / Apply, no title
buttons), an `Adw.PreferencesPage`, a `Gtk.ListBox` `boxed-list` of
`Adw.SwitchRow` (one per CPU plus "_Run on all CPUs"), and a bottom
`Gtk.ListBox` `background` holding "Apply to Child _Threads".

**Gap:** the port builds an `Adw.AlertDialog` with a `Gtk::Grid` of
`Gtk::CheckButton`s instead — same behaviour, different presentation. Missing:
`Adw.Window` + header bar shell, `Adw.SwitchRow` rows, the `boxed-list` and
`background` CSS classes, and the Escape `GtkShortcutController`.

#### `data/procproperties.ui` + `src/procproperties.cpp` → `lib/gnome_system_monitor/process_properties.rb` — partial

| Widget | × | CSS | Signals | Port |
|---|---:|---|---|---|
| `Adw.Window` 600×675 (min 360×294) | 1 | — | `destroy-with-parent` | present |
| `Adw.ToolbarView` + `Adw.HeaderBar` | 1 | — | — | present |
| `Adw.PreferencesPage` | 1 | — | — | present |
| `Adw.PreferencesGroup` | 4 (Details, Status, Usage, unnamed) | — | — | present |
| `Adw.ActionRow` + `Gtk.Label` `selectable` | 12 | `numeric` | — | present; **`numeric` missing** |
| `Adw.ActionRow` subtitle-selectable | 4 (Security Context, Command Line, Waiting Channel, Control Group) | `property`, `numeric` | — | present; **both classes missing** |
| `Gtk.ActionBar` + 2 buttons | 1 | — | `procprop.send-signal-term` / `-kill` | present |
| `Gtk.MenuButton` More Actions | 1 | `flat` | `view-more-symbolic`, direction up, menu model | **missing** |
| `GtkShortcutController` Escape → `procprop.close` | 1 | — | — | **missing** |

---

### Detail windows

#### `data/memmaps.ui` + `src/memmaps.cpp` + `src/mem-map.c` → `lib/gnome_system_monitor/detail_view.rb` + `detail_windows.rb` (`memory_maps`) — present

`Adw.Window` 620×400, `Adw.ToolbarView`, `Adw.HeaderBar` with
`Adw.WindowTitle`, `Gtk.ColumnView` with 11 columns (Filename, VM Start, VM
End, VM Size, Flags, VM Offset, Private Clean, Private Dirty, Shared Clean,
Shared Dirty, Device, Inode).

**Gaps:** the `monospace` and `numeric` cell CSS classes; the Escape
`GtkShortcutController`; the `view` class on the window.

#### `data/openfiles.ui` + `src/openfiles.cpp` + `src/open-file.cpp` → `detail_view.rb` + `detail_windows.rb` (`open_files`) — present

`Adw.Window` 575×400 with 3 columns (FD, Type, Object). Same three gaps
(`view` class, Escape shortcut).

#### `data/lsof.ui` + `src/lsof.cpp` → `lib/gnome_system_monitor/detail_windows.rb` (`SearchOpenFiles`) — partial

| Widget | × | CSS | Signals / actions | Port |
|---|---:|---|---|---|
| `Adw.Window` 575×400 | 1 | `view` | title bound to a `format_title` closure over match count + query | present; **title is static, `view` class missing** |
| `Gtk.ToggleButton` search (header start) | 1 | — | bound to the search bar | **missing** — the port pins the search bar open |
| `Gtk.Button` refresh (header end) | 1 | — | `lsof.refresh`, `<Primary>R` | **missing**, along with the `lsof.refresh` action |
| `Gtk.SearchBar` + `Gtk.SearchEntry` | 1 | — | `search-changed` | present |
| `Gtk.CheckButton` Case Insensitive | 1 | — | `toggled` | present |
| `Gtk.ColumnView`, `Gtk.NoSelection` + `Gtk.FilterListModel` + `Gtk.StringFilter` | 1 | — | incremental filtering | present (filtering done in Ruby, not a `Gtk.StringFilter`) |
| columns Process / PID / Filename | 3 | — | — | present |
| `Gtk.Image` process icon in the Process cell | 1/row | — | `paintable` from `GsmOpenFile:icon` | **missing** (depends on `prettytable.cpp`) |
| `GtkShortcutController` Escape, `<Primary>R` | 1 | — | — | **missing** |

---

### Privileged actions

#### `src/actions/gsm-actions.c`, `src/actions/gsm_pkexec.cpp`, `gsm_gksu.cpp`, `gsm_gnomesu.cpp`, `src/action-impls/gsm-kill.c`, `gsm-setaffinity.c`, `gsm-setpriority.c`, `scripts/gsm_execute_helper.c` → `lib/gnome_system_monitor/actions.rb` + `bin/` — present

Try directly, fall back to `pkexec` on `EPERM`/`EACCES`. The three helpers live
in `bin/` and `data/gnome-system-monitor.policy` is upstream's policy file.

#### `src/selinux/gsm-selinux.c`, `src/cgroups/gsm-cgroups.c`, `src/systemd/gsm-systemd.c` → `lib/gnome_system_monitor/proc_fs.rb` — present

Security context, cgroup name, systemd unit/session/seat/owner, all read from
`/proc` and `/run/systemd` rather than through the libraries.

#### `src/legacy/treeview.c` → n/a

`GtkTreeView` plumbing the port does not need (it uses `Gtk::ColumnView`).

---

### Data, schemas and catalogue

| Upstream | Port | Status |
|---|---|---|
| `src/org.gnome.gnome-system-monitor.gschema.xml.in` | `data/gnome-system-monitor.gschema.xml` | present, keys unchanged |
| `src/gsm.gresource.xml.in` | n/a — the port loads from `data/` via `paths.rb` | n/a by design |
| `src/style.css` | `data/style.css` | present |
| `data/org.gnome.SystemMonitor.desktop.in.in` | `data/org.gnome.SystemMonitor.desktop` | present |
| `data/org.gnome.SystemMonitor.metainfo.xml.in.in` | `data/org.gnome.SystemMonitor.metainfo.xml` | present |
| `data/org.gnome.gnome-system-monitor.policy.in.in` | `data/gnome-system-monitor.policy` | present |
| `data/gnome-system-monitor-kde.desktop.in.in` | `data/gnome-system-monitor-kde.desktop` | present |
| icons (app, symbolic, processes, resources) | `data/icons/` | present |
| `pixmaps/arrow_mask.svg`, `arrow_overlay.svg` | `data/pixmaps/` | present |
| `po/` (99 languages) | `po/` (99 `.po` + LINGUAS + POTFILES.in) | present, at parity |
| `help/` (user manual, 26 C sources + 25 catalogues) | `help/` | present; `make help` merges through itstool as `gnome.yelp()` does |
| `data/screenshots/` | `data/screenshots/` (4, incl. a new process-properties shot) | present |

---

## Summary of gaps, worst first

Closed since the first survey: `prettytable.cpp`, `smooth_refresh.cpp`,
`generic-window-menu`, the KDE desktop file, `pixmaps/arrow_*.svg`, `help/` and
the `po/` shortfall.

1. **`win.show-page` action + `<Alt>1/2/3`** — advertised in the shortcuts
   dialog, not installed. Nothing in `lib/` mentions it. (`window.rb`)
2. **Disks device icon + `activate` handler + `GVolumeMonitor`** — no
   `Gtk::Image` cell, no `single-click-activate`, no mount-added/removed
   signals; the page only re-reads on its timer. (`disks_view.rb`)
3. **Process properties "More Actions" `Gtk.MenuButton`** — no `MenuButton` in
   the file. (`process_properties.rb`)
4. **lsof search toggle, refresh button + `lsof.refresh` action, and the
   match-count window title** — the port pins the search bar open and keeps a
   static title. (`detail_windows.rb`)
5. **lsof per-row process icon** — `pretty_table.rb` now exists but the Process
   cell does not call it. (`detail_windows.rb`)
6. **Set Affinity presentation** — upstream is an `Adw.Window` with a header
   bar and a `boxed-list` of `Adw.SwitchRow`; the port is an
   `Adwaita::AlertDialog` with a `Gtk::Grid` of `Gtk::CheckButton`s
   (`dialogs.rb:233`). Same behaviour, different control.
7. **CSS classes not carried over** — the port applies only
   `destructive-action`, `data-table`, `dim-label`, `view`, `loadgraph`.
   Missing: `numeric` (12 procprop labels, 4 rows, 10 process columns, 6
   memmap cells, 2 disks cells), `property` (4 procprop rows), `monospace`
   (4 memmap cells), `icon-dropshadow` (disks icon), `flat` (procprop menu
   button), `boxed-list` and `background` (affinity), and `view` on the lsof /
   memmaps / openfiles windows.
8. **`GtkShortcutController`s — none exist in the port at all** — `Delete` on
   End Process; `Escape` on procproperties, setaffinity, memmaps, openfiles,
   lsof; `<Primary>R` on lsof.
9. **Search bar key capture widget** — typing on the Processes page does not
   open search.
10. **`notify::suspended`** — timers keep running when the window is suspended.
11. **Preferences polish** — `search-enabled`, 700×700 default size, the three
    page icons, the two "Information Fields" group descriptions, and opening on
    the page matching the current tab.
12. **`app.preferences` accelerator** `<Primary>comma` —
    `application.rb:46-48` sets only `app.quit`, `app.help` and `window.close`.
