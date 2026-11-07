# Accountability ensurance — gnome-system-monitor-rb

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

One real hit, rewritten above. No label laundering, no "n/a," no "out of
scope" language found elsewhere in `lib/`, `exe/`, or `.reports/`. The larger
accountability risk in this port isn't excuse-writing — it's the absence of
the standing ledgers (`PORTING.md` and friends) that would make the next
agent's job of re-checking any of this cheap, combined with a runtime gate
broken badly enough (`.reports/runtime-gate.md`) that no claim about
behavior, anywhere in this port, has ever been backed by a single execution.
