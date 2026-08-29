# D-20260828 · Explore is an order, and the frontier is knowledge

**Status:** ACCEPTED. **Closes:** #120. **Extends:** D-004/D-025 (fog is
curve gating, and there is one fog query),
D-20260818-pathing-knows-only-what-the-player-knows (belief, and its
optimism), D-007/D-038 (shared per-destination fields, and coarse
snapping), D-034 (attack-move, the standing order this is shaped after).
**Constrained by:** D-006/D-024 (squad-level only), D-051 (an AI is held
to every rule a human is),
D-20260818-every-microsecond-of-a-tick-has-a-phase.

## Decision

A sixth squad order, **explore**: the player issues it once and the squad
uncovers ground on its own — picking a destination, walking, revealing,
repicking — until it is given another order, routs, or dies.

Four pieces:

- **`ExploreTarget`** (new, all-static, pure) — THE definition of "pick
  the next unexplored destination".
- **`TerrainKnowledge.Belief.explored`** — a per-side ever-observed set,
  accumulated in the pass that already folds sight into knowledge.
- **`SquadSim._explore`** — one byte per squad, plus a repick pass on
  vision's cadence charged to its own tick phase.
- **`C2S_ORDER_EXPLORE` (39)** and an `exploring` byte on `SQUAD_INFO`.

## The frontier is `TerrainKnowledge`, not a new field (#120 point 4)

`Vision` answers *can this side see the cell now*. A scout needs *has
this side ever been shown it* — the same currently-visible versus
ever-revealed distinction D-026's hash had to get right, and the issue
names it as the input.

That set did not exist server-side. `Belief.believed` looks like it
should serve and cannot: it starts **all-1** because unknown ground reads
passable (the optimism that makes a squad find out by walking), so
`believed[c] == 1` cannot separate "never seen" from "seen, and open".

So `Belief` gains a second array — **in the object that already folds
sight into knowledge, on vision's own cadence, out of vision's own
coverage.** That is deliberately not a second fog query: D-004 forbids a
second data-hiding path, and a per-player explored field maintained
anywhere else would be exactly that. It costs one byte per cell per side
and one store inside a loop that was already running.

**The two defaults deliberately disagree.** Unknown ground is
*optimistically passable* (so a squad will walk into it) and
*pessimistically unexplored* (so a scout will go and look at it). Both
push the same way: toward finding out.

### The ordering trap, which was real

`observe()` skips cells whose passability it already agreed with — and on
open ground that is most of the map. With the explored write placed after
that skip, almost nothing is ever marked seen, and a scout is told the
whole map is unexplored forever and repeatedly sent to the cell it is
standing on. The write goes first, and the guard was observed to fail
with it moved.

### `absorb` no longer bails out when there is no terrain

It returned early on an empty `truth`. Passability is unknowable without
truth; **what a side has seen is not**, and fog exists on a sim with no
terrain array. It now takes a `cell_count` fallback. This surfaced as
three test failures with one cause — a headless sim could accumulate no
knowledge at all.

## It is not omniscient, and that is structural (#120 point 1)

The issue is right that this is #96 in a more dangerous form: here the
**simulation** picks the destination rather than a player clicking one,
so "it only uses what the player knows" has to be built rather than
asserted.

`ExploreTarget.next_destination` is handed the asking side's `explored`
and its `believed_passable`, and nothing else. **There is no argument
through which ground truth could arrive.** A target is rejected only if
the side has *observed* it is blocked; unknown ground is a legitimate
place to walk at, and finding out it is a bay is the intended outcome.

