# Translation parity — gnome-system-monitor-rb

| | |
|---|---|
| Upstream | `main` @ `ebfa2af8` |
| Port | `ruby` @ `844ed8ec` |
| Port | `ruby` @ `57971f35` (re-checked this round; not re-run from scratch — see note below) |
| Domain | `gnome-system-monitor` |
| Upstream messages | 374 |
| Ported | **334** |
| Gaps | **40** |
| Extra (untranslated) | **10** |
| Kind mismatch (plural↔single) | **1** |
| Upstream occurrences | 435 across 374 messages (46 reused) |
| Port occurrences | 397 |
| Upstream languages | 99 `.po` files, 29,735 translated, 1,739 untranslated, 247 fuzzy |
| Languages shipped by the port | 99 (file set matches, not independently verified string-for-string) |
| Unresolved markers (upstream) | 2 — `src/proctable.cpp:435`, a `switch` on `titles[i]` whose literal strings were not resolved by the census; carried as a scanner lead, not closed here |

**Note added this round**: the only commits between the prior census and
the current tip (`b921d443`, `83589698`, `57971f35`) touch
`.reports/`, `column-view-persister.c`'s port, and the devShell/two bugfixes
respectively — none add, remove, or reword a user-facing string in `lib/`.
The full catalogue script was not re-run this round for budget reasons; the
numbers and gap list below are carried forward as still current on that
basis, not re-verified byte-for-byte. Group A's premise is now partly
stale, though: `win.show-page`'s accessible descriptions and the properties
`MenuButton` exist now (`component-parity.md`), so a couple of Group A rows
may have moved into Group B (string exists, differs) rather than staying
"component not built." Not re-triaged row-by-row this round — flagged as a
follow-up rather than silently left under the old label.

Generated with `.claude/skills/translation-parity/scripts/catalogue.rb`
against `/tmp/claude-1001/upstream-gsm` (worktree of `origin/main`) and the
`ruby` branch tip, then `catalogue.rb --compare`. Raw totals:
**334/374 messages · 397/435 occurrences · 99/99 languages**.

## Not a pass: 40 gaps, 10 extra, 1 kind mismatch

`summary.parity` is **false**. Full gap list (upstream message, no byte-equal
port key found):

```
%.1f%%                          %d Matching Open File        %d Open File
%s (%.1f%%) of %s               %s (PID %u)                  %u:%02u.%02u
%u:%02u:%02u                    %ud%02uh                     %uw%ud
A simple process and system monitor.                         Affinity failed on %i: %s
Affinity unsupported             Change Priority of %s (PID %u)
Change _Priority                 Click to set graph colors
Current Color                    Fraction
Icon (×2 sites)                  Kill failed on %i: %s
Memory Maps                      Open Failed
Open Files                       Percentage full for pie color pickers
Pick a Color (×2 sites)          Pick a Color for "%s"
Priority failed on %i: %s        Refresh
Select CPUs allowed to run on    Set Affinity
Show the File Systems tab        Show the Processes tab
Show the Resources tab           The priority of a process is given by
                                   its nice value...
The selected color                The title of the color selection dialog
Title                              Type of color picker
FD  [msgctxt "FD here means File Descriptor..."]
_Search for Open Files  [msgctxt "Menu item to Open Search for Open Files dialog"]
_End Process…  [msgctxt "interface"]  — see kind mismatch below
```

Two groups worth separating out, because they are different kinds of gap:

**Group A — components not built** (`%d Matching Open File`, `%d Open File`,
`Refresh`, `Memory Maps`, `Open Files`, `Change _Priority`, `Select CPUs
allowed to run on`, `Set Affinity`, the four `gsm_color_button.c` strings,
`Icon` ×2, `A simple process and system monitor.`, the three `Show the ...
tab` accessibility strings): these wait on `component-parity.md`'s named
gaps (lsof refresh/search/title, the legacy color-picker widget which the
port does not build at all, the three page-switch actions' accessible
descriptions). They are not translation bugs on their own — a widget that
doesn't exist has no string to mark — and they're named here per the rule
that a marked string in a widget the port hasn't built is a translation row
that waits on the component, not a row this ledger can close by itself.

**Group B — components that exist but whose string differs** (every
duration/size/PID format listed below): these are real translation defects,
independent of any missing widget.

## The systemic finding: named placeholders instead of upstream's tokens

Ten port messages are "extra" — present in the port, absent from upstream —
and nine of them are **the same information as an upstream message, with
Ruby's named-placeholder syntax substituted for upstream's plain `printf`
tokens**:

