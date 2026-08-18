# D-20260818 · 2026-08-18 · Accepted — pathing knows only what the player knows

**Decision:** a flow field is solved against what its mover's SIDE
believes the ground to be, never against the simulation's ground-truth
passability array. `terrain_knowledge.gd` owns that belief;
`SquadSim._fields` is keyed on `(destination, side)` instead of
`destination` alone.

The standing rule, stated once so anything downstream can cite it:

> **The simulation may never route a squad around, or refuse to move a
> squad because of, terrain its owner has not discovered.** Anything that
> plans a route, or decides a route is impossible, reads
> `TerrainKnowledge`. `SquadSim._passable` is ground truth and answers
> exactly one question: may a squad physically STAND here, right now.

Five clauses:

1. **Belief is optimistic: unknown ground reads PASSABLE.** One byte per
   cell per side; 0 means "this side has observed that cell and it is
   blocked", anything else means known-open *or* never looked at. So a
   squad takes the shortest route it has no reason to doubt. Fog can be
   hiding a ramp, and the honest answer to "is there a way through" is
   "try it".
2. **A side is Vision's knowledge group, not a player.** Allies share
   sight (D-050), so they share belief and share fields.
   `Vision.group_of_player` is the one definition of that grouping — a
   second copy of the arithmetic would eventually disagree, and the
   symptom would be an ally pathing differently from you through ground
   you both explored.
3. **Discovery has two sources, and the second is the safety net.**
   Sight: `TerrainKnowledge.absorb` folds the coverage `Vision.rebuild`
   has already stamped into belief, on vision's own cadence, so pathing
   knowledge can never be wider than sight and no disk is walked twice.
   Touch: `_rebuild_curve` checks every step it is about to write against
   ground truth, so a squad learns what it is about to walk onto whatever
   its `vision_range`. Optimism may plan a route into a mountain; it may
   never put soldiers inside one.
4. **Discovery re-routes by dropping the field, not by patching it.** A
   planned step onto ground the side now knows is blocked means the
   cached field predates the knowledge: it is erased, the curve keeps the
   prefix already written (so the squad walks up to the obstruction while
   the replacement solves), and every squad sharing that field gets the
   corrected route with it.
5. **Refusal survives, with a narrower input.** The give-up rule
   (`curve.key_count() <= 1` → treat the current cell as the destination)
   is unchanged in shape and now fires only when the ground the player has
   actually SEEN proves the destination impossible. It is held off for the
   one tick between discovering an obstruction and re-solving around it,
   because otherwise walking into the first unknown wall would read as a
   refusal and cancel a perfectly good order.

## Rationale

Reported by the owner from playtest P06 (issue #96), playing
`quick-test` on `continents`: a squad ordered across the map immediately
rounded lakes, mountain ranges and walled-off pockets nobody had ever
seen, and an order into an unexplored pocket that happened to be sealed
was refused **on the tick it was given**. Fog hid the terrain visually
while movement acted on the whole map.

**This is not a regression and no number could see it.** Every field was
optimal, every refusal accurate, and both were derived from data the
player does not have — `flow_field.gd`, `squad_sim.gd` and
`torus_space.gd` have behaved this way for as long as flow fields have
existed. It is the *declared-and-unread* family inverted: nothing was
missing and nothing was unread, the input was simply wider than the
player.

### Why optimism, and why the error must lean that way

The owner's refinement on #96 settles the direction:

> a unit should assume it can get somewhere if the player visible land
> mass doesn't prevent it (i.e. fog could be hiding a ramp until proven
> otherwise so try that route)

Which gives the invariant everything downstream leans on:

    believed-passable ⊇ truly-passable

so **belief-unreachable implies truly-unreachable**: a side can only ever
be refused an order that was genuinely impossible, never one that would
have worked. That asymmetry is deliberate and is the reason optimism is
the right default rather than merely a cheap one — being wrongly refused
an order is far more noticeable, and far more annoying, than marching
somewhere and finding a dead end, because the second is a mistake the
player understands making.

It also preserves D-040's "unreachable now is unreachable later"
reasoning, which the give-up rule depends on to avoid an invalidation
storm: belief only ever LOSES passable cells, so further exploration can
never re-open a destination the known map has ruled out. Only passability
itself changing can, and `set_passable`'s deferred-order retry already
covers that.

The one seam in the invariant is passability that CHANGES: a gate (D-076)
seen closed and later opened out of sight stays believed-shut until
somebody looks again. That is fog behaviour rather than a bug — the
client still draws the structure it last saw (D-030), so the refusal
matches what is on the player's screen — and `absorb` repairs belief in
BOTH directions the moment the cell is covered again, so a side is never
wrong about ground it can currently see. A player's own gate is inside
their own buildings' vision by construction.

### What this costs D-007, which is the real question

D-007's scaling claim is that ONE field per destination serves every
squad heading there, and keying fields on knowledge threatens exactly
that. In the worst case the issue names, live fields multiply by the
player count.

