# Playtest #44 — civ differentiation (Legion vs Northmen): bot findings

**Ticket:** [#44](https://github.com/desktopmachineshop/my-edotmw/issues/44) — CLOSED, obsolete.
**Replacement filed:** [#207](https://github.com/desktopmachineshop/my-edotmw/issues/207).
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`.

## Verdict

Not playtested. The ticket names two civilizations that no longer exist in the
repository, so there is nothing to observe — bot or human. Closed as obsolete
and replaced.

## What was checked, and how

Static inspection of the shipped data only. No match was run; none would have
been informative.

| claim | evidence |
|---|---|
| Legion and Northmen are gone | `ls civs/` returns exactly `emberdeep gildedreach gravesworn stoneblood thornwood windmarch` |
| their units are gone | `ls units/*.tres` returns 39 files, every one prefixed with one of those six ids; no `legion_*`, no `northmen_*` |
| the archetype vocabulary moved | `militia` is `levy`; `heavy`, `breaker`, `shades`, `greatbow`, `bowriders`, `sellswords`, `engine`, `ram`, `bombard` are new since the ticket was written |
| the three `CivDef` knobs are live | `D-20260823-a-civs-knobs-are-read-by-the-simulation` (#158), landed 2026-08-23 |

The authority for the deletion is #191 /
`D-20260818-fantasy-civs-supersede-the-historical-frame`, Accepted 2026-08-26,
and `docs/status/fantasy-civs.md` records it.

## The one thing worth carrying out of it

#44's third pass criterion was *"no mechanical difference relies on the three
dead `CivDef` knobs (`squad_cap_bonus`, `production_speed`, `gather_speed` —
shipped but read by nothing; note where their absence is felt)"*. Those knobs
stopped being dead on 2026-08-23. The criterion is therefore not merely stale,
it is **inverted**: the question worth a human's time now is whether the two
civs that carry non-default values are *felt* to carry them.

Measured off the shipped `.tres` while filing the replacement — only **two of
six** civs carry any non-default knob at all:

| civ | squad_cap_bonus | production_speed | gather_speed |
|---|---|---|---|
| gravesworn | **4** | **1.15** | 1.0 |
| gildedreach | 0 | 1.0 | **1.15** |
| stoneblood | 0 | 1.0 | 1.0 |
| thornwood | 0 | 1.0 | 1.0 |
| windmarch | 0 | 1.0 | 1.0 |
| emberdeep | 0 | 1.0 | 1.0 |

Four of six are mechanically differentiated by their **roster alone**. That is
plausibly correct — "ranged attrition" and "mobility" are roster-expressible
identities — but it is not something the data can settle, and it is the single
most useful question the replacement playtest can answer. It is written into
#207 as step 4 and its own pass criterion.

Not filed as a defect: the knobs being at their defaults is a balance position,
not a bug, and `docs/status/fantasy-civs.md` explicitly leaves strength ordering
between the six to `just ai-ladder` — of which no run against this roster exists
yet.

## Bugs filed

None. Nothing was run.

## What remains for the owner

All of #207. Nothing in it is bot-observable: every criterion is a judgement
about whether a difference is *felt*, which is exactly the thing an automated
run cannot report.

One thing the owner should know before starting it, from
`docs/status/fantasy-civs.md`: art coverage is uneven **by design**. Emberdeep
wears the supplied dwarf models throughout, Gildedreach borrows the two
surviving authored human models, and the other four civs — including their
gatherers — are the primitive capsule tier. That is D-064's designed
degradation, not a defect to report.
