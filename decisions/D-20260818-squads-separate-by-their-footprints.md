# D-20260818 · 2026-08-18 · Accepted — squads separate by the ground they actually cover, not by their centre cell

**Decision:** `SquadSim._separate_arrivals` (D-060) requires two settled
squads to stand at least `footprint_cells(a) + footprint_cells(b)` apart,
where `footprint_cells` is `Formation.footprint`'s world-space radius
converted to cells. It used to require only that they not share a centre
cell — one cell of clearance between formations that are eleven cells
wide.

Seven clauses:

1. **The number comes from `Formation.footprint`, not from a constant.**
   That function has computed the ground a squad covers since selection
   needed a hit target and a marker of the right size, and until now
   every caller was in `client.gd` — the simulation had never read it.
   A squad's room is therefore whatever its own formation, strength and
   spacing say it is, and a shape change or a casualty moves it with no
   second definition to keep in step.
2. **In CELLS, in the hex metric, not in world units.** Every other
   radius rule in this codebase is a `TorusSpace.disk_offsets` scan, and
   a world-space test would need a `distance()` per candidate — the
   defect this project has now hit five times. `footprint_cells` divides
   by the spacing between neighbouring cell centres
   (`sqrt(3) * hex_size`) and rounds **up**: half a cell of extra room
   beats two squads sharing a rank of men because the arithmetic landed
   just under.
3. **The pass places squads in ascending id and records where it put
   them.** The lower id keeps its ground; the higher one is sent to the
   nearest cell where its whole footprint clears. A squad that is sent
   somewhere is recorded at its NEW spot, so the next squad in the pass
   cannot be given the same one.
4. **A working gatherer crew still never moves, and now holds ground.**
   The D-060 exemption is unchanged in the direction that matters —
   several crews on one node is normal, and displacing them once produced
   an economy with 22 gatherer squads and a stockpile that never rose
   above its starting value. A crew is now entered in the pass's bucket
   map, so an arriving squad walks around it instead of standing in it.
5. **Marching squads stay exempt, deliberately.** Shoving a squad aside
   mid-journey is the per-tick avoidance D-006 rules out. Columns passing
   through each other still interpenetrate; see "What this does not fix".
6. **ENEMIES keep D-060's original one cell.** The footprint rule is for
   allies only. A melee `attack_range` is under two world units — a
   little over one cell — so separating a squad from its opponent by its
   own footprint shoves every engagement out of its own reach and no
   melee can ever land. Interpenetrating enemies is what a fight looks
   like; combat (D-024) is what resolves it, not spacing.
7. **A squad with something in reach is exempt entirely, and the pass
   runs AFTER combat so that it can be.** Clause 6 is not enough on its
   own: two ALLIED squads battering one town centre must BOTH be within
   `attack_range` of it, so footprint clearance between them takes the
   second one out of the fight — which is D-067's shipped rule ("one
   squad cannot raze a defended building; two can") broken by a spacing
   change. `Combat.is_engaged` is the signal, and the siege pass records
   it now as well as the squad pass. The ordering matters exactly once:
   the tick a besieging squad arrives is the tick separation would send
   it away, and only combat run first knows it has a target.

## Rationale

