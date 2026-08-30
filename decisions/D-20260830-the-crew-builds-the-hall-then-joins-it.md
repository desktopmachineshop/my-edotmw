# D-20260830 · The crew builds the hall, then joins it

**ID:** D-20260830-the-crew-builds-the-hall-then-joins-it
**Date:** 2026-08-30
**Status:** Accepted (owner's call, from a live playtest: "gatherers
should build until the town hall is finished then they walk into it and
are consumed")

## Decision

A `consumes_builder` build no longer spends its crew at COMMIT. The crew
stands at the site for the whole build, is BOUND to it — every order to
a bound crew is refused at `_validated_squad`, the one gate all squad
orders pass — and joins the building the tick construction completes,
through the same `consume_squad` casualty path as before. This
supersedes the spend-at-commit clause of
`D-20260823-the-opening-is-a-crew-and-a-general` (everything else in
that entry stands).

1. **The exploit moves guards, it does not come back.** Spend-at-commit
   existed because consume-on-completion was a measured exploit — D-027's
   first playtest founded three town halls in five seconds off one party
   standing free while the first went up. The LOCK closes it instead: a
   crew that takes no orders cannot be ordered to found a second hall,
   and its remaining build queue lapses at bind. One gate rather than a
   check per handler, because twenty guards are the same rule written
   twenty times (D-20260827's overlay reasoning).
2. **The bond lives server-side** (`server._founding_crews`, building →
   squad), settled by `_settle_founding_crews()` once per tick: a
   completed building consumes its bound crew; a razed site frees its
   crew — the bond defers consumption, it is not a death sentence for a
   build an enemy tears down. A crew that died waiting costs nothing:
   `consume_squad` guards liveness itself.
3. **Sandbox `instant_build` consumes in the same breath**, because the
   site is raised already complete and a deferred bond would lock the
   crew to a building that will never re-complete.
4. **Binding releases the crew's haul** (`Economy.release`, a function
   nothing needed before): spend-at-commit relied on the death sweep to
   erase a founder's haul entry, and a crew that now lives through the
   build would otherwise still be worked by the haul loop — gathered
   remotely and force-marched to its drop-off mid-founding.

## Known and accepted

- **A routed bound crew is still consumed at completion, wherever its
  rout carried it.** Consuming only-if-nearby would let "order the crew
  away just before completion" keep both the crew and the hall — every
  hall founded free. The rout case is rare (founding happens away from
  enemies or the build is already doomed) and the airtight rule wins.
- **The walk-in is the crew standing at the site and vanishing as the
  hall completes** — no bespoke walk animation this pass; the men are
  already adjacent by construction (build reach, D-031).
- **AI and bot orders to their own bound crew are refused like anyone
  else's** — they latch founding on the building appearing (at commit,
  unchanged), so their logic proceeds; stray orders to the bound crew
  are refused noise for the 40 s build, deduped by `_report_refusals`.
- **Net economics are unchanged**: the crew was dead during construction
  before and is locked during construction now — either way it gathers
  nothing until the hall stands. Timings tuned against the opening do
  not move.

## Consequences

- `tests/test_opening.gd`: spend-at-commit's test now proves
  spend-at-completion, plus the lock, the razed-site release, the
  instant-build path and a caller scan on `_process` (D-106's rule).
- `manual/first_minutes.tres` re-worded and re-stamped — its prose
  stated the superseded timing outright.
- `docs/status/the-opening.md` carries the status note.
