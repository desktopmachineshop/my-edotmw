# D-20260827 · Every start shares one landmass

**Date:** 2026-08-27
**Status:** Accepted
**Issue:** #128 (lobby playtest, 2026-08-18 — *"spawn location for me was
in an unaccessible area isolating my founder from the rest of the map"*)

## Decision

**Every starting position is sampled from ONE walkable component — the
largest one on the map.** `MapConfig.spawn_points` labels the whole
passability field's components once, before it draws a single candidate,
and rejects any cell that is not on the mainland. `validate_spawns` fails
a seating that is complete and disconnected as well as one that is short.

D-104's `min_spawn_landmass` survives as a floor on the mainland's own
size, and is no longer the whole rule.

## Rationale

D-104 added `min_spawn_landmass` for close to this reason and its doc
comment says a start must not be *"a six-cell rock in the sea"*. It does
prevent that. It cannot prevent isolation, for a reason that is
structural rather than a tuning mistake: **it is an absolute size, and
isolation is a relation.** `_landmass_at` flooded from one candidate and
asked only whether that component cleared the bar. Nothing anywhere asked
whether the component holding spawn A also held spawn B.

The threshold made it worse without being the cause. 96 cells is 1.19% of
the shipped Skirmish map and 0.29% of the Standard one, so a start could
clear the bar by a wide margin and still share its ground with nobody.

**The harm is a silent stalemate, not an unlucky map.** A player who
cannot be reached cannot be eliminated, so under D-033 the match cannot
be decided and runs to the time cap. That is exactly the shape D-055
found when nothing could destroy a building — matches drawing for a
reason nobody could see, misread as an AI weakness through several rounds
of AI work. `just ai-ladder` would have reported it as a draw with no
indication the map was at fault.

**The old flood fill could not have answered the question even if a
caller had wanted it to.** It early-exits at the threshold
(`while head < queue.size() and seen.size() < min_spawn_landmass`), so it
returned 96 for a 96-cell rock and for a 20,000-cell continent alike.
Component identity and true size are both new information.

## How often was it reachable — measured, not assumed

Four presets x four sizes x six seeds (96 worlds), `player_slots = 20`,
`min_spawn_landmass = 96`. "Strandable" is a component other than the
mainland that clears the bar, i.e. ground the OLD sampler would happily
have seated somebody on alone.

| preset | worlds with a strandable component | starts the old rule actually stranded |
|---|---|---|
| `continents` (shipped default) | 4 of 24 | 0 of 480 |
| `plains` | 0 of 24 | 0 |
| `highlands` | 0 of 24 | 0 |
| `islands` | 24 of 24 | **6 to 19 of every 20** |

So on `islands` this was not an edge case — on the Huge map at seed 1337,
**19 of 20 starts were marooned**. On `continents` it is rare and real:
four worlds in twenty-four hold ground that qualifies, and none of the
six seeds sampled happened to seat anyone there. The reported world is
not reproducible from the issue (no seed, no preset recorded) and the
passability rule has since changed underneath it
(`D-20260826-passable-means-flat-enough-to-cross` fractures land by
slope, and carves ramps into 60% of the pockets it creates), so this
table describes the tree as it stands rather than the session that
reported it.

## What it costs, measured

**Seating capacity**, same sweep, 20 slots:

| preset | mainland as a share of walkable ground | seated before | seated after |
|---|---|---|---|
| `continents` | 99.3–99.9% | 20/20 | 20/20 |
| `plains` | 100% | 20/20 | 20/20 |
| `highlands` | 99.9–100% | 20/20 | 20/20 |
| `islands` Skirmish | 24–67% | 18/19/18 | **8/14/17** |
| `islands` Standard+ | 8–43% | 17–20 | 17–20 |

**On every preset a human has played, the change is free.** `islands`
pays, and it pays honestly: an archipelago genuinely cannot seat twenty
mutually-reachable starts, and the old rule's "20 of 20" was a count of
points rather than a count of players who could take part. Note the old
rule already short-seated `islands` (17–19 of 20) — this makes the
shortfall bigger and, for the first time, meaningful.

