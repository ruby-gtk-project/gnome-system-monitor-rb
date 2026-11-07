# Component identification — gnome-system-monitor-rb

This is the inventory half of the audit. See `.reports/component-parity.md`
for the comparison and verdicts, and `.reports/runtime-gate.md` for why none
of this could be confirmed by running anything.

## What this report is, and isn't

`.reports/component-inventory.md` already carries a file-by-file,
widget-by-widget inventory of both trees (upstream `.ui`/`.cpp` pairs unioned
against the port's `lib/gnome_system_monitor/*.rb` files), built per the
`component-identification` skill's method: `.ui` files read first as the
authoritative tree, then the `.cpp`/`.c` siblings read for actions,
accelerators, dynamic rows and runtime CSS the builder files don't show. It
is dated at commit `1204f8bb` and was re-checked against the current tip
(`844ed8ec`) for this audit: the only commit since is
`844ed8ec "Wire the GTK4/Adwaita/GLib/gettext binding gems in properly"`,
which touches `Gemfile`/`Gemfile.lock`/`gemset.nix`, not `lib/`. **The
inventory's widget/CSS/signal content is unchanged and still current.**

This audit does not re-derive that inventory from scratch (it would reproduce
the same 411-line document). Instead it:

1. confirms the inventory's scale claims against a fresh scan,
2. extends it with the translation (text) axis, which the component
   inventory explicitly defers to `translation-parity`,
3. notes one scope item the existing inventory does not cover.

## Scale, re-confirmed

| | Upstream | Port |
|---|---:|---:|
| widget rows (scan) | 478 | 142 |
| distinct widget types | 79 | 47 |
| distinct CSS classes applied | 11 | 5 |
| source files contributing UI | 10 `.ui` + 14 `.cpp`/`.c` | 27 `.rb` |
| translation messages (catalogue) | 374 | 344 |
| translation occurrences | 435 | 397 |
| `.po` languages | 99 | 99 |

(Translation numbers from `.claude/skills/translation-parity/scripts/catalogue.rb`
run against `origin/main` @ `ebfa2af8` and the `ruby` branch tip; full detail
in `.reports/translation-parity.md`.)

Every upstream top-level unit (application, three main-window pages, both
primary-menu variants, four dialogs, three detail windows, the pretty-table
icon lookup, the smooth-refresh governor) has a corresponding port file. What
the existing inventory and this audit agree on: **the gaps left are facets of
present components** (CSS classes, `GtkShortcutController` bindings, one
action, assorted per-row widgets and signal sources), not whole missing
screens. That shape is exactly why a per-axis comparison (`component-parity`)
matters more than a per-file presence check here — file-level coverage
already looks complete.

## One thing the existing inventory does not scope: `data/screenshots/`, `help/`, `.desktop`/`.policy`/`.metainfo`

These are listed as "present" in the existing inventory's "Data, schemas and
catalogue" table, but that table was not re-verified for byte/content parity
in this audit — only presence. Flagging as unverified rather than re-asserting
it as checked.

## Identification gap this audit adds: the text axis

`component-scan.sh` (and therefore the existing inventory) does not carry
strings — by design, per the `component-identification` skill, which defers
that to `translation-parity`'s census. That census was run for this audit
(see `.reports/translation-parity.md`) and surfaces components whose widgets
are present (so they'd read "present" in a widget-only inventory) but whose
*text* is not upstream's: the lsof window's title and refresh button, the Set
Affinity dialog's description, and — more systemically — every port string
built with Ruby's `%<name>s`-style named-format placeholders instead of
upstream's plain `%s`/`%u` tokens. Those are catalogued in
`.reports/translation-parity.md` and are not repeated here, but they are real
identification findings this audit is folding in because the
`component-parity` skill requires the four axes to be read together, and a
widget-only scan would have reported those rows clean.