| Upstream (gap) | Port (extra) | Site |
|---|---|---|
| `%uw%ud` | `%<weeks>uw%<days>ud` | `units.rb:74` |
| `%ud%02uh` | `%<days>ud%<hours>02uh` | `units.rb:77` |
| `%u:%02u:%02u` | `%<hours>u:%<minutes>02u:%<seconds>02u` | `units.rb:80` |
| `%u:%02u.%02u` | `%<minutes>u:%<seconds>02u.%<centiseconds>02u` | `units.rb:84` |
| `%s (PID %u)` | `%<name>s (PID %<pid>u)` | `detail_windows.rb:29`, `process_properties.rb:26` |
| `%s (%.1f%%) of %s` | `%<used>s (%<percent>.1f%%) of %<total>s` | `resources_view.rb:207` |
| `Change Priority of %s (PID %u)` | `Change Priority of %<name>s (PID %<pid>u)` | `dialogs.rb:169` |
| — (component gap, Set Affinity) | `Set Affinity of %<name>s (PID %<pid>u)` | `dialogs.rb:323` |
| `FD` [with a translator-comment context] | `FD` (no context) | `detail_windows.rb:164` |
| `Refresh`/`_Search for Open Files` pattern | `Search for Open Files` (reworded, no mnemonic, no context) | `detail_windows.rb:257` |

These are **two gaps apiece, exactly as the skill predicts**: the upstream key
is missing (nobody emits `%u:%02u:%02u` any more) and the port has an extra
key nobody has translated (`%<hours>u:%<minutes>02u:%<seconds>02u` exists in
no `.po` file in any of the 99 languages). This is not a cosmetic difference
— every duration shown anywhere in this app (process CPU time, uptime,
elapsed time columns) and every PID-qualified dialog title goes through one
of these four `units.rb` formats or the two `(PID %u)` constructions, which
makes this the single highest-impact translation gap in the port: it is not
one missing label, it is the formatting of numbers across the entire
Processes and Resources views, in 99 languages, none of which have ever seen
these exact keys. Closing it is **not** "add `_()`" — the call sites already
use `n_`/`_`; closing it means switching the format string back to
positional/plain `%s`/`%u` tokens matching upstream byte-for-byte, which may
require reordering the Ruby `format`/`%` call's arguments positionally
instead of by name. That is real work, not a relabeling.

## Kind mismatch: a real plural bug

`_End Process…` is `ngettext`-plural upstream (`data/interface.ui:359`,
context `interface`) and a plain singular string in the port. Every locale
whose plural rules differ from English's binary split will render this
wrong — not a missing translation, a wrong grammatical form shown to users
who do have a translation.

## Unresolved markers — both open, neither closed here

`src/proctable.cpp:435` builds column titles through a `switch` on an
interpolated index rather than a literal call; the census could not resolve
it to concrete msgids. Per the skill, **a ledger may not be written while
`totals.unresolved` is non-zero without hand-censusing those sites** — this
one was not hand-censused in this audit (budget), so the upstream message
count of 374 is a **floor, not a final number**: there may be more upstream
messages than this ledger accounts for. Stated here rather than silently
rounded off.

## Languages

File-set parity: both trees ship 99 `.po` files, same list, same
`translated_strings`/`untranslated_strings`/`fuzzy_strings` totals
(29,735 / 1,739 / 247) — because the port's `po/` directory is upstream's,
copied across (confirmed present at `po/*.po`, 99 files, matching
`component-inventory.md`'s claim). **Not independently verified**: this
audit did not diff each `.po` file byte-for-byte against upstream's, and did
not confirm `msgfmt`/`rmsgfmt` is available in the (currently broken) dev
shell to compile a `.mo` at all, nor did it run the app under
`LANGUAGE=de LC_ALL=de_DE.UTF-8` to see a translated string on screen — both
required by the skill's Step 5 and both blocked by the same runtime gate as
every other live check in this audit (`.reports/runtime-gate.md`). **A check
that could not run is not a check that passed**: domain-binding and
on-screen-translation are open items, not green.

## Verdict

`summary.parity: false`. 334/374 messages, 40 gaps (10 waiting on
`component-parity`'s named widget gaps, the rest — the `units.rb` formats and
the plural bug — real translation defects with no component dependency), 10
extra untranslated keys, 1 plural/singular mismatch, 2 unresolved upstream
sites never hand-censused, and the on-screen/`.mo`-compiles-at-all checks
unrun because the dev shell cannot install the port's own dependencies.
