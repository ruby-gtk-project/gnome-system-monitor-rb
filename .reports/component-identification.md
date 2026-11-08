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
(`57971f35`) for this audit. Commits since the prior round's check
(`844ed8ec`) are `b921d443` (`.reports/` only), `83589698` (ports
`src/column-view-persister.c`'s drag-reorder persistence -- a real `lib/`
addition the existing inventory predates and does not list), and
`57971f35` (devShell fix plus two bug fixes, not new widgets). **The
inventory's widget/CSS/signal content is current except for the
column-view-persister addition, added as a named gap below rather than
silently left unlisted.**

### Gap added this round: column-view-persister.c's port is unlisted anywhere

`83589698` ported `src/column-view-persister.c` into the port, but
`.reports/component-inventory.md` predates that commit and has no row for
it, and no step in `test/drive_window.rb` exercises column reordering at
all (confirmed against the driven-step list in `.reports/test-parity.md`).
This is a real component with zero verification coverage of any kind this
round -- not re-confirmed present-and-correct, not driven, not
screenshotted -- simply absent from every ledger. Named here rather than
letting its absence from the inventory read as done.

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

**This audit checked `help/C` file-by-file and the flag above was correct to
be suspicious: `16704eb4` ("Port the two missing help/C Mallard pages") did
not in fact close the help/C file-set gap.** Diffing
`find help/C -maxdepth 1 -name '*.page'` between `origin/main` @ `ebfa2af8`
and `ruby` @ `8e919988`:

```
upstream: 29 .page files
port:     28 .page files
missing:  process-forcequit.page
```

`process-forcequit.page` is itself a stub upstream (`status="stub"`, with an
inline reviewer comment arguing it may be redundant with
`process-end-kill.page`) and no other upstream page `xref`s it — but it is a
real file upstream ships in `help/C`, and the port does not ship it. Per
`component-parity`'s own rule, "not applicable" and "upstream itself flags it
as maybe-redundant" are not a third option; this is a one-file gap, not a
zero. Scope note: this check covered `help/C` only — the 98 other `help/<lang>`
directories were not diffed file-by-file in this audit, so whether the port's
translated help trees match upstream's is still unverified, not confirmed.

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
