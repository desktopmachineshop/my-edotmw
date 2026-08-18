### D-20260818 · 2026-08-18 · Accepted — a soldier stands where his squad could walk

**Decision:** terrain passability is the **second half of D-006's terrain
sample**, alongside height. A formation slot that lands on ground its
squad could not path onto is pulled back along its own offset ray until
it lands on ground the squad could, and failing that stands on the
squad's own cell. `Formation.grounded_offset` is the whole mechanism; it
is static and pure like everything else in that file, and the array it
reads is an argument, never a remembered state.

The array is **terrain passability only** — `TerrainGen.passability`, the
same predicate the flow field routes around. Both sides derive it from
the replicated `MapSettings` (D-049) and nothing new goes on the wire.

**Why.** Reported from playtest P06 (#34, #97): a squad on a beach with
half its formation standing up on the grey mountain shelf behind it, and
soldiers visibly popping on and off the rock as the squad shifted.
Passability was enforced on the SQUAD and on nothing else. `_grid_offset`,
`_wedge_offset`, `_ring_offset` and `_scatter_offset` are pure geometry in
(shape, slot, alive, spacing); the only terrain input anywhere on the path
was a HEIGHT sampler, so a slot that landed on a mountain cell was not
rejected, it was dutifully lifted to the height of the rock and drawn
standing on it.

The pop is large rather than subtle, and D-097 is why: `surface_field`
stores the RENDERED elevation, which for the impassable HIGH class
includes `cliff_rise` (2.0 world units) on top of the natural step
(median 0.20 along the coast, 0.66 at a mountain foot, measured in
D-097). A slot crossing the passability boundary therefore teleported to
the top of the drawn cliff.

**Why it stays inside D-006 clause 1.** Adding an input is not adding
state. A soldier's position is still a pure function of its arguments,
the same call gives the same answer forever, and a man back on open
ground gets his full offset again the very next frame with no memory of
having been pushed. There is nowhere for a per-soldier nudge to live —
`Formation` is all-static by construction, which is the property that
makes this checkable rather than merely intended. What clause 1 forbids
is local avoidance, collision push-back and jostling; those are
per-soldier integration, and this is not one.

**Why the pull is toward the squad and not to the nearest passable cell.**
A nearest-free-cell walk (`TorusSpace.disk_offsets`, sorted nearest-first
since D-067) moves every man his own way, so neighbours separate and the
block tears along the shoreline; it is also an unbounded walk on the
hottest path in the client. Pulling along the offset ray keeps every man
on his own line out from the centre, so the formation COMPRESSES against
the water instead of scattering, the work is bounded at
`PASSABLE_PULL_STEPS` (4) lookups, and the fallback is guaranteed rather
than a shrug: the squad's own cell is passable, because the simulation
would not have routed it anywhere else.

**Why terrain passability and not the server's copy.** `SquadSim`'s
`_passable` has living buildings stamped out of it
(`Server._refresh_passability`), so squads walk around a town hall. A
client under fog cannot reproduce that set. Clamping against it would put
the two sides in different places for a reason neither could detect —
D-022's audit block, rebuilt from parts. Water and rock are what #97 is
about, they come from `MapSettings` over the wire, and both sides derive
them from identical numbers; `tests/test_formation.gd` asserts the
client's array is byte-identical to the one the server builds.

**Cost, measured, with the caveat first.** One `TorusSpace.world_to_cell`
plus one array index per soldier per frame; the pull loop only runs for
the handful of men actually over water or rock, and the empty-array case
is hoisted out of the derive loop, so every caller without terrain — the
server, the profile sweep, every test — derives at exactly the cost and
to exactly the bit it did before.

The A/B was taken headless rather than through `bench-render`, because
M5 measured this frame as 97% CPU in per-soldier derivation, so the
term that moves is a CPU term. 625 squads x 40 soldiers on the shipped
168x194 map, interleaved, best-of-9 per configuration:

| run | without | with | delta |
|---|---|---|---|
| 1 | 12.08 us/soldier | 17.75 us/soldier | +47% |
| 2 | 14.96 us/soldier | 27.04 us/soldier | +81% |

**Both absolutes are junk and the spread says so.** They are ~8x M5's
0.72 us/soldier for the same work, and a bare `world_to_cell` + index
priced at 3.5 us in the same process is roughly thirty times what that
arithmetic can cost — the host was running five other worktrees' docker
suites throughout, which is CLAUDE.md's own "worst ticks measured while
the host was building containers" warning arriving again. What survives
is the shape: the clamp costs **tens of percent of the per-soldier
derivation path**, it is not a rounding error, and **a clean
`bench-render` A/B on an idle machine is still owed** — the same status
D-097 gave its own 1,000-squad numbers.

**If M10 needs that back, the lever is a per-SQUAD test, not a faster
per-soldier one.** The expensive part is `world_to_cell`, which D-008
forbids anyone from reimplementing; the cheap version of this question is
"is any cell within the squad's footprint impassable", answered once per
squad from `TorusSpace.disk_offsets` (integer offsets, no world
conversion) and skipping every per-soldier lookup for the overwhelming
majority of squads that are nowhere near water. That is deliberately not
in this change: it is an optimisation, the measurement that would justify
it cannot currently be taken cleanly, and D-021's rule is evidence rather
than suspicion.

**Rejected alternatives:**

- **Nearest passable cell per soldier** — truthful, and the first idea in
  #97, but it tears the formation and its walk is unbounded on the client's
  hottest loop. See above.
- **Shrink or reshape the footprint when it overlaps rock.** Cheaper
  (per squad, not per soldier) but it changes formation SHAPE as a side
  effect of terrain, and shape is tactical information a player reads off
  the screen — the same objection D-045 makes to drawing a distant squad
  smaller.
- **Refuse the parking spot: forbid a squad settling where its footprint
  overlaps impassable ground.** Cheapest of all and a good idea on its own
  terms, but it is a placement rule, it does nothing for a squad merely
  marching along a shoreline, and it belongs with the movement-order work
  rather than here.
- **Marking the cliff-adjacent band impassable so the picture and the sim
  agree trivially** — already rejected by D-097, and it deletes visibly
  flat walkable ground.

**Consequences:**

- **D-097's "rendering only" clause is narrower than it was written.**
  It justified `cliff_rise` partly with "nothing stands on impassable
  ground for the offset to disagree with". Soldiers did. The simulation
  half of that claim is untouched — `passability` still thresholds the
  unscaled elevation and the wall still stands exactly where it changes —
  but the rendering side now has to know about passability, and does.
  D-097's own file carries the amendment.
- **`SoldierMotion` (D-059) smooths what is left.** The clamp is a
  discontinuity in the authoritative slot; the client eases toward that
  slot rather than teleporting to it, so a man pushed off the rock walks
  off it. That is cosmetic and one-way, as clause 2 requires.
- **The server does not clamp**, because nothing on the server reads a
  soldier position: combat, vision and the composition hash are all
  squad-level. `SquadSim.soldier_transforms` was already the reference
  path rather than the shipping one (it passes no height sampler either
  and answers y=0). If a server-side consumer of soldier positions is
  ever added, it must be handed the terrain-only array, not `_passable`.

**Revisit trigger:** a soldier position becoming something the simulation
reads — per-soldier hit resolution, per-soldier collision, anything that
makes where a man stands an OUTCOME rather than a picture. At that point
the clamp stops being free and D-006's revisit trigger has fired anyway.
Also revisit if `PASSABLE_PULL_STEPS` ever has to grow: four steps is fine
while a formation's half-width is a handful of hexes, and would not be for
a formation an order of magnitude wider.

---
