# D-20260830 · Each worker carries his own load

**ID:** D-20260830-each-worker-carries-his-own-load
**Date:** 2026-08-30
**Status:** Accepted (owner's call, from a live playtest: "each worker
counts their total individually rather than as a squad — good if they
get killed etc.")

## Decision

A gatherer crew's carrying capacity and its delivery are **per-capita in
`alive`**: `Economy._crew_capacity` is
`ceil(carry_capacity × alive / squad_size)`, read where the crew fills
up and where it turns for home, and `_try_unload` credits at most that —
so a crew at half strength fills half a load and turns home sooner, and
a crew ambushed on the walk home banks the SURVIVORS' shares while the
dead drop theirs where they fell.

**This is squad-level arithmetic, deliberately.** The owner's ask was
per-worker fairness, and the phrase "walk individually close enough"
reads naturally as per-soldier simulation — which D-005/D-006 fence out:
squads are the atomic simulation unit, soldiers are derived render
state, and per-soldier hauling would be per-soldier position, identity
and ledger on the authoritative side, the exact revisit
D-20260819-tier-three-lives-on-the-render-side says must reopen as its
own decision, never arrive as a patch. Every OUTCOME the ask names is
expressible in `alive`:

- a killed worker's share is not delivered — the clamp at unload;
- a depleted crew does not gather loads its dead cannot carry — the
  capacity cap while filling;
- income already scales with `alive` per tick (D-028, unchanged).

What is NOT expressible in `alive` is each man visibly filing to the
door with his own sack — a render-layer nicety in the same family as the
duel pass, left unbuilt here and noted rather than implied.

Before this, `carrying` was a squad total that outlived the men who
carried it: a crew that filled to 45 and lost half its men on the walk
home delivered all 45.

## Consequences

- Ceil, not floor, so one survivor still carries at least one unit and
  the crew is never trapped filling a zero-capacity load.
- A full-strength crew is bit-for-bit unaffected (`alive == squad_size`
  makes the cap the def's own `carry_capacity`), so `test-load` and
  ladder timings only move where crews actually take casualties.
- `tests/test_economy.gd` pins both halves: a half crew turns home at
  half a load, and survivors of an ambush deliver exactly their own
  shares.