That worst case does not happen, because **the sharing that was ever
load-bearing is sharing between squads of one side.** A player ordering
fifty squads to one place still solves one field; so does a team, since
allies share belief. The multiplier only bites when two *different* sides
order squads to the *same* cell — which is a coincidence of clicks, not a
pattern, and each side genuinely has a different answer.

Per-cell cost is unchanged: `FlowField` still reads one byte per cell and
neither knows nor cares which array it came from. `absorb` walks coverage
`Vision` has already built, so no disk is stamped twice, and its inner
loop lives inside `TerrainKnowledge.Side` so the byte write is in place —
a `PackedByteArray` fetched out of a dictionary is a copy-on-write COPY,
and a discovery written through one would be silently lost. A sim with no
terrain holds no belief array at all and pays literally nothing, which is
most of the test suite.

## Rejected alternatives

- **Per-player fields (rather than per-side).** Truthful and simplest to
  reason about, but it pays for D-050's shared sight twice: allies with
  identical knowledge would solve identical fields separately. Per-side
  is the same truthfulness with the team multiplier instead of the player
  multiplier.
- **One globally optimistic field plus per-squad local correction.** The
  cheapest option on paper and wrong on inspection: "optimistic" has no
  meaning without a knower. A single shared field would have to treat
  ground *everyone* has explored as passable too, so a player who had
  scouted a lake would still walk their army into it. The correction
  would also have to live per squad, which is state D-006 would then have
  to be argued with.
- **Coarse knowledge quantisation (share a field between sides whose
  relevant knowledge matches).** A cache-key optimisation for a cost that
  measurement has not yet shown to exist. Available later if field counts
  ever become the binding constraint; it changes nothing about the rule.
- **Invalidating a side's fields whenever it discovers any blocked
  cell.** The obvious way to "re-route on discovery" and the expensive
  one: a squad marching along a coast discovers blocked cells almost
  every vision rebuild, and nearly none of them are on anybody's route.
  Checking the planned STEP instead is precise — it fires exactly when a
  discovery is actually in somebody's way — and costs one array read per
  step written.
- **Making `_approachable` fog-aware too.** Deliberately out of scope,
  and left as ground truth. It answers "can a squad STAND here", which is
  a physical fact the simulation must not lie about, and it corrects a
  destination rather than choosing a route — it can never refuse an
  order. The omniscience it retains is small and helpful (a click on
  unseen water near a shore snaps to the shore instead of marching there
  and stopping). Worth revisiting only if a playtest reports it.
- **Notifying the player that an order was refused.** #96 asks for this
  to be settled here, and the answer is **not now, and not as part of
  this**. Under this decision a refusal means "the ground you have
  explored proves this impossible", which is information already on the
  player's own screen — and the wire, the HUD and the order-feedback
  surface are a different change touching different files. Filed as the
  follow-up below rather than smuggled in.

## Consequences

- **Squads take longer, wronger, more human routes**, and marching time
  into unexplored ground goes up. That is the feature.
- **`SquadSim.route_discoveries` is new instrumentation**: planned steps
  that ran into ground the mover's side had not known was blocked. A
  match with terrain reporting ZERO of these is one where the mechanism
  is quietly dead — this project's most-repeated defect — so it is
  counted rather than assumed.
- **`_pending_fields` holds `_fields` keys, not bare destinations.** The
  same destination can genuinely be in flight for two sides at once.
- **The wall-top tier (D-076) is deliberately NOT fogged.** Its network is
  made of buildings a side put there itself; there is no unknown ground
  in it to be optimistic about, so `_field_for_top` still solves against
  `_passable_top`.
- **An AI player is held to this like everyone else** (D-051). It is a
  client without a socket, its squads have an owner, and its routes come
  out of the same belief. Nothing in `ai_player.gd` changes.
- **#120 (an explore command) depends on this rule existing.** "Explore"
  is only a meaningful order once the simulation distinguishes ground a
  player has seen from ground that merely exists; `TerrainKnowledge` is
  where that distinction now lives, and an explore order should be
  expressed as a destination chosen from it rather than as a new kind of
  movement.
- **Follow-up, not built here:** an order that has been refused should
  say so (a notification, or the order visibly cancelling) rather than
  the current silent stall. Under this decision a refusal becomes a
  legitimate outcome of a reasonable order rather than an error, which
  makes the case for feedback stronger than it was, not weaker.

## Revisit trigger

- Field COUNT becomes a binding cost — either memory (fields are cached
  for the life of the match and are ~5 bytes/cell each) or
  `ticks_with_pending_fields` climbing with player count rather than
  squad count. The answer then is knowledge quantisation, above, not
  going back to ground truth.
- `route_discoveries` climbing fast enough that field re-solves show up in
  `total_field_usec`, which would mean sight is not getting ahead of feet
  — most likely a `vision_recompute_every_ticks` problem rather than a
  pathing one.
- Terrain-occluded line of sight (D-025's deferred item) lands. It changes
  which cells `Vision` stamps and therefore what a side may learn, but
  nothing about the shape here.