**And on the map the gate runs on, it is a provable no-op.**
`maps/default.tres` at seed 1337 has **17 walkable components, of which
exactly ONE clears `min_spawn_landmass`** — the 24,997-cell mainland. The
old predicate ("any component past the bar") and the new one ("the
mainland") therefore accept precisely the same candidates, off the same
rng stream, so the seating is bit-identical and `just test-load`'s
numbers stay comparable across this change. It also means the load test
does not exercise the new rejection at all; the unit tests and the sweep
are what cover it.

**Wall clock**, `spawn_points` on one host, five calls averaged, 20 slots:

| preset / size | before | after |
|---|---|---|
| `continents` 84x96 | 14.0 ms | 6.4 ms |
| `continents` 168x194 (shipped default) | 12.9 ms | **13.3 ms** |
| `continents` 252x290 | 22.2 ms | 30.1 ms |
| `continents` 336x388 | 16.6 ms | 61.5 ms |
| `islands` 84x96 | 29.7 ms | 16.3 ms |
| `islands` 336x388 | 10.6 ms | 32.5 ms |

The shipped default is unchanged and the small maps get faster; the two
top rungs pay. Accepted, because the two callers are a match starting
(once) and the lobby's map preview — which is guarded by a settings key
and already spends a `biome_color` call on every one of those 130,368
cells in the same function. #128's own suggestion that a precomputed
component map "avoids that trade entirely" turned out to be optimistic:
the capped fills it replaces only ever ran on candidates that had already
passed two cheaper tests, so the old sampler's cost was dominated by
rejection sampling and was near-flat in map size.

Two implementation notes bought during that measurement, both of which
are about GDScript rather than about maps:

- **`TorusSpace.neighbor_table` is the wrong tool for a single pass.** It
  is exactly right for the flow-field solver, which walks the lattice
  thousands of times a match
  (`D-20260818-the-flow-field-solver-was-93-percent-neighbour-lookup`).
  Here `to_space()` mints a fresh space per call and each cell is visited
  once, so a table-backed pass cost 76.0 ms on the Huge map — most of it
  building a 3.1 MB table to read each entry a single time. The six
  offsets are inlined instead, and a test pins them against
  `TorusSpace.neighbors` so the copy cannot drift.
- **A six-element array literal per cell cost half the pass** (88.3 ms to
  61.5 ms on Huge when unrolled). It is written out rather than factored
  into a helper because a GDScript `Packed*Array` argument is
  copy-on-write: a helper would mutate its own copy of `labels` and the
  walk would never terminate.

## Rejected alternatives

- **Replace the absolute 96 with a fraction of the map.** #128 raises it,
  and it does not fix this: a fraction is still a size, and two large
  islands both clear any threshold. The rule that actually prevents
  isolation is connectivity, which is scale-free — so `min_spawn_landmass`
  was left exactly where D-104's sweep put it. Re-expressing it is a
  balance change with no defect behind it.
- **Per-preset opt-out, so `islands` may deliberately maroon people.**
  Named in #128 as a possible future. Not built: nothing in the game
  currently makes an island start playable (no transports, no naval
  movement), so the opt-out would enable a configuration whose only
  outcome is the stalemate above. The revisit trigger below is when that
  stops being true.
- **Require pairwise reachability rather than one shared component.**
  Identical in effect — reachability on an undirected field IS component
  identity — and strictly more work.
- **Keep the per-candidate fill and add a second connectivity pass.** Two
  walks over the same field, and the size answer would still be the
  capped one.

## Consequences

- **Spawn placement changes on every map that has more than one
  component**, which is every `continents`, `highlands` and `islands`
  world. `plains` is a single component at every size and seed sampled,
  so it is untouched. Any timing tuned against the old spread is
  measuring a different opening, per the standing rule — the same clause
  `D-20260817-starting-positions-follow-the-seats` had to write.
- **Determinism survives.** Components are discovered in cell-index order
  and each frontier expands in direction order, so labels are a property
  of the field. The mainland is the largest component with ties broken to
  the first discovered. Replays (D-016) and the lobby preview both still
  reproduce from the seed alone, and a test asserts two calls agree.
- **`min_spawn_landmass <= 1` is now one switch for BOTH landmass rules.**
  A caller asking for no size bar is asking for the placement that
  predates D-104; splitting the switches would leave a configuration able
  to seat a player on a rock that only the size bar forbade. It is also
  the one configuration in which the sampler can still produce a stranded
  seating, which is how `validate_spawns`' new branch is *observed* to
  fire rather than asserted to be unreachable.
- **`walkable_components` and `disconnected_spawns` are public.** The
  sampler makes a disconnected seating impossible by construction, so a
  check reachable only through the sampler would be a check nobody could
  watch fail — the exact vacuity D-022's audit block was written against.
  Both are driven directly by tests with hand-authored fields.
- **A short seating is reported and is not fatal**, unchanged from before:
  `server.gd` warns and plays on. `islands` at 20 seats will now say so.

## Revisit trigger

- **Naval movement, transports, or any way to cross water.** An island
  start stops being a dead player at that point, and the per-preset
  opt-out rejected above becomes the right shape.
- **A preset whose mainland is a minority of its walkable ground being
  wanted for real play.** `islands` is at 8–67% today and is playable
  only because the sampler now confines starts to the mainland; a design
  that wants the archipelago itself needs a different rule, not a looser
  one.