One honest caveat, unchanged rather than widened: `_apply_move_order`
still snaps a destination through `_approachable`, which reads truth.
That is pre-existing, applies identically to every order, and is
explicitly scoped out by
D-20260818-pathing-knows-only-what-the-player-knows ("deliberately still
omniscient... corrects a destination rather than choosing a route"). An
explore order goes through the ordinary move path precisely so it
inherits that behaviour rather than inventing a second one — but the
influence is larger here than for a player's click, because the sim
chose the cell. Named as a known edge, not a claim of purity.

## Targets are REGIONS, because fields are shared (#120 point 2)

D-007's per-destination sharing is the scaling claim and the issue
correctly names N scouts each demanding a unique frontier CELL as its
pathological case — on a map where a squad already waits for a path
(#107).

A target is therefore snapped exactly as a rout's is (`rout_quantum`,
D-038) and for the identical reason: **nobody chose the exact cell**, so
precision buys nothing and sharing buys a lot. `explore_quantum` is **4**
rather than the rout's 8 so the worst snap error (3 cells) stays well
inside every roster unit's vision radius — the squad arrives at the
region and can *see* the frontier it was aimed at.

Two scouts of one side are additionally kept off each other's regions by
a `claimed` set the sim gathers fresh each pass from its own
destinations. Gathered rather than remembered: a cached copy of a fact
the simulation already holds is the shape of the D-038 ownership cache
that silently refused every produced squad an order.

## Repicking

"Run out of journey" is **`is_idle`**, which covers arrival *and* a
destination given up on as unreachable (`_deferred_destination`). A scout
that walked at a sealed pocket and stopped forever would be the more
embarrassing of the two failures.

The pass runs on **vision's cadence**, immediately after the stamp that
feeds it — the explored set is the input, so repicking between rebuilds
would re-read an identical map and re-answer identically.

It is charged to its **own phase** (`explore`), not folded into vision's.
D-20260818 requires the phases to partition the tick exactly, and a pass
without its own accumulator lands in `other`.

`explore_repicks` and `explore_exhausted` are instrumentation in
`field_waits`' style — and they are two counters rather than one because
"the map is uncovered" and "the picker is broken" both produce a squad
that stops moving, and those are different facts.

## Cancellation

Move, attack-move and stop all clear the flag, exactly as they clear a
charge: **a mode a player cannot turn off by giving an ordinary order is
a mode that has taken the squad away from them.** There is deliberately
no `stop_exploring` opcode — a second way to cancel is a second rule.

A **rout** clears it too. Without that, the repick pass sees a fleeing
squad arrive at its rout destination, calls it idle, and sends it back
toward the fog it just ran away from — which is where the enemy is.

`order_explore` refuses a routed squad, like every other player order.

## The wire (#120 point 5)

One new opcode carrying a squad id and **no destination** — declining to
choose one is the whole request — so it is shaped like `ORDER_STOP`, not
`ORDER_MOVE`. Validated through `_validated_squad`, the same shared
helper as every other squad order, so a hand-crafted packet can start no
scouting a button could not.

`SQUAD_INFO` gains one `exploring` byte, riding the existing message
exactly as the stance byte does. Explore is a MODE, and a player who
cannot see that it is still on cannot tell "scouting" from "stopped
somewhere odd". It is **not** in `composition_hash`: it is a display
fact, and hashing it would make an ordinary mode change read as a desync
on a healthy system.

## Cost

One pass over REGIONS, not cells — `(width/q) * (height/q)`, so 2,058 on
the shipped 168x194 map at quantum 4 against 32,592 cells — and only for
squads actually repicking, on vision's cadence. The scan is whole-map
rather than an expanding ring on purpose: a ring terminates early in the
easy case and degenerates to a `disk_offsets` table the size of the map
exactly when the frontier is far, which is the case a late-game scout is
always in.

Measured in `just test-load 4 120`: see the branch's PR. Quote it with
its squad count, as ever.

## Rejected

- **A per-player explored field of its own.** A second fog query is what
  D-004 forbids, and it would have had to be kept in step with the one
  `TerrainKnowledge` already maintains from the same coverage.
- **Explore as a stance bit.** The stance byte is a set of behaviour
  toggles that modify how a squad executes what it was told; explore
  *replaces* what it was told and repeatedly issues its own orders. Folding
  it in would have made "which stance bits cancel each other" a new rule.
- **Unique per-squad frontier cells.** The pathological case for D-007,
  named as such by the issue.
- **Choosing targets client-side and sending moves.** The client would
  need the explored set on the wire, which is both bandwidth and a
  data-hiding surface, and the AI would then need its own copy of the
  logic — the two definitions of exploring this decision exists to avoid.

## Deliberately not in scope

Everything #120 lists as out of scope (formation presets, patrol routes,
re-scouting stale ground), plus two named here:

- **What an exploring squad does when it meets something** (#120 point 3)
  is left as today's behaviour: it fights if engaged and routs if broken,
  and a rout ends the mode. Making a scout flee on contact is a real
  design question and wants its own decision, not a default smuggled in
  with the verb.
- **The AI does not use it yet.** The picker is pure and static
  specifically so it can, and that is the named follow-up. The risk of
  wiring it here is that `bot_patrol.gd`'s leg structure is what
  `test-load`'s `conceal_events`/`reveal_events` gates depend on, and
  changing scouting behaviour in the same branch that adds the verb would
  make a gate movement unattributable.

## Revisit trigger

If `explore_repicks` is ever zero in a match where a squad was ordered to
explore, the mechanism is dead — the failure this project keeps finding
wearing a green verdict. If the region scan shows up in the `explore`
phase at scale, the lever is an expanding ring with the whole-map scan as
its fallback, not a finer quantum.
