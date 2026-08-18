**Pathing knows only what the player knows
(D-20260818-pathing-knows-only-what-the-player-knows, 2026-08-18).** Flow
fields were solved against the sim's single ground-truth passability
array, so a squad ordered across the map rounded lakes, mountain ranges
and walled-off pockets nobody had ever seen, and an order into an
unexplored pocket that happened to be sealed was refused **on the tick it
was given**. Fog hid the terrain visually while movement acted on the
whole map. Found by the owner playing (#96, playtest P06), not by any
check — every field was optimal and every refusal accurate, which is
precisely why nothing failed.

The standing rule, which is the part worth carrying:

> **The simulation may never route a squad around, or refuse to move a
> squad because of, terrain its owner has not discovered.** Anything that
> plans a route, or decides a route is impossible, reads
> `terrain_knowledge.gd`. `SquadSim._passable` is ground truth and answers
> exactly one question: may a squad physically STAND here, right now.

Four things to know before touching movement:

- **Belief is OPTIMISTIC — unknown ground reads passable.** That gives
  `believed-passable ⊇ truly-passable`, so belief-unreachable implies
  truly-unreachable and a side can only be refused an order that was
  genuinely impossible. The asymmetry is deliberate: being wrongly
  refused is far more noticeable than marching somewhere and finding a
  dead end, which is a mistake a player understands making.
- **Fields are keyed on (destination, SIDE), and D-007's sharing
  survives** — because the sharing that was ever load-bearing is between
  squads of one side. Fifty squads sent to one place still solve one
  field; allies share it too (D-050). Only two *different* sides ordering
  to the same cell pay twice.
- **Discovery has two sources and the second is the safety net.** Sight
  folds `Vision`'s own coverage into belief on vision's cadence; TOUCH
  checks every step before it is written, so a squad with `vision_range`
  0 still learns, and optimism can plan a route into a mountain but can
  never put soldiers inside one.
- **A re-route DROPS the field rather than patching it**, and the give-up
  rule is held off for that one tick. Invalidating a side's fields on
  every discovered blocked cell was rejected as the expensive version:
  a squad marching a coast discovers blocked cells constantly and almost
  none of them are on anybody's route.

`SquadSim.route_discoveries` counts planned steps that ran into ground the
mover's side did not know was blocked. **Zero of those in a match with
terrain means the mechanism is dead**, which is this project's
most-repeated defect wearing a green verdict.

Deliberately still omniscient, and scoped out: `_approachable` (which
answers "can a squad STAND here", corrects a destination rather than
choosing a route, and can never refuse an order). Deliberately not
fogged: the wall-top tier (D-076), whose network is made of buildings a
side put there itself.