Reported from playtest P06 (#34, movement orders and pathfinding), issue
#104, judging the criterion *"crowded destinations resolve NEARBY — no
squad shoved far away and left idle"*. That criterion failed in the
opposite direction to the one it was written to catch: squads ordered to
the same area did not shove each other away, they **overlapped almost
completely**.

The rule was doing exactly what it said and was an order of magnitude
short of the geometry. Measured from `Formation.footprint` with shipped
values (`formation_spacing` 0.9):

| shape | alive | footprint radius (world) | centres must be apart |
|---|---|---|---|
| line | 12 | 2.07 | 4.14 |
| line | 24 | 3.73 | 7.45 |
| **line** | **36** | **5.48** | **10.96** |
| line | 48 | 7.26 | 14.52 |
| column | 36 | 4.29 | 8.58 |
| tight | 36 | 3.15 | 6.30 |

The system guaranteed 1. Even the tightest shape at that size needs 6.3.

`_free_cell_near` had a second, smaller bound of the same kind: it
searched `disk_offsets(4)` — four rings, smaller than one 36-strong
line's own radius — so even a footprint-aware check could not have found
anywhere to put the second squad. Its reach scales with the footprints
involved now.

**This is the declared-and-under-read family in a variant worth naming.**
`footprint()` exists, is correct, is cached, and returns exactly the
number the rule needs. It is not unread — it is read by the CLIENT, for
DRAWING, and never by the simulation for the rule it would enforce. So
the usual instrument (grep for uncalled public members, D-055) finds
nothing, no test can see it, and the picture even looks self-consistent:
the selection marker is drawn at the squad's true footprint and therefore
visibly overlapped its neighbours. **The picture was telling the truth
and nobody read it as a bug report.** Same family as `UnitDef.cost`,
`BuildingSim.damage`, the three `CivDef` knobs and the client's explored
set (D-106) — with the reader present but pointed the wrong way.

## Rejected alternatives

- **Per-soldier collision.** What the report literally asks for ("a
  little more unit to unit collision limits") and what D-006 names as its
  revisit trigger, verbatim: local avoidance, collision push-back and
  jostling each give a soldier integration state. That purity is what
  lets client and server agree on 40,000 soldier positions without
  sending any of them. The same visible outcome is reachable at squad
  level, which is where D-005 puts it, with no per-soldier state at all —
  the two approaches look near-identical on screen and only one is legal
  here.
- **Dealing a mass order out across a disk at ORDER time.** Better feel
  (squads arrive in formation rather than shuffling on arrival) and it is
  what the crowded-destination criterion is really asking for — but it is
  the version D-060 already tried and reverted: twenty squads sent to one
  point got twenty DIFFERENT destinations and therefore built twenty flow
  fields instead of sharing one, which is D-007's entire scaling claim.
  `_quantise` (D-038) exists to force nearby orders onto ONE destination
  for exactly this reason. Separation stays where the pile-up shows: at
  the end. `test_separation_does_not_cost_extra_flow_fields` is the guard.
- **A pairwise squad x squad overlap pass.** ~10^6 comparisons a tick at
  D-018's 1,000 squads. A squad scans its own hex disk against a bucket
  map built once per pass instead — the D-066 shape, the fifth instance
  of the same rule.
- **World-space separation via `TorusSpace.world_delta`.** Exact, and
  it costs a length() per candidate. The hex metric is anisotropic by
  13% between an axis direction and a corner one, which is invisible on
  screen, and it makes `disk_offsets` exactly the set of cells that can
  matter — no per-candidate re-check, the same reasoning `combat.gd`
  records for its target scan.

## Consequences

- **Armies take up a great deal more room, on purpose.** For two line
  formations the new clearance is very nearly shoulder to shoulder: two
  36-strong militia settle 8 cells apart where they used to settle 1.
  A rally point is now a body of troops rather than a heap.
- **`_free_cell_near` takes the bucket map and the widest footprint on
  the board**, and its reach is `(own + widest) * SEPARATION_SEARCH`
  capped at `SEPARATION_MAX_RINGS` (16). The cap is what bounds the one
  loop in the pass whose cost is not bounded by the squad count; a crowd
  too big for it falls back to the function's existing behaviour —
  standing a little close beats never settling.
- **`_separate_arrivals` moved to the end of the tick and is timed on
  its own.** It used to sit inside the curves phase; it now runs after
  combat (clause 7) and reports `last_separation_usec`, which the
  server's over-budget breakdown prints as `sep=`. A pass that is now a
  hex-disk scan per settled squad must be visible as itself there, or the
  next person profiling a spike is sent to the wrong file (D-038).
- **The tier-1 eviction path (D-076) shares the new function**, and
  builds its bucket map once for the whole sweep rather than once per
  stranded squad — a wall coming down is exactly when several drop at
  once.
- **Three squads sent to one cell now separate in ONE tick.** The old
  pass never recorded where it had just sent a mover, so the second and
  third were both given the same free cell and had to re-separate over
  the following ticks.
- **Freshly produced squads spread out at the barracks.** They were
  settled one cell apart by `_spawn_cell_near` and are now pushed to
  their real clearance, which costs a flow field each. That is the same
  cost the pass already paid per mover; the count of distinct
  destinations is unchanged (one per mover), only the distance moved.
- **Per-squad cost: +10.9%, measured as a PAIR.** Every settled squad now
  scans a hex disk of `own + widest` rings against the pass's bucket map —
  about 217 cells at shipped sizes, the same shape and roughly the same
  size as an archer squad's target scan in `combat.gd`.

  | tree | µs/squad @ 48 squads | worst tick | dropped | verdict |
  |---|---|---|---|---|
  | `main` (1e6ba9c) | **341.94** | 85.9 ms | 0 | ok, 0 desyncs |
  | this branch | **379.13** | 79.0 ms | 0 | ok, 0 desyncs |

  4 bots × 300 s on the shipped default map, 2026-08-18, this worktree's
  own instance. **Quote the DELTA, not the absolutes.** Both figures are
  roughly twice `docs/status/m10-plan.md`'s 167.7 µs at the same 48
  squads, because Docker Desktop was down on this host and the run was
  taken with the NATIVE runtime while ~15 other agents' Godot processes
  were resident — the same "measured during a long benchmarking session"
  caveat D-096 records, which is exactly why the baseline was re-taken on
  the same host minutes apart rather than read out of a status file.
  The two runs are also not the same MATCH: separated armies meet
  differently (`conceal_events` 42 → 29, `known_squads_max` 33 → 25), so
  some of the delta is a different game rather than slower code.

  The printed `combat=` figure rose 52.3 → 66.2 µs, which is mostly this
  pass being inside `last_combat_usec`'s outer window rather than combat
  itself getting dearer. `sep=` in the over-budget breakdown is the number
  to read when one is available; neither run had an over-budget tick.

## How clauses 6 and 7 were found, which is the part worth carrying

The first version applied footprint clearance to every squad, exactly as
the old rule did, and every test written FOR this change passed. Two
separate failures elsewhere in `just test-unit` are what found the rest,
and neither is in a file this change touches.

**First, `test_wall_top.gd`** —
`test_the_height_bonus_extends_a_defenders_effective_range`, failing on
its *setup* assertion, "defender climbed". A defender standing at a
tower's door had been shoved off it by an ENEMY squad five cells away
whose footprint now reached that far. The failing assertion is about
wall-top climbing and the defect was about melee: with footprint
clearance between enemies, **no melee squad could ever engage anything.**
It marches into contact, arrives, is declared crowded, is sent eight
cells back, and repeats. Hence clause 6.

**Then `test_buildings.gd`**, which is D-067's own guard, reporting in
its own words: *"two squads dealt 1560 against one squad's 1461 — the
second squad is not in the fight"*, plus 13 more failures across "two
squads of any line troop can take a town centre / a tower". Clause 6
does not cover this one, because the two besiegers are ALLIES: they were
being separated from each other, and separating them puts the second one
outside its own reach of the wall. Hence clause 7, and the tick
reordering it needs.

Nothing in this change's own tests could see either. Every one of them
puts its squads under a single owner with nothing to shoot at, because
"an army spreads out" is what the issue is about; and the combat tests
place their squads already adjacent, so before this change no arrival
ever settled next to a fight.

**A separation rule and an engagement rule are the same arithmetic
pointed in opposite directions**, and separation is the one that has to
give way. The general form, which is worth more than the fix: when a
change makes squads keep their distance, go and read the mechanics whose
whole job is to close it — combat range, siege, gathering, wall access.
Each of those is a position a squad NEEDS, and a spacing rule that does
not know about one of them will quietly delete the feature.

## What this does not fix, and is not trying to

- **Marching squads still interpenetrate.** `_separate_arrivals` skips
  any squad whose cell is not its destination, because shoving one aside
  mid-journey is the D-006 revisit trigger. Two columns crossing will
  pass through each other. Whether that is acceptable is a real design
  question and is being ANSWERED here rather than discovered later: it is
  accepted for now, on the grounds that the alternative is per-tick
  avoidance and the visible complaint was about squads standing still.
  Revisit trigger below.
- **A crowd larger than `SEPARATION_MAX_RINGS` can hold still overlaps.**
  Bounded, deliberate, and reported by the squads simply standing closer
  than they should — never by a squad failing to settle.

## Revisit trigger

- A playtest reports marching columns interpenetrating badly enough to
  matter. The legal fix is at squad level (staggered destinations within
  one flow field, or lane offsets derived from the field), never
  per-soldier avoidance.
- `_separate_arrivals` showing up in the per-phase breakdown of an
  over-budget tick (D-038's instrumentation). The next lever is a coarse
  bucket grid sized to the widest footprint, which turns the per-squad
  disk scan into a fixed nine-bucket lookup.
