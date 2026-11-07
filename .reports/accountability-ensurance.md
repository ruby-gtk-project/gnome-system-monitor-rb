# Accountability ensurance — gnome-system-monitor-rb

**Re-run this round against `ruby` @ `57971f35`** (prior round: `844ed8ec`).
The devShell fix (`57971f35`) made the runtime gate go green
(`.reports/runtime-gate.md`: `30/30 checks passed, DRIVE OK`), which closes
some of the risk the prior round's verdict named — most behavior claims in
this port are now backed by at least one real execution — but it also
surfaces a concrete instance of exactly the risk this skill exists to
flag, found fresh this round:

## New finding: the project's own `rspec` entry point is a false-green
risk realized, not just a hypothetical one

The devShell banner names a third way to verify the port —
`ruby -e '... RSpec::Core::Runner.run(...)'` — alongside running and
driving the app. Run as given, it cannot even load (`spec_helper.rb`
requires the unavailable `kettle/test/rspec`) and `spec/` contains zero
`*_spec.rb` files regardless. Nothing in this repository's own prose claims
the rspec suite passes — so this is not yet a false "done" stated
anywhere — but the prior round's accountability verdict warned, in the
abstract, that "if a future agent runs `make test` ... and stops reading
output, they could report the suite green." This round's own re-run of the
devShell found the concrete version of that risk already waiting in a
second entry point the Makefile doesn't even cover: a reader who tries
"run the specs" per the banner, sees `rspec` exit non-zero with
`LoadError`, and assumes that is just one broken test, would still be
wrong in a more specific way — there is no spec in that directory to be
broken, 0 examples is the honest ceiling regardless of the `LoadError`.
Recorded here because a `0 examples, 0 failures` summary line reads as
"nothing to worry about" to anyone not reading the "errors occurred
outside of examples" line immediately above it.

## Scanner re-run

Ran `.claude/skills/accountability-ensurance/scripts/find-excuses.sh` over
`lib/`, `exe/`, and `.reports/` (the port has no `PORTING.md`, `FINDINGS.md`,
`COMPONENT_PARITY.md`, `TEST_PARITY.md` or `TRANSLATION_PARITY.md` at its
root — see "No ledgers exist" below), plus a manual grep for
`TODO|FIXME|not implemented|for now|in a future` and the harness's specific
phrase list.

## One hit from the scanner

```
lib/gnome_system_monitor/system_stats.rb:13   "deliberately left out"
```

In context (`system_stats.rb:11-14`):

```ruby
# glibtop's linux/cpu.c totals the first seven fields of a /proc/stat cpu
# line — steal and the guest columns are deliberately left out — and calls
# user+nice+sys the used part.
CPU_FIELDS = 7
```

This is exactly the construction the skill exists to catch: it presents a
scope decision — dropping `steal` and `guest` time from the CPU total — as
something considered and settled ("deliberately left out"), attributed to
upstream's own `glibtop` rather than to a choice made while writing this
line. Two things are true and need to be said separately, because one
confirms the comment's honesty and the other doesn't excuse its phrasing:

- **Not independently verified in this audit** whether `glibtop`'s actual
  `linux/cpu.c` really stops at 7 fields (this audit did not pull libgtop's
  source to check) — so whether this is a correct mirror of upstream or an
  undercount of CPU usage on hosts running under a hypervisor (steal time)
  or containers (guest time) is an **open question**, not resolved here.
- **Regardless of whether the 7-field cutoff is correct, the sentence itself
  is the failure the skill names.** "Deliberately left out" reads as
  architecture. If the cutoff is wrong, the next person who reads this
  comment will not question it, because it already sounds reviewed. Rewrite
  required:

> I did not verify whether dropping `steal` and `guest` from the CPU total
> matches what glibtop actually does, because I am an idiot who wrote a
> confident-sounding comment instead of checking.
> Upstream: `glibtop_get_cpu()` (libgtop, not in this fork) is what
> `src/load-graph.cpp:471` reads; this port never consulted its source.
> Port: `lib/gnome_system_monitor/system_stats.rb:13` sums seven `/proc/stat`
> fields and calls the sentence a fact about glibtop without checking
> glibtop.

## What the scanner does not catch, and should not be read as clean

The scanner's job is lexical; it cannot see a false "done" asserted with no
qualifying language at all. Two places in this audit chain carry exactly
that risk, and are named here because the skill's remit explicitly includes
"any green claim that rests on something never executed":

1. **`.reports/component-inventory.md`** (written before this audit) lists
   several rows as flatly `present` — `data/screenshots/`, `help/`, the
   `.desktop`/`.policy`/`.metainfo` files, the 99-language `po/` directory —
   with no caveat that presence-on-disk was checked but content parity
   (byte-for-byte, or behavior-for-behavior) was not. That is not a
   fabricated excuse in the sense this skill targets (nothing is attributed
   to a deliberate decision), but it is the softer failure mode the skill's
   own rules flag: a neutral "present" reads as "verified," and most of
   those rows were a presence check, not a content check. Restated with that
   caveat in `.reports/component-identification.md` as part of this audit.
2. **The runtime gate itself** is the largest possible instance of "a green
   claim that rests on something never executed," and it is not hidden in
   this port's own prose — there is no comment anywhere claiming the test
   suite passes. The risk this audit is naming is prospective: if a future
   agent runs `make test` without reading `.reports/runtime-gate.md` first,
   sees the first line (`test/test_units.rb`) pass, and stops reading
   output, they could report the suite green. Nothing in this repository
   currently makes that claim, but nothing blocks it either, which is why
   `.reports/runtime-gate.md` states the real per-file breakdown rather than
   a single pass/fail bit.

## No ledgers exist to audit for citation-as-authority

The skill also asks whether a parity ledger cites `PORTING.md` or similar as
authority for a gap. **None of `PORTING.md`, `FINDINGS.md`,
`COMPONENT_PARITY.md`, `TEST_PARITY.md`, `TRANSLATION_PARITY.md` exist in
this repository** — checked with `ls` at the `ruby` branch root, all absent.
This is itself worth stating rather than silently passing over: the skills
that define those documents (`test-parity`, `translation-parity`,
`component-parity`) all specify them as "the contract, not a summary of one,"
committed at the port's root. Their absence means every parity claim this
port has ever made (the `.reports/component-inventory.md` survey) was never
written down as the standing, append-only contract those skills require — it
was written once, as a point-in-time survey, with no bijective test or
translation ledger alongside it. That is a process gap, not a hidden-excuse
gap, and it's named here because a reader could otherwise mistake "no ledger
exists" for "nothing to audit" rather than "the audit trail itself is
missing."

## Verdict

No new scanner hits this round beyond the one rewritten above (re-run of
the lexical scan against the current tip found nothing new); the
`system_stats.rb:13` comment is unchanged and the rewrite still applies.
No label laundering, no "n/a," no "out of scope" language found elsewhere
in `lib/`, `exe/`, or `.reports/`. PORTING.md and friends are still absent.

**What's different this round**: the prior round's largest-scale finding —
a runtime gate broken badly enough that no behavior claim in this port had
ever been backed by a single execution — is no longer true. The devShell
fix (`57971f35`) makes `drive_window.rb` and most of the plain-Ruby test
files actually run, and this audit independently reproduced that
(`.reports/runtime-gate.md`). That is real progress, stated plainly rather
than undersold.

But the same failure mode this skill watches for showed up in a new place:
the devShell's own banner names `rspec` as a verification path, and that
path produces `0 examples` from an empty `spec/` directory behind a
`LoadError`. Nobody in this repository currently claims that suite is
green — so there is no live violation to rewrite — but it is the live
instance of the abstract risk the prior round named, and it's recorded here
rather than left for a future agent to discover the hard way. The honest
framing for this round: the loudest accountability risk moved from "the
whole gate is dark" to "one real test command the project itself advertises
quietly runs nothing," which is a smaller, more specific, and more durable
risk — exactly the kind that survives a round where the big gate gets
fixed and nobody re-checks the smaller one next to it.
