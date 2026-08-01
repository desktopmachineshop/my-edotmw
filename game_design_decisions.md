# Game Design Decisions

Living decision log for my-edotmw. `CLAUDE.md` is the condensed ground-rules
summary of this file — if the two ever disagree, this file wins and
`CLAUDE.md` needs updating.

Format per entry: **ID · Date · Status · Decision · Rationale · Rejected
alternatives · Consequences · Revisit trigger**.

Status is one of:
- **Accepted** — settled, build against it
- **Provisional** — best current call, but explicitly cheap to overturn;
  has a revisit trigger
- **Superseded by D-0xx** — kept for history, no longer in force

New entries go at the top of section 1. Never edit history in place —
supersede instead, so the rationale trail survives.

---

## 1. Decisions

### D-027 · 2026-07-30 · Accepted
**Decision:** M3's exit criteria, written down before the code, in the
shape D-022 established and D-026 confirmed — each criterion names the
decision it discharges. M3 is D-015's **launchable MVP**.

M3 is complete when all of the following hold, `just test-unit` is green,
`just test-load` and `just test-client` report clean **with the PNG
actually looked at**, and a 4-player LAN match can be played start to
finish without restarting the server.

*The match*

1. **Match lifecycle exists** (D-033): lobby → start at the configured
   player count → play → elimination → victory → results. A disconnect
   eliminates that player and removes their army, rather than leaving it
   standing in the simulation as it does today.
2. **Victory by elimination is proven by a headless test** that plays a
   match to completion and asserts exactly one winner — not merely that
   the server did not crash.

*The client*

3. **Selection exists** (D-034): click-select, box drag-select, control
   groups. Right-click no longer means "order everything I own".
4. **A real command vocabulary** (D-034) — move, attack-move, stop,
   gather, build, produce, set-formation — each a distinct C2S opcode,
   each validated server-side per D-002. A client may not command what it
   does not own, and the server enforces that rather than trusting it.
5. **A HUD exists** (D-034): `client.tscn` gains a `CanvasLayer` carrying
   four resource readouts, a selected-squad panel (type, strength,
   morale, routing state), a production queue, match state, and a
   **wrap-aware minimap** — D-008's torus tax landing on the minimap
   exactly as CLAUDE.md predicts it will.

*The economy*

6. **Gatherer squads gather** (D-028): a worker squad assigned to a node
   collects, hauls to a drop-off, unloads and returns, in a loop. Output
   scales with `alive`. No per-soldier state anywhere (D-006 clause 1)
   and no per-unit pathfinding (D-005).
7. **Four resources, data-driven** (D-010): food/wood/gold/stone ledgers;
   `UnitDef.cost` becomes a per-resource cost table and building costs
   live in a new `BuildingDef`. Schema change recorded in D-010's log the
   way `formation_spacing` was.
8. **Hauling's re-pathing cost is measured** (D-003). Round trips
   invalidate curves continuously, which is precisely the
   invalidation-storm risk D-003 flags; the replicator's budget must
   absorb it and `test-load` must report it rather than leaving it
   assumed.

*Buildings — the second entity class*

9. **Buildings replicate without colliding with squads** (D-029). A
   sibling `BuildingSim` with its own packed arrays (D-009), its own id
   space and its own replicator. `CurveReplicator` and `ReplayLog` are
   already entity-agnostic and need no change; what must change is every
   call site assuming *object id == squad index*. **A test must construct
   a squad and a building at the same local index and prove neither leaks
   into the other's wire bytes, hash, or replay output.** This is the
   highest-risk item in the milestone.
10. **Construction progress is a curve** (D-003, which already names
    "build progress" as curve state) — two keyframes, costing nothing
    further until interrupted. Health replicates as **sparse events**
    like casualties, because health is event-shaped, not continuous.
11. **Player-placed construction works** (D-031): placement validated
    against terrain passability on the hex torus, progress visible to the
    owner, buildings destructible.
12. **Building fog is persistent-explored, not ghosting** (D-030). A
    building never moves, so there is no positional staleness; once seen
    it stays known with its state frozen at last-known. **The consequence
    is the trap:** its hash must be computed over a per-client
    *ever-revealed* set, never `visible_to()`'s current-tick answer, or
    the two sides hash differently-shaped sets and the desync check fires
    on a healthy system — the same failure D-025 part 3 and
    `composition_hash`'s header were written against, recurring in a new
    shape. Proven by a test that drives a building out of vision and back
    with the hash checked throughout.

*Combat*

13. **Four unit types with working counters** (D-032): armour class and
    bonus-vs-class multipliers in `.tres`, consumed by `combat.gd`. A
    test must prove the counter changes the outcome — a counter system
    nothing verifies is decoration.
14. **Combat resolves simultaneously** (D-024 amendment). Resolution
    reads round-start strengths, so squad id no longer confers a first
    strike, and a mirror matchup is symmetric by test.

*The world*

15. **The torus looks like a torus** (D-035): the camera wraps rather
    than panning into void, terrain renders continuously across the seam,
    and no entity is drawn outside the meshed world. Verified in the
    `test-client` PNG by looking at it.
16. **Spawns and nodes are map data** (D-036). `server.gd`'s hardcoded
    spawn formula and `client.gd`'s duplicate of it are both deleted.

*Standing obligations*

17. **Cost re-measured and quoted with counts** (D-020, D-012): µs per
    squad-update *and* per building/production update, with vision,
    combat and economy identifiable as components. M2 ended at 70.8
    µs/squad at 48 squads with combat as the hot spot — that is the
    baseline, and economy work must not quietly consume the headroom.
18. **Replays cover a whole match** (D-016): new record kinds for
    buildings and economy, reconstructed under their own top-level key
    rather than sharing a numeric keyspace with squads. `replay-info`
    reports buildings, final resources and the winner.
19. **Every new check observed to fail before it is trusted** (D-022's
    standing rule), with perturbations **applied and reverted atomically**
    — see D-026's completion block for why that wording is now explicit.
20. **Docs match the code**: `CLAUDE.md` and section 2 updated.

**Explicitly NOT in M3**, so scope creep stays visible: LOD (D-012, M5);
a second civilization (M6); any AI opponent (D-015); matchmaking or
internet play — LAN and direct-IP only, so Q3 stays open; reconnection
and desync recovery (Q10); persistence or saves (Q13); mesh tiers 2 and 3
(D-011); terrain-occluded line of sight (deferred by D-025).

**Rationale:** Written before the code for the third milestone running,
because it has now twice caught things a green suite could not — see
D-022's audit and D-026's completion block. Criteria 9 and 12 exist
because the review that produced them identified id collision and
hash-set mismatch as the two failure modes most likely to be invisible
until a live multi-client run.

**Rejected alternatives:** Deferring exit criteria until the work is done
(rejected twice already, for the reasons D-022 records). Treating "it
looks like a game" as the bar (rejected — that would pass without
criteria 9, 12 and 14, which are exactly the ones no playtest surfaces).

**Consequences:** M3 needs ten new decision entries (D-028 … D-036 plus
this one) and two amendments to D-024. It is by a wide margin the largest
milestone so far, adding a second networked entity class, a four-resource
economy, construction, a UI that does not exist at all today, and a match
loop. Implementation is sliced so a playable 4-player battle exists after
slice 1, before buildings or economy land: (1) playable skirmish, (2)
torus presentation, (3) buildings, (4) economy.

**Revisit trigger:** If M4 needs something M3 was assumed to have proven,
add it here rather than quietly widening the milestone.

**Reviewed against these criteria, 2026-07-31.** Written after the work,
by the same agent that did it — the arrangement D-022's audit warns
about — so it is stated as a checklist with evidence rather than a
verdict, and the gaps are listed as plainly as the passes.

*Met, with the evidence:*

1–2. Match lifecycle and elimination — `match_state.gd`, lobby →
running → finished, elimination read from `living_squad_count` so
"defeated" has one definition. Disconnect wipes the army and the ordinary
rule notices. Tested in `test_match.gd`, including the cases a smoke run
cannot distinguish: a match that never starts, one that declares a winner
instantly, one that never ends.
3–5. Selection, the command vocabulary, and a HUD — click, shift-extend,
box drag, Ctrl+1-9 groups; move, stop, attack-move, build, produce, each
a distinct opcode validated server-side through one shared helper; a
CanvasLayer with status, selection, controls and a wrap-aware minimap.
6–8. The economy — gatherer SQUADS (D-005 affirmed, not excepted),
four resources, biome-derived depleting nodes, round-trip hauling.
`test_economy.gd`.
9–12. Buildings — sibling `BuildingSim`, the id-collision test that
landed before any other building code, construction, and
persistent-explored fog whose hash is computed over the ever-revealed
set. A test hashes the *visible* set instead and asserts it desyncs, so
the trap is demonstrated rather than described.
13–14. Four unit types with a working counter triangle, and simultaneous
combat resolution. Perturbing the latter back to sequential makes mirror
matchups differ by exactly one soldier.
15–16. The torus renders as one — terrain tiled across both seams, the
camera wrapping in continuous lattice coordinates — and spawns are map
data with the duplicated formula deleted from both files that held it.
18. Replays carry buildings under their own top-level key, and
`replay-info` reports what was founded.
19. Every new check was perturbed, observed red, and reverted, with the
perturbations applied and reverted atomically after M2's review found two
left behind.

*Not met, and recorded rather than glossed:*

- **Criterion 17 is only half met.** Cost is measured and its components
  are identified, but the milestone changed the game's shape underneath
  the metric: an opening of one founding party means a run reaches a
  useful squad count only after production has been going for a while,
  and the per-squad figure is dominated by fixed overhead below ~20
  squads.

  The best M3 measurement, from `just test-load 4 180`: **100.95 µs per
  squad-update at 24 squads — vision 42.2, combat 54.6**, with four town
  halls standing. That is **not** comparable to the 65.2 µs measured at
  48 squads before the opening changed, and saying so is the point:
  CLAUDE.md's rule is that the figure is meaningless without its squad
  count, and here the counts differ. What IS comparable is the absolute
  work per tick — about **2.4 ms against a 100 ms budget** — which is the
  number that actually answers "does it keep up", and it does, with
  `dropped_ticks=0` throughout.

  Two things this milestone added that the metric now folds in: buildings
  contribute vision at a larger radius than squads, and their cost lands
  on whatever squad count happens to exist. A per-squad figure comparable
  to M2's needs a run that reaches ~48 squads, which needs production
  running longer than any current recipe does. That is M4's job, and M4's
  tiered sweep (D-027's own reference point) is exactly the shape of
  measurement this needs.
- **Criterion 20 is partly done.** `CLAUDE.md` describes slices 1–2; the
  economy and buildings are not yet in it.
- **Not attempted at all: the human 4-player LAN session** D-027's
  verification section calls the one criterion no automated check
  substitutes for. Everything above is machine-verified. Whether this is
  *fun* — whether founding, gathering and fighting hang together as a
  game — is untested, and that is the whole point of a "launchable MVP".

**M3 is therefore not declared complete.** The systems are built and
green; the milestone's own bar includes a thing no test can stand in for.
M1 and M2 were both declared done and then found incomplete, and the
honest reading of this checklist is that M3 is one playtest and one doc
pass away rather than finished.

**A playtest did happen, 2026-07-31/08-01 — one human against three
bots.** Recorded because it is the only part of that criterion which has
been discharged, and because what it found is the argument for the
criterion existing at all.

It produced four defects in about twenty minutes, none of which 260
passing tests had caught:

1. **The minimap hit-test swallowed every click.** Hit-testing asked the
   `TextureRect` for its own rectangle; when that reported larger than
   intended, every click on screen counted as a minimap jump — so
   selection AND ordering died together. A guard had silently expanded to
   cover everything it was meant to exclude.
2. **A player with a standing base was declared defeated.** Elimination
   tested squads only, and founders are consumed by the hall they found,
   so making the *correct opening move* ended your match — after which
   the server refused every order you sent.
3. **Founders were consumed on completion rather than on order**, leaving
   a 40-second window in which one founding party could found unlimited
   town halls. The playtest founded three in about five seconds.
4. **Refused orders were silent.** A build nine cells from its founders,
   against a three-cell reach, did nothing and said nothing — a refused
   order was indistinguishable from a broken key.

Each is fixed with a regression test. The pattern across all four:
**bots do each thing once, in the expected order, and never press the
same key three times in five seconds.** Every automated run exercised
only the path on which the defect is invisible. That is not a gap in the
suite's thoroughness — it is the difference between verifying a system
and using one, and it is exactly why D-027's verification section named a
human session as the criterion no automated check substitutes for.

**What remains undischarged is narrower than "a playtest": it is the
judgement.** Whether founding somewhere feels like a decision, whether
losing the founders lands as a fair price at the moment it happens,
whether fog at 128x64 hides too much, whether the counter triangle reads
at the speed a fight actually happens. Four human players, and an
opinion. Nothing in this repository can produce that, and a milestone
named "launchable MVP" should not be closed without it.

**Amended 2026-08-01, by Dave's call: the session criterion is ONE human
against three bots, plus a written judgement.** Four humans on four
machines is a logistics problem rather than an engineering one, and it
would leave M3 unclosable on any timescale a solo developer controls. One
human against three bots is the strongest verification this project's
actual team can produce — and it has already demonstrated its worth by
finding four defects in twenty minutes that 260 tests had not.

This is a deliberate lowering of the bar, recorded as such. The risk it
accepts: three bots are not three people, and the things four humans
would surface — collusion, unexpected build orders, someone doing the
thing nobody designed for — stay untested until M7's Steam work brings
real opponents.

**And a scope reversal that makes it defensible: BOTS ARE NOW A SHIPPED
FEATURE.** D-015 scoped M3 with "no AI opponent", so bots existed purely
as a load-test fixture. Dave's call reverses that — they ship, which
means effort spent making them cleverer and more genuinely competitive is
product work rather than test scaffolding.

The reason this matters beyond the feature list: it removes the tension
that has quietly shaped every load test so far. Bot behaviour was written
to *exercise code paths* — converge here, raid there, found once — and
that is exactly why every defect the human playtest found was invisible
to them: bots did each thing once, in the expected order. Making them
play to win instead of play to cover makes them better opponents AND
better tests at the same time, with no conflict between the two goals.
The reverse held before: every hour spent on smarter bots was an hour
spent on scaffolding.

Consequences: D-015's "no AI opponent" cut line no longer holds and
should be treated as superseded for M3 onward. Bot quality becomes a
product concern with its own budget, and D-018's scale targets now have
to accommodate whatever an AI opponent costs per player at full scale —
worth measuring at M4 rather than assuming it is free.

**Amended 2026-07-30, when the seven open items closed** (see section 2).
Four resolved as recommended and change nothing here. Three did not, and
these criteria change with them:

- **Criterion 1 gains a squad cap.** A per-player cap is enforced
  server-side at production time, and a test proves production is
  *refused* at the cap — not merely that the cap exists as a number.
  **One shared cap covers military and gatherer squads alike**, so the
  test must show *both* production paths — barracks and town centre —
  refusing against the same ceiling, and a gatherer squad consuming a
  slot a military squad could have used. A cap that only one path
  respects is worse than none, because the player would discover it by
  being unable to explain their own economy.
- **Criterion 6 gains private wallets.** Wallets replicate to their owner
  only, proven byte-level in the shape D-026 criterion 6 used for fog: an
  opponent's client receives zero wallet bytes. Nodes are biome-derived,
  deplete, and their remaining stock replicates under criterion 12's
  persistent-explored rules — a reuse of that mechanism, never a second
  one.
- **Criterion 9 covers four building types, one of which shoots.** The
  tower makes buildings attackers rather than only targets. Buildings
  resolve attacks in a pass **separate** from the squad path, and a test
  proves a tower damages a squad without any squad-only code becoming
  reachable for a building — `_check_rout` calls `force_move`, and a
  building has neither morale nor the ability to move.
- **Criterion 14 also closes D-024's last open item**: rout resolves as
  rally-with-hysteresis, the behaviour already implemented.
- **Criterion 16 becomes map generation, not just map data.** The map is
  128×64; generation is quadrant-symmetric; spawns sit at identical
  relative offsets per quadrant. **A test asserts `elevation_at(x, y) ==
  elevation_at(x + width/2, y) == elevation_at(x, y + height/2)` for
  every cell** — exact, cheap, and trivially observed to fail by
  perturbing the symmetry factor. Three constraints ride along:
  `elevation_frequency` halves to preserve apparent feature size, width
  and height must divide by the symmetry factor with height still even
  (D-008), and **the symmetry order is tied to the player count** —
  changing from 4 players is a generation change, not a config tweak.
- **Criterion 17 gains flow-field build cost**, reported separately now
  the map is 4x larger, against the pre-change baseline of 70.8 µs/squad
  at 48 squads.

**Consequence for sequencing:** the map change moves to slice 1, ahead of
everything else, so every later measurement is taken against the real map
rather than needing to be re-based. Slices are now: (1) map foundations,
(2) playable skirmish, (3) torus presentation, (4) buildings, (5)
economy. D-036 and D-037 are added to the entries this milestone needs.

---

### D-026 · 2026-07-30 · Accepted
**Decision:** M2's exit criteria, written down before the code, in the
same shape D-022 established for M1 — each criterion names the decision it
discharges. M2 is "combat + fog of war" and nothing else.

M2 is complete when all of the following hold, `just test-unit` is green,
`just test-load N DURATION` reports clean, and `just test-client` reports
clean **with its PNG actually looked at**:

1. **Combat is D-024's model, at squad granularity** (Q7, D-005, D-006).
   Resolution is squad-level and stochastic; the server is the only side
   that resolves it. No per-soldier state exists anywhere in the
   simulation — `Formation` remains all-static with no instance fields,
   and nothing stores a soldier's health, target, or position.
2. **Combat is deterministic given a seed** (D-016). The RNG is seeded
   from map configuration and advanced in squad-id order, never from
   wall-clock time, so the same inputs produce the same battle twice.
   Proven by a test that runs an engagement twice and compares outcomes.
3. **Casualties replicate as sparse reliable events** (D-006's "combat
   outcomes replicate as sparse reliable events, not continuous
   per-soldier state"), sent only when a squad's strength actually
   changes. A tick in which nobody dies sends zero casualty bytes, and a
   squad that is idle and not fighting still costs zero bandwidth
   (D-003). Proven by a byte-count test, not by inspection.
4. **Morale and routing exist at squad level** (D-019). Morale falls with
   casualties, a squad below its `rout_threshold` routs, a routed squad
   flees and does not obey player orders while routed, and there is a
   defined path back (rally or permanent). Tested at the sim level.
5. **Fog of war is curve gating and nothing else** (D-004). `SquadSim.
   visible_to()` returns a real per-player set computed from D-025's
   vision field. No second data-hiding mechanism is introduced, and
   D-022's "known stub: `visible_to()` returns every squad" note is
   closed rather than restated.
6. **Fog is proven to hide, from the wire** (D-004, and the audit rule
   that a check must observe the thing it claims). A test shows a client
   receives **zero curve bytes** for an enemy squad outside its vision —
   byte-level, not "the client chose not to draw it" — and that horizon
   clipping still applies to a squad the moment it is revealed, so
   D-003's intent-leakage property survives reveal.
7. **Reveal and conceal follow D-025**: true-position pop-in on reveal,
   stale flagged ghost on conceal, conceal delivered as an explicit event
   so both sides agree which squads are live. No synthetic catch-up
   curves anywhere.
8. **The desync check stays meaningful under fog** (D-006's protocol
   obligation). Client and server hash the same set — ghosts excluded by
   construction — `state_hash_checks > 0` remains a verdict condition,
   and composition now changes during a run (casualties), so the check is
   exercised against moving state rather than a constant.
9. **Every new check is observed to fail before it is trusted** (D-022's
   audit rule, standing). The load test's verdict gains conditions that
   combat rounds were resolved, casualties were applied, and both a
   reveal and a conceal occurred — because a fog test in which nothing
   was ever hidden, or a combat test in which nobody died, proves
   nothing. Each new condition is perturbed, watched go red, and
   reverted, and that is reported.
10. **Cost re-measured and quoted with a squad count** (D-020, D-012).
    `test-load` still prints µs per squad-update, with vision and combat
    identifiable as components, compared against D-020's ~50 µs budget
    and extrapolated to D-018's counts. Per CLAUDE.md the number is
    meaningless without its squad count.
11. **Replays can explain a battle** (D-016). Casualty and rout events
    are in the curve log, and `just replay-info` reconstructs final squad
    strengths. The server's replay is deliberately unclipped ground truth
    — it contains what fog hid from every client — and that is written
    down so nobody "fixes" it into per-client logs.
12. **New stats are data, and the schema change is recorded** (D-010).
    Vision range, combat, and morale tuning live in `UnitDef` fields and
    `/units/*.tres`, not as constants in scripts, and the schema addition
    is logged against D-010 the way `formation_spacing` was.
13. **The docs match the code**: `CLAUDE.md`'s status section, section 2's
    Q7 entry (struck through), and D-004's status (Provisional →
    Accepted, semantics closed by D-025).

**Explicitly NOT in M2**, so scope creep is visible if it happens:
economy or production of any kind; LOD (D-012, M5); terrain-blocked
line of sight — vision is radius-only over the torus and elevation does
not occlude, stated rather than assumed; buildings; additional civs
(D-015); unreliable-with-resend transport (an M4 measurement); and any
per-soldier combat resolution (D-024's rejected alternative).

**Rationale:** M1's first "complete" was declared against criteria the
same agent wrote while building, and it drifted to fit what was produced
(see D-022's audit). Writing M2's criteria before any M2 code exists, and
deriving each from an already-accepted decision, is the cheapest available
defence against that recurring. Criteria 3, 6, and 9 exist specifically
because M1's equivalents were satisfiable vacuously.

**Rejected alternatives:** Deferring exit criteria until the work is
done (rejected — that is precisely the failure D-022 documented).
Reusing M1's criteria with combat appended (rejected — fog changes what
"client and server agree" even means, because they now agree about
different sets; that needs its own criterion, which is 8).

**Consequences:** Criterion 9 makes the perturbation evidence a
deliverable, not a private step. Criterion 11 extends the replay format,
which is a wire-format change under D-016 — the log stays byte-identical
to what is sent, so the casualty event has one definition in
`NetProtocol` used by server, client, and replay alike.

**Revisit trigger:** If M3 needs something M2 was assumed to have proven,
add it here rather than quietly widening the milestone.

**M2 was declared complete 2026-07-30, after a review that first found it
incomplete.** Recorded here because the pattern is now twice-confirmed:
writing the criteria before the code (this entry) worked, and reviewing
against them still caught three failures that every test suite passed.

What the review caught, all three invisible to `just test-unit`:

1. **Criterion 10 — cost was 5.6x over budget.** 282 µs per squad-update
   at 48 squads (vision 232, combat 47), against M1's 1.5–2.7 µs for the
   same 48. Both `Vision._stamp_squad` and `Combat._find_target` called
   `TorusSpace.distance()` once per candidate cell of a hex disk, and
   `distance()` → `delta()` evaluates nine ghost-copy candidates and
   allocated two array literals per call. The fix is geometric, not
   architectural: **a hex disk is translation-invariant on a torus**, so
   the offsets within a radius are computed once, cached
   (`TorusSpace.disk_offsets`), and reused for every squad and every
   rebuild — zero distance calls while stamping. Now **70.8 µs/squad at
   48 squads (vision 15.3, combat 45.5)**, ~71 ms inside a 100 ms tick at
   D-018's counts. D-020 was never in question; the implementation was.
2. **Criterion 11 — replays were silently truncated.** `just replay-info`
   on a real run reported "final strengths (0 squads known)" from a file
   exactly 512 bytes long — a buffer boundary. Nothing in the codebase
   ever called `flush()`, and `docker compose stop` sends SIGTERM, which
   Godot headless does not run `_exit_tree` for, so `close()` never ran.
   This predates M2 and was harmless while replays held only curves; M2
   made it matter, because composition and casualty records are written
   *after* the curves and so were exactly what got cut. `ReplayLog` now
   flushes per record.
3. **Criterion 11's visual half proved M1, not M2.** `test-client` ran a
   single client against a server with no opponent — `ghosts=0`, every
   squad at full strength — so the frame could not contain a casualty or
   a ghost however carefully anyone looked at it. It now runs bots
   alongside the client, and the verdict requires casualties, conceals
   and reveals to have happened. A worker also found, while fixing this,
   that `GeometryInstance3D.transparency` renders nothing under the
   `gl_compatibility` rasteriser `test-client` is forced to use, so the
   ghost fade was invisible — replaced with material-level alpha.

**And a process failure worth more than any of them.** Two workers were
interrupted mid-perturbation and each left a live perturbation in the
tree: a counter increment replaced with `pass`, and `_max_known_squads()`
hardcoded to `return 999999`. Either would have shipped a check that
could never fail — the precise defect D-022's audit exists to prevent,
reintroduced *by the discipline meant to prevent it*. Both were caught by
grepping the tree during review rather than by any test, because a
permanently-passing check is invisible to a green suite by definition.
**Apply and revert a perturbation within a single atomic step**, and
grep for leftovers before trusting a suite. Added to the standing rule in
D-022 rather than replacing it.

Not everything found was fixed. Two items were logged to section 2
instead, both out of D-026's scope: combat's sequential resolution order,
and a seam-crossing rendering artifact visible in the M2 frame.

---

### D-025 · 2026-07-30 · Accepted — closes D-004's Provisional semantics
**Decision:** Three parts, all riding on D-003/D-004's curve gating.

1. **Vision is a per-player field over cells, not a per-pair test.** Each
   tick (or each vision-recompute interval, which may be lower), each
   player's vision coverage is stamped once from its own squads'
   positions and `vision_range`, and a squad's visibility is then a
   single O(1) lookup into the owning player's coverage. Vision is
   radius-only on the torus via `TorusSpace.distance` — elevation does
   not occlude in M2.
2. **Reveal is a truthful pop-in.** A squad entering vision has its
   current curve replicated clipped to `[now, now + horizon]` exactly as
   any other squad would be. The client therefore sees it at its true
   present position with no history and no future beyond the horizon. No
   synthetic curve is ever manufactured.
3. **Conceal leaves a stale ghost, announced explicitly.** When a squad
   leaves vision the server sends a conceal event; the client keeps its
   last-known curve and composition, marked stale, and stops treating it
   as live. It receives no further updates until revealed again, at which
   point the resend replaces the ghost wholesale.

**Rationale:** Part 1 is a cost decision. The obvious implementation —
for each player, for each squad, is any of my squads within range — is
~50,000 distance tests per player per tick at D-018's counts, so about a
million per tick across 20 players, against a 100 ms budget that has to
cover the simulation as well. Stamping coverage per player and looking up
per squad replaces that with tens of thousands of cheap operations, and it
is also the structure that terrain-occluded LOS would later extend rather
than replace.

Part 2 falls out of D-003 already being mandatory: clipping to the horizon
is what a reveal *is*, so pop-in requires no new machinery, and it cannot
leak — the keyframes describing where the squad has been were never in the
packet. A synthetic catch-up curve was tempting for smoothness and is
rejected below.

Part 3's explicit conceal event is not a convenience. Without it the
client cannot distinguish "this squad is out of vision" from "its update
is late", and D-006's composition hash then compares different sets on the
two sides: the server hashes what a client can see, while a client
carrying ghosts hashes more than that. The desync check would fire
constantly on a system working exactly as designed — and a check that
cries wolf gets muted, which is the failure mode `NetProtocol.
composition_hash` was written to avoid. Announcing conceal keeps the
hashed set agreed by construction and makes the ghost a deliberate,
inspectable state instead of an inference from silence.

**Rejected alternatives:** *Synthetic catch-up curve on reveal* (rejected
— it draws motion that never happened, and worse, it leaks: a unit
sliding in from its last-known position tells the player it moved while
unseen, which is exactly the class of information D-003's clipping
exists to withhold). *Hard removal on conceal* (rejected — simplest and
genuinely tempting for testability, but it discards the tactical memory
the genre is built on, and D-019's Total War half assumes the player
reasons about where an enemy was last seen). *Per-pair visibility tests*
(rejected on the cost math above). *Terrain-occluded LOS in M2* (deferred
— it needs a height field the sim does not yet carry, and radius-only
vision is enough to prove the gating).

**Consequences:** `SquadSim.visible_to()` becomes real and D-022's stub
note closes. The protocol gains a conceal event and must send squad
composition on reveal, not only at join — a client cannot derive soldiers
for a squad it was never described (D-006's protocol obligation). Client
state grows an explicit live/ghost distinction, and `composition_hash`
covers live squads only. Ghost curves are stale by design: anything that
samples them must know it is reading history, and the client's own
accounting must not count a ghost as a live squad.

**Revisit trigger:** Terrain-occluded or unit-blocking LOS, stealth
units, or shared vision between allied players. Any of those changes part
1's field computation; none of them change parts 2 or 3.

---

### D-024 · 2026-07-30 · Accepted — resolves Q7's shape
**Decision:** Combat resolves **at squad level, stochastically**, on the
server only.

- A squad engages an enemy squad when it is within its `attack_range`
  (converted to cells over the torus). Engagement is squad-vs-squad;
  soldiers do not pick individual targets.
- Damage output per round is a function of aggregate squad state —
  strength (`alive`), per-soldier `damage`, and `attack_interval` — and
  the roll is stochastic, drawn from a seeded RNG.
- Casualties are applied as **integer decrements to `alive`**, with
  fractional damage carried in a per-squad accumulator.
- Morale is a per-squad value that falls with casualties taken; a squad
  below its `rout_threshold` routs, flees as a squad, and ignores player
  orders until it rallies (D-019).
- Rounds are a whole multiple of the 10 Hz tick, per D-020's 100 ms
  minimum granularity.

**Rationale:** D-006's confirmation block already narrowed Q7 to answers
expressible within the purity clause, and this one satisfies it trivially
rather than delicately: nothing in combat reads or writes a soldier
position at all.

The decisive detail is that **`alive` is the only formation input a death
changes.** `Formation.slot_offset` takes `(shape, slot, alive, spacing)`,
so with `alive = N` the occupied slots are exactly `0..N-1` and the
formation restamps. D-006 clause 3 asks for casualty reassignment to be
deterministic and derived from the ordered death-event log — under this
model that is satisfied by construction and needs no per-soldier
identity, because *which* soldier died is not an input to anything. The
ordered log is simply the sequence of strength decrements, which is what
already replicates.

Squad-level state that combat does need — the damage accumulator, an
attack-interval accumulator, current morale — is per-*squad*, which
D-009's packed arrays are exactly for. D-006 forbids per-*soldier*
integration state; it says nothing against squads having state, and
squads already have position, destination, and strength.

It is also the only one of the three candidate shapes that stays cheap at
D-018's counts (aggregate arithmetic per engaged pair, not 40,000
per-soldier resolutions per round) and that LOD can later aggregate
without building a second combat model (D-012).

**Rejected alternatives:** *Deterministic per-soldier resolution,
read-only* (rejected — it satisfies D-006 clause 1 only in the strict
read-only form, costs ~40,000 position derivations per round at full
scale, and makes D-012's LOD aggregation a second implementation of
combat rather than a coarsening of this one. Per-soldier resolution that
*moves* soldiers as a result of combat is rejected outright: it trips
D-006's corrected revisit trigger). *Hybrid LOD-gated resolution*
(rejected for M2 — it pulls M5's LOD work forward and obliges proving two
models agree in aggregate; revisit at M5 if the squad-level model reads
as too coarse near the camera). *Continuous per-tick damage without
stochastic rolls* (rejected — deterministic attrition makes even fights
decide on stat ties alone, and D-019's morale model wants the variance).

**Consequences:** `UnitDef` gains combat/vision tuning fields, recorded
against D-010's schema log. The RNG must be seeded from map configuration
and advanced in a fixed order (squad id) so replays reproduce battles
(D-016) — a wall-clock or unordered RNG would silently break replay
forensics, which is the one tool for diagnosing a desync. Casualties make
squad composition change *during* a run for the first time, so
composition must replicate as events and the desync check finally runs
against moving state. Combat resolution is server-only: clients receive
outcomes and never roll, so there is no client-side RNG to diverge.

**Revisit trigger:** Combat that reads as too coarse at the camera —
specifically, a player being unable to tell *why* a fight was lost —
argues for the hybrid alternative at M5 alongside D-012. Any wish for
soldiers to physically react to being hit is a D-006 revisit first, not a
combat tuning change.

---

### D-023 · 2026-07-29 · Accepted
**Decision:** The authoritative simulation is driven by an **explicit
fixed-timestep accumulator owned by the sim**, not by Godot's
`_physics_process`. `physics/common/physics_ticks_per_second` in
`project.godot` is left at 10 only so the engine's own stepping doesn't
run wildly out of proportion to the sim; nothing reads it as the tick
rate. D-020 remains the single source of truth for 10 Hz.

**Rationale:** Three reasons, in order of weight. (1) D-009 keeps
simulation state in packed arrays outside the scene tree, so binding the
sim to a scene-tree callback is a coupling the design explicitly does not
need. (2) It makes the sim tickable without a `SceneTree` at all — unit
tests and replay playback drive `tick()` directly in a loop, which is
what lets the M1 suite test the simulation rather than only its parts.
(3) It keeps tick rate a property of the simulation (D-020) rather than a
project setting, so changing it can't happen by editing an engine config
field and silently invalidating D-018's budget math.

**Rejected alternatives:** `_physics_process` as the driver (rejected —
couples sim to the scene tree and to an engine setting, and makes
headless replay/test stepping awkward); `_process` with variable delta
(rejected outright — a variable-rate authoritative sim is not
reproducible, which breaks replays under D-016).

**Consequences:** The server node calls into the sim from `_process` with
an accumulator, consuming whole ticks and carrying the remainder. Tests
call `tick()` directly. `project.godot`'s physics tick setting is now
decorative with respect to the sim — noted in that file so nobody
"fixes" it into load-bearing status.

**Revisit trigger:** None currently.

---

### D-022 · 2026-07-29 · Accepted
**Decision:** M1's exit criteria, written down. D-015 named the milestone
ladder but deferred per-milestone exit criteria to "the 2026-07-28
planning session," which is not in the repo — so "M1 complete" was not a
checkable claim. These are derived from the already-accepted decisions
rather than newly invented, and each criterion names the decision it
discharges.

M1 ("movement + netcode proof") is complete when all of the following
hold and `just test-unit` is green:

1. **Torus is a type, not a convention** (D-008). A wrap-aware hex
   coordinate type exists; neighbor, distance, and interpolation all go
   through it. GUT tests cover seam-crossing cases explicitly — D-008
   requires this from M1 onward.
2. **Flow-field pathfinding** (D-007) computes a field per squad
   destination over the torus, CPU-side only, and a squad on the far side
   of a seam takes the short way around.
3. **Curve-based sync** (D-003) with all three properties demonstrated by
   test, not by inspection: an idle object costs zero bandwidth; curves
   are clipped to a visibility horizon so a client cannot read an enemy's
   future path (intent leakage); re-pathing goes through a budgeted
   scheduler rather than naive immediate replication.
4. **Derived soldier positions** (D-006) — a pure formation function
   drives `PrimitiveUnit`'s MultiMesh, with tests proving purity (same
   inputs → same outputs, no carried state) and deterministic casualty
   restamp.
5. **10 Hz authoritative sim** (D-020, D-009) with squad state in packed
   arrays outside the scene tree, and per-squad update cost measurable —
   D-012 requires the cost be measurable and swappable from M1 even
   though LOD isn't built until M5.
6. **Replay capture** (D-016): the curve log lands in `artifacts/` in a
   replayable format.
7. **Every M1-gated recipe is real**: `run-server`, `run-client`,
   `test-load`, `gen-terrain-preview` no longer exit with "NOT
   IMPLEMENTED UNTIL M1", and `just test-load N DURATION` runs clean.

**Explicitly NOT in M1** (so scope creep is visible if it happens):
combat resolution of any kind (Q7, M2), fog of war (D-004, M2), economy
or production, terrain generation beyond what `gen-terrain-preview`
needs to exercise chunking (D-017), and any LOD (D-012, M5).

**Rationale:** The project's workflow depends on decisions being written
down (CLAUDE.md). An unwritten definition of done for the milestone that
proves the whole architecture is the highest-leverage instance of that
gap. Writing the criteria as discharges of existing decisions also
surfaces whether the decisions actually cover M1 — they do, with no gaps
found while deriving this.

**Rejected alternatives:** Treating M1 as done when "movement works
visually" (rejected — that would pass without the three D-003 properties,
which are the entire point of the netcode proof). Reconstructing the
original planning session's criteria (rejected — not recoverable from the
repo; deriving from accepted decisions is both possible and more
authoritative).

**Consequences:** `CLAUDE.md`'s pointer to "M1's exit criteria in
`game_design_decisions.md` section 2" was wrong — section 2 is Open
Questions. Updated to point here.

**Revisit trigger:** If M2/M3 turn out to need something M1 was assumed
to have proven, add it here rather than quietly widening the milestone.

**M1 was declared complete 2026-07-29, then audited and found incomplete
the same day.** See the audit block after the criteria list. The
completion notes below are accurate about what was built; they were
wrong that it was done.

**M1 complete (revised) 2026-07-29.** All seven criteria met after the
audit fixes; `just test-unit` is green at 141 tests / 10 scripts, and
`just test-load 4 12` runs clean end to end. Criterion by criterion:

1. `torus_space.gd` — wrap enforced by every method normalising its own
   inputs, so a call site that forgets to wrap cannot get a different
   answer than one that remembers. Seam cases are tested exhaustively
   (every cell pair for distance symmetry and the wrapped bound).
2. `flow_field.gd` — BFS from the destination through
   `TorusSpace.neighbor_index`, one field per destination shared by all
   squads heading there. Verified as exactly the analytic wrapped hex
   distance at every cell, which is the check a non-wrapping expansion
   fails.
3. `state_curve.gd` + `curve_replicator.gd` — all three D-003 properties
   proven by test: 500 idle objects cost literally zero bytes; a client
   decoding the raw wire bytes cannot recover an enemy position 10s
   ahead; a 1,000-squad simultaneous re-path stays inside the byte
   budget and drains without starvation.
4. `formation.gd` — all-static, no instance state. Purity is tested by
   evaluation order, by time-travel (sample late, then early, then late
   again), and by two independent evaluators standing in for client and
   server. Cosmetic offsets live in a separate file (`cosmetic_offset.gd`)
   so clause 2's one-way boundary is structural rather than a comment.
5. `squad_sim.gd` — packed arrays, no Nodes, explicit 10 Hz tick
   (D-023). **Measured 1.5–2.7 µs per squad-update** at 48 squads against
   D-020's ~50 µs budget — a few percent of budget, which is direct
   evidence for D-021's judgement that GDScript would fit. The figure
   varies run to run with host load; treat the order of magnitude as the
   result, not the third digit.

   **The figure is only comparable at equal squad counts.** It is total
   tick time over (ticks × squads), so per-tick fixed overhead is charged
   to the per-squad number and inflates it when squads are few — a real
   play session at 12 squads measured ~3.9 µs where 48 squads measured
   ~2 µs on identical code. Quote the squad count alongside it, or a
   smaller test will look like a regression. The bias runs in the safe
   direction for D-018's extrapolation: it overstates per-squad cost at
   low counts, so real headroom at ~1,000 squads is better, not worse.
6. `replay_log.gd` — the curve log, byte-identical to the wire format.
   `just replay-info` reads a real load-test replay back and
   reconstructs all 48 squads.
7. All recipes real; `run-client`, `gen-terrain-preview` and
   `replay-info` added.

**Defects found and fixed while building M1**, recorded because each was
silent rather than loud:

- `StateCurve.clipped()` dropped the keyframe sitting exactly on the
  window start — the common case, since the sim emits keyframes on the
  same tick boundary the replicator clips at.
- `just test-load` reported "clean" for a run in which every bot exited
  non-zero. Grepping for the absence of bad news cannot distinguish
  "nothing went wrong" from "nothing happened"; it now also checks exit
  status and an explicit verdict.
- `docker compose` `depends_on: server` under `run --rm` left a running
  server container behind after every bot run — a stray-container leak
  directly against D-014.
- `NetProtocol.decode_welcome` appended to `out["squads"]`, and
  `PackedInt32Array` is a value type in GDScript, so it appended to a
  copy. Clients silently believed they owned no squads.
- Terrain noise was sampled at ~1 feature per cell, producing per-cell
  static that still passed every aggregate check (plausible water
  fraction, plausible biome spread) while having no landmasses at all.
- Bot teardown ran twice (once from the run loop, once from
  `_finalize`), calling `peer_disconnect_now` on a peer whose host was
  already destroyed. Three ERROR lines per successful run.
- The container lacked `libfontconfig1`, so Godot logged ten fontconfig
  ERRORs on every invocation. Harmless individually, but a log where
  routine ERRORs are normal is a log where a real one goes unnoticed —
  and `test-load`'s scan reads exactly those logs. Both logs are now
  clean at zero ERROR lines on a passing run, which is what makes the
  scan worth anything.

**Deliberately still open, not silently assumed:** fog of war (D-004's
reveal semantics), combat (Q7), casualties (M1 has no combat, so
`alive` is only ever the full squad size), and per-squad selection in
the client (M3 UI work). Replication uses reliable ENet delivery
throughout; unreliable-with-resend is a refinement M4 can measure.

**Known stub:** `SquadSim.visible_to()` returns every squad. That is
correct for M1 — fog is D-004/M2 — but it means the replicator's
per-client gating is exercised only by unit tests and never by the
running system. Recorded here so the criterion above does not read as
more proven than it is.

**Stub closed, 2026-07-30 (M2).** `SquadSim.visible_to()` is real now:
it returns the player's own squads plus any other squad sitting in a
cell the player's `Vision` field currently covers (`vision.gd`, D-025
part 1) — an O(1) lookup per squad against a per-player coverage stamped
once per recompute, never a per-pair scan. `server.gd`'s `_replicate()`
feeds this into `CurveReplicator.collect_for_client()` every tick, so the
replicator's per-client gating is now exercised by the running system,
not only by unit tests, closing exactly the gap this note flagged.

---

### Audit of this entry, 2026-07-29 — and why it was needed

D-022 was written by the same agent, in the same session, that then built
the code against it. That is exactly the arrangement in which a
definition of done drifts to fit whatever was produced, so it was
re-examined rather than restated. It had drifted, in two specific ways,
and both let real bugs through:

**Criterion 4 asked for the wrong thing.** It required "tests proving
purity and client/server agreement". The tests proved agreement *given
identical inputs* — they passed `def.squad_size` to both sides — and
therefore could not notice that the live client fed `Formation` a
nominal 40-strong "line" while the server used 32-strong "loose". Every
soldier on every client was in the wrong place, and the suite was green.
The criterion should have demanded agreement **in the running system,
with the test taking its inputs from the wire**. See D-006's "necessary
but not sufficient" note.

**Criterion 7 could be satisfied vacuously.** "`test-load` runs clean"
was true while one of its three checks — a grep for the word `desync` —
matched nothing any code path ever printed. A check that cannot fail is
indistinguishable from one that passes. It hid the bug above through
every green run of M1.

Both are now closed. The protocol carries squad composition
(`S2C_SQUAD_INFO`), the server publishes a composition hash
(`S2C_STATE_HASH`) that clients check themselves against, and the bot
verdict fails if that verification did not *happen*, not merely if it
did not complain.

**A further live bug the new check caught on its first run:** squad
composition was sent only to the joining client, so every
already-connected client received curves for the newcomer's squads
without ever being told what they were. The desync check flagged it
immediately — bot 0 knew 12 squads, bot 1 knew 24, bot 2 knew 36 — which
is the clearest possible demonstration that the previous check had been
dead rather than passing.

**Standing rule this produces:** every check added to a test recipe must
be *observed to fail* before it is trusted. Both new checks were
verified by deliberate perturbation, and the log scan itself was fixed
after it failed a good run by matching its own success line ("0
desyncs") — a check that fires on its own good news is no better than
one that never fires.

**Also fixed in the audit:** the sim now rejects a
`curve_lookahead_seconds` that does not exceed the replicator's
`horizon_seconds` (previously a comment, enforced by nothing), and the
server counts and reports simulation ticks discarded by its catch-up
bound instead of silently falling behind wall-clock.

**The GUI client gap is closed too — see D-014's 2026-07-29 amendment.**
`just test-client` renders the real client against a real server using a
software rasteriser, so criterion 4 is now verified visually and not
merely numerically. That distinction earned its keep immediately: the
first frame ever rendered showed **no soldiers at all**, while every
numeric assertion passed — 12 squads drawn, 384 soldiers derived, zero
desyncs. `ClientState` was calling `Formation.soldier_transforms` with no
terrain sampler, so every soldier derived at y=0 and rendered *inside*
the terrain.

That is a D-006 gap, not a cosmetic one: "terrain sample" is the fourth
element of clause 1's input tuple, and it was simply never supplied. It
is now, from the same `TerrainGen` instance that builds the mesh, so the
ground a soldier stands on is the ground that was drawn. When the server
begins deriving soldier positions for combat in M2 it must use an
identical sampler, or the two sides will disagree about who is standing
where.

---

### D-021 · 2026-07-29 · Accepted
**Decision:** **No C# in the shipping build.** GDScript for all gameplay
and simulation code. Where profiling shows a specific kernel exceeding
budget, the escape hatch is **GDExtension (C++/Rust) scoped to that
kernel** — not a project-wide .NET conversion. This narrows D-009's
looser "C# only where profiling shows a specific need" clause; see the
note appended to D-009.

**Rationale:** Q6 framed this as a question about export matrix and
platform support. For this project it largely isn't: shipping is Steam
desktop (D-015 → M7), Godot's .NET builds export to Windows/Linux/macOS,
and there is no web target — the usual platform argument against C# does
not apply here. Dedicated servers (Q3, open) are Linux either way. The
decision therefore rests on toolchain cost and reversibility.

*Toolchain cost is permanent.* The current image is debian-slim plus one
Godot zip. .NET means the Mono/.NET Godot artifact, the .NET SDK in the
image, a NuGet restore, and a compile step gating `test-unit` on top of
the headless-import step D-015 already requires. That is paid on every
container operation from M1 onward, against D-014's explicit premise of
a small footprint and clean teardown.

*Reversibility is asymmetric.* Deciding no now and reversing at M4 costs
the container/export rework — which is the same work whether done now or
then, since existing GDScript keeps working alongside a later `.csproj`.
Deciding yes now pays the toolchain tax continuously across M1–M3 for a
bottleneck that is speculative.

*D-006's confirmation is what makes this tenable.* The strongest argument
for C# is that D-009's packed-array-outside-the-scene-tree design is
ergonomic in C# (structs, spans, generics) and ugly in GDScript (parallel
`PackedFloat32Array`s with hand-rolled index math). That argument was
substantially weakened on 2026-07-28: because soldier positions are
derived rather than stored, the hot data set is ~1,000 squads of state,
not ~40,000 soldiers — a 40x reduction. Manual index math over a thousand
entities is unpleasant but tractable. **Had D-006 been rejected, this
entry would likely have gone the other way.**

**Rejected alternatives:** C# permitted project-wide from the start
(rejected — continuous cost for speculative benefit; the hiring-pool and
static-typing arguments are real but don't outweigh it at this stage).
Leaving D-009's vague "C# if profiling shows a need" as the answer
(rejected — that phrasing can't be acted on when sizing the container or
export matrix, which is precisely why Q6 demanded a yes/no). GPU compute
shader as the general escape hatch for the flow-field solver (rejected as
*unsafe*: the authoritative server is headless and, depending on Q3, may
be CPU-only in a cloud VM — GPU acceleration is available to the client
renderer, not to the server-side solver).

**Explicitly not a reason:** .NET GC pauses. At D-020's 100 ms tick,
gen0 collections are noise and a gen2 pause is poolable. Recorded here so
the argument doesn't get re-raised as though it were load-bearing.

**Consequences:** Container and export stay single-toolchain. D-009's C#
clause is narrowed (note appended there); `CLAUDE.md`'s Conventions
section updated to match. Accept the ergonomic cost of parallel packed
arrays in GDScript for D-009's simulation state. Note that GDExtension is
deferred cost, not free: it brings its own native build matrix
(`.dll`/`.so`/`.dylib` per target), so the escape hatch should be reached
for once, deliberately, on measured evidence.

**Revisit trigger:** M4 profiling identifies a kernel exceeding budget
that GDScript-level optimization cannot close. The flow-field solver
(D-007) under D-003's invalidation-storm conditions is the prime
candidate — a wrap-aware pass over 10,000+ cells (Q8) recomputed for many
squads at once. Reverse to GDExtension for that kernel first; revisit
project-wide C# only if several kernels qualify.

---

### D-020 · 2026-07-28 · Accepted, per-LOD variation Open
**Decision:** Server simulation tick rate is **10 Hz** (100 ms). This is
the rate at which authoritative game state advances. It is explicitly
*not* the same number as either the curve keyframe emission rate (D-003)
or the flow-field recompute rate (D-007), both of which are lower and
independently tunable.

**Rationale:** 10 Hz was already load-bearing in D-018's accepted math
("1,000 squads at a 10 Hz tick is 10,000 squad-updates/second") while
remaining formally undecided — this entry closes that gap rather than
introducing a new number. The rate is defensible on its own terms: at
full scale it leaves ~50 µs per squad-update to consume half of one core,
which is a workable GDScript budget under D-009's packed-array design.

Crucially, D-003 decouples tick rate from *visual* smoothness. Under
snapshot replication 10 Hz would look choppy; under curve-based sync
clients interpolate continuously along a received curve, so tick rate
governs decision and combat-resolution latency, not motion fidelity. The
cost that remains is up to 100 ms of command quantization on top of
network RTT — well inside genre norms, where classic lockstep RTS
deliberately ran 200–500 ms command latency.

**Rejected alternatives:** 20–30 Hz (rejected — doubles or triples the
squad-update budget for latency the genre doesn't need and that D-003
already hides visually); 5 Hz (rejected — halves the cost but pushes
worst-case command quantization to 200 ms and coarsens combat resolution
to 200 ms rounds, which starts to constrain Q7's design space).

**Consequences:** Per-squad update cost should be measured against a
100 ms tick budget from M1 onward, per D-012's "keep it measurable and
swappable." Combat resolution (Q7) has a 100 ms minimum round
granularity. Do not conflate this number with network send rate — an
idle squad still costs zero bandwidth per D-003 regardless of tick rate,
and that property must survive M1's implementation.

**Revisit trigger:** M1/M4 profiling showing squad-update cost exceeding
the 100 ms budget at D-018's counts — per D-018's own revisit trigger,
tick rate is the dial to consider before the architecture. Whether the
tick rate itself varies by LOD tier remains **open** and is deferred to
M5 with the rest of D-012.

---

### D-018 · 2026-07-28 · Accepted
**Decision:** Full-scale target is 20 players × 2,000 individual soldiers
each (40,000 soldiers total), organized into ~50 squads/player (~1,000
squads total at full scale), implying an average squad size of ~40
soldiers.

**Rationale:** Dave's explicit call, replacing the ambiguous "500 units"
figure in the original brief (see former Q1, now resolved). This reading
(soldiers, not Total-War-style multi-soldier "units") keeps the
squad-atomic architecture's math tractable: 1,000 squads at a 10 Hz tick
is 10,000 squad-updates/second, roughly 4x the number modeled in the
original MVP planning pass but still within GDScript's budget assuming
D-006 holds.

**Rejected alternatives:** 500 soldiers/player (original brief, too
small to be interesting per Dave); 500 Total-War-style units/player
(~20,000 soldiers/player, ~400,000 total — an order of magnitude beyond
what's viable for this project's team size and hardware).

**Consequences:** Every downstream budget in `CLAUDE.md` and this file
(bandwidth, tick cost, MultiMesh instance counts, load-test bot shape)
should be sized against 1,000 squads / 40,000 soldiers at full scale, not
the original 250/10,000. MVP (M3) squad count per player stays modest
(~12-15) — full-scale squad density is a v1.0 target, not an MVP one.

**Revisit trigger:** If M1/M4 profiling shows squad-update cost exceeding
budget at this count, revisit either the squad-count target or the tick
rate before touching the architecture.

---

### D-019 · 2026-07-28 · Accepted
**Decision:** The "Rome Total War" half of the hybrid means **formations
and morale/routing only** — units fight and break in formation, morale
determines when a squad routs. No separate turn-based or persistent
campaign layer wrapping the RTS battles.

**Rationale:** Dave's explicit call (former Q2, now resolved). This
confirms squads are the right atomic simulation unit for a reason beyond
performance: formations and morale are inherently squad-level concepts,
not per-soldier ones.

**Rejected alternatives:** Campaign layer wrapping battles (Total War's
actual structure) — rejected as out of scope entirely, not just deferred;
"Total War" as aesthetic/scale reference only, no formal
formation/morale system — rejected, Dave wants the mechanics, not just
the vibe.

**Consequences:** Combat model (former Q7, still open) must define
formation shapes per squad, a morale stat and rout trigger/threshold, and
how routing interacts with flow-field movement (a routed squad presumably
gets a new, player-uncontrolled flow-field target). This also firms up
`unit_def.gd`'s schema: it needs formation-shape and morale-stat fields
from the start, not bolted on later.

**Revisit trigger:** None — this is a firm scope boundary, not a
provisional call.

---

### D-006 · 2026-07-28 · Accepted (confirmed 2026-07-28 — see confirmation block below)
**Decision:** Individual soldier positions are a pure client-side
function of (squad curve, formation shape, slot index, terrain sample)
and are never networked. Only squads are networked entities. Combat
outcomes (damage, death, routing) replicate as sparse reliable events,
not continuous per-soldier state.

**Rationale:** This is the keystone that makes D-018's 1,000-squad
full-scale target tractable at all — it's what keeps the networking and
simulation cost at "squads" (~1,000) rather than "soldiers" (~40,000), a
40x difference. It also composes cleanly with D-019: formation shape is
exactly the function that would derive soldier slot positions.

**Rejected alternatives:** Per-soldier authoritative networked
positions — rejected provisionally, as it multiplies the netcode budget
by ~40x and wasn't shown to be necessary for anything in scope.

**Consequences:** Combat resolution cannot depend on true per-soldier
positions being known to the server at high precision — it has to work
off squad-level state plus a formation model. This needs explicit
confirmation before M1's flow-field/curve-sync proof is built, because
M1's exit criteria assume it.

**Revisit trigger:** If the combat model (informed by D-019) turns out to
require server-authoritative per-soldier positions — e.g., for precise
morale/rout triggers based on individual soldier deaths in specific
formation slots — revisit before M2.

**Confirmed 2026-07-28.** Promoted Provisional → Accepted, with the scope
sharpened. The original entry bundled two separable claims: that soldier
positions are never *networked* (a bandwidth claim) and that they are
never *server-authoritative state* (a simulation-cost claim). Only the
first is load-bearing, and it does not depend on the second — if a
soldier's position is a pure function of replicated squad state, the
server may compute it whenever combat needs it and still send nothing.
Server and client agree by construction rather than by synchronization.

Three clauses, now binding:

1. **Purity.** A soldier's position is a pure function of (squad curve,
   formation shape, slot index, terrain sample). No per-soldier
   integration state — no velocity, no accumulated offset, no history
   carried across ticks.
2. **Cosmetic offsets are one-way.** Client-side visual offsets (idle
   sway, footfall jitter, terrain settling) are permitted and are never
   read back by simulation. This is where visual life comes from without
   touching the keystone.
3. **Casualty slot reassignment is deterministic**, derived from the
   ordered death-event log — which is already replicated as sparse
   reliable events, so reassignment stays inside the purity boundary.
   The formation restamps; soldiers do not walk to fill a dead man's
   slot.

**Clause 1 is necessary but not sufficient — added 2026-07-29.** Purity
guarantees client and server agree *given identical inputs*. It says
nothing about whether the system actually hands them identical inputs,
and that turned out to be the gap that mattered.

M1 shipped with the server spawning the roster's default unit (32-strong
archers in "loose" order) while every client assumed a nominal 40-strong
"line". Because `Formation.slot_offset` takes `alive` as an input, this
did not merely draw eight phantom soldiers — it put *every* soldier
somewhere the server had not. The formation function was flawlessly pure
throughout. The tests proved that purity and passed, because they handed
both sides `def.squad_size` themselves.

So: **supplying both sides identical inputs is a protocol obligation**,
and it belongs to whatever message carries squad composition (see
`NetProtocol.encode_squad_info`). A test that supplies the inputs itself
verifies the function, not the system. Any future test claiming
client/server agreement must take its inputs from the wire.

**Corrected revisit trigger** (replaces the original above, which was
miswritten): the trigger is *not* "combat needs server-authoritative
per-soldier positions" — under clause 1 that is free. The trigger is
**emergent per-soldier movement**: local avoidance, collision push-back,
soldiers physically jostling, neighbors pathing into a vacated slot. Any
of those gives a soldier its own integration state and breaks clause 1,
at which point the only options are networking ~40,000 entities or
accepting divergence. Revisit before M2 if the combat model wants one.

**Consequence for Q7.** This constrains the still-open combat model
rather than waiting on it. Q7 must resolve to something expressible
within clause 1: squad-level stochastic resolution satisfies it
trivially; deterministic per-soldier resolution satisfies it only if
resolution *reads* derived positions without perturbing them; per-soldier
resolution that physically moves soldiers as a result of combat does not
satisfy it and trips the corrected trigger above.

---

### D-001 · 2026-07-28 · Accepted
**Decision:** Godot 4.7.1 (stable), pinned via `.godot-version`.

**Rationale:** Latest stable release as of 2026-07-28 (released
2026-07-14). Chosen for plain-text asset formats (`.tscn`/`.tres`) that
make the project directly editable by Claude Code.

**Rejected alternatives:** Godot 4.6.3 (prior stable branch) — no
compelling reason to pin behind latest stable for a greenfield project.

**Consequences:** Container image and portable native binary must both
resolve to this exact version. Bump this entry (don't silently update)
if a newer stable release becomes worth adopting.

**Revisit trigger:** A newer stable release ships with a fix or feature
this project specifically needs (e.g. `MultiMesh` improvements relevant
to D-009).

---

### D-002 · 2026-07-28 · Accepted
**Decision:** Client-server, authoritative server. Not lockstep.

**Rationale:** Lockstep desync debugging cost, 20-player join/rejoin
handling, and cheat resistance all favor authoritative server + client
interpolation over lockstep, despite lockstep being the historical RTS
default.

**Rejected alternatives:** Lockstep simulation (classic RTS netcode).

**Consequences:** Server needs enough CPU to simulate the full match
(see former Q3, still open — server hosting model). Clients send input,
receive curve-based state (D-003), interpolate locally.

**Revisit trigger:** None currently.

---

### D-003 · 2026-07-28 · Accepted
**Decision:** Object state (position, build progress, etc.) syncs as
keyframed curves, not per-tick snapshots. Curves are mandatorily clipped
to each client's visibility horizon and a bounded time window before
transmission.

**Rationale:** Near-zero bandwidth for idle objects. The clipping
requirement prevents two specific failure modes: intent leakage (a raw
curve reveals an enemy squad's future path before it happens) and
unbounded lookahead cost.

**Rejected alternatives:** Per-tick snapshot replication (simpler, but
scales linearly with object count and tick rate — incompatible with the
zero-cost-when-idle goal).

**Consequences:** Curve invalidation (re-pathing, especially many squads
at once, e.g. a large engagement) is a bandwidth spike risk and needs a
budgeted/prioritized update scheduler, not naive immediate replication.
This should be measured explicitly in M1's exit criteria.

**Revisit trigger:** If M1 profiling shows invalidation-storm bandwidth
exceeding budget, revisit the scheduler design (not the curve-based
approach itself).

---

### D-004 · 2026-07-28 · Accepted (semantics closed 2026-07-30 by D-025)
**Decision:** Fog of war is implemented as curve gating on top of D-003
— a client simply doesn't receive curves for objects outside its
vision — not a separate data-hiding system.

**Rationale:** Avoids building and maintaining two parallel
visibility-gating mechanisms.

**Rejected alternatives:** Separate fog-of-war system layered on top of
full replication with client-side hiding (rejected — leaks true state to
a modified client, defeats the purpose of fog of war).

**Consequences:** Reveal/conceal semantics are not yet decided: does a
unit entering vision pop in at its true position, receive a short
synthetic catch-up curve, or does the client keep a stale "ghost" at
last-known position after it leaves vision? All three are legitimate;
needs an explicit pick before M2 (fog of war milestone).

**Revisit trigger:** Pick reveal/conceal semantics before M2 begins;
this entry stays Provisional until then.

**Semantics picked 2026-07-30 — see D-025.** True-position pop-in on
reveal, stale announced ghost on conceal, and vision computed as a
per-player field rather than per-pair tests. This entry is no longer
Provisional. The one part of D-025 that is not merely a choice among the
three options listed above: conceal has to be an **explicit event**, or
the composition hash compares different sets on the two sides and the
desync check fires on a healthy system.

---

### D-005 · 2026-07-28 · Accepted
**Decision:** Squads, not individual soldiers, are the atomic unit for
movement, pathfinding, production, and networking.

**Rationale:** Matches D-019's formation/morale mechanics (which are
inherently squad-level) and is what makes D-018's full-scale target
tractable via D-006.

**Rejected alternatives:** Per-soldier pathfinding/production (rejected —
doesn't scale to 40,000 soldiers and fights D-019's formation model).

**Consequences:** Don't reintroduce per-unit pathfinding or per-unit
production queues anywhere in the codebase.

**Revisit trigger:** None currently.

---

### D-007 · 2026-07-28 · Accepted
**Decision:** Flow-field pathfinding, computed per squad destination, not
per-soldier A*.

**Rationale:** Well-trodden technique (Supreme Commander 2, Planetary
Annihilation) that composes with squad-atomic movement (D-005) and scales
far better than per-agent A* at this unit count.

**Rejected alternatives:** Per-soldier A* (rejected — doesn't scale;
also redundant given D-006's derived soldier positions).

**Consequences:** None beyond standard flow-field implementation cost.

**Revisit trigger:** None currently.

---

### D-008 · 2026-07-28 · Accepted
**Decision:** Wrapped hex grid on a torus, using axial coordinates on a
parallelogram domain with row-parity constraints on map dimensions.
Wrap-awareness is enforced via a `HexCoord`/`TorusSpace` type rather than
left as a convention every call site has to remember.

**Rationale:** A true geodesic sphere is unnecessary complexity for the
stated design; a naive offset-coordinate rectangular grid does not wrap
cleanly without careful row-parity handling. Making wrap a type-level
concern prevents the "twentieth call site forgets ghost-copy distance"
class of bug.

**Rejected alternatives:** True geodesic sphere (rejected — much more
complex, not needed); offset-coordinate grid with wrap handled by
convention (rejected — proven bug-prone pattern, error-prone at scale).

**Consequences:** Every distance/neighbor/noise calculation
(pathfinding, vision, minimap, camera, drag-select, formation math, AI
targeting, terrain noise) must go through the wrap-aware type. Seam-
crossing cases must be in GUT tests from M1 onward.

**Revisit trigger:** None currently.

---

### D-009 · 2026-07-28 · Accepted
**Decision:** GDScript for gameplay logic at squad granularity. Rendering
via `MultiMesh`, with simulation state kept in packed arrays outside the
Godot scene tree — not one `Node` per soldier or per squad. C# only where
profiling shows a specific need.

**Rationale:** Godot's `Node`/scene-tree model is not designed for tens
of thousands of dynamic actors; the idiomatic "one scene instance per
unit" approach fails well before D-018's target. `MultiMesh` + packed
arrays is the path that actually scales, but it cuts against Godot's
default idiom and needs to be an explicit decision so early
implementation doesn't default to per-soldier scene instances.

**Rejected alternatives:** One `Node`/scene instance per soldier
(rejected — doesn't scale); one `Node` per squad (reconsider only if
squad count, not soldier count, turns out to be the bottleneck).

**Consequences:** Unit rendering code should be written against
`MultiMesh` from `primitive_unit.gd` onward, not retrofitted later.

**Revisit trigger:** If profiling shows packed-array simulation state is
itself the bottleneck (unlikely before M4).

**Narrowed 2026-07-29 by D-021.** The "C# only where profiling shows a
specific need" clause above is superseded: C# is **not** permitted in the
shipping build at all. The escape hatch for a kernel that exceeds budget
is GDExtension (C++/Rust) scoped to that kernel. The rest of this entry —
GDScript at squad granularity, `MultiMesh` rendering, packed arrays
outside the scene tree — stands unchanged. See D-021 for the reasoning,
including why D-006's confirmation is what makes GDScript tenable for the
packed-array design.

---

### D-010 · 2026-07-28 · Accepted
**Decision:** Unit stats live in `/units/*.tres` against the `UnitDef`
schema (`unit_def.gd`). Schema changes are versioned and recorded here,
not just in the code.

**Rationale:** Data-driven units are what makes the project directly
editable via Claude Code rather than requiring the Godot editor GUI, per
`CLAUDE.md`'s core premise. `UnitDef` now needs formation-shape and
morale-stat fields per D-019 from the start.

**Rejected alternatives:** Hardcoded per-unit-type script subclasses
(rejected — defeats the data-driven goal).

**Consequences:** New units are added by adding a `.tres` file, not by
writing new unit classes. Squad size (~40 soldiers per D-018) is a
`UnitDef` field, not a global constant, so it can vary per unit type if
needed later.

**Revisit trigger:** None currently.

**Schema log** (this entry requires schema changes be recorded here, not
just in code):

- **2026-07-29, M1 — added `formation_spacing: float = 1.0`.** Formation
  geometry (D-006/D-019) needs a per-unit centre-to-centre spacing;
  cavalry and skirmishers do not occupy the footprint of line infantry.
  Existing `.tres` files pick up the default, so this is backward
  compatible.

- **2026-07-30, M2 — added `vision_range: float = 12.0`,
  `morale_recovery_per_second: float = 2.0`, `rout_rally_margin: float =
  15.0`, `morale_loss_per_casualty: float = 4.0`, `damage_variance: float
  = 0.25`.** D-024's combat model and D-019's morale/routing need these
  as per-unit tuning rather than script constants; `vision_range` is
  D-025's vision-field radius, added here (combat's file) rather than by
  the fog worker so `unit_def.gd` only gets one schema-touching editor
  per unit. All five are additive with defaults; existing `.tres` files
  pick them up unchanged.

- **2026-07-30, M3 — added `armour_class: String = "infantry"` and
  `bonus_vs: Dictionary = {}`.** D-032's counters. `armour_class` is what
  a unit *is* for targeting; `bonus_vs` maps an opponent's armour class
  to a damage multiplier, so the counter table is data and adding a
  counter never means editing `combat.gd`. A missing entry means 1.0, so
  a generalist unit needs no special-casing and both existing `.tres`
  files stayed valid. Shipped alongside two new units — `spearmen.tres`
  and `cavalry.tres` — completing D-015's 3-4 unit cut line with a real
  triangle: spears counter cavalry, cavalry counter missile, missile
  counters infantry.

---

### D-011 · 2026-07-28 · Accepted
**Decision:** Mesh generation stays at the primitive tier (capsules,
boxes, cylinders composed from `UnitDef` data) through M3. Modular/
parametric (tier 2) and Blender/`bpy` final-fidelity (tier 3) are
unscheduled.

**Rationale:** Zero art dependency lets the architecture and gameplay
loop get validated before any art investment. Matches `CLAUDE.md`'s
existing tiering.

**Rejected alternatives:** Jumping to higher mesh fidelity early
(rejected — art investment before the architecture is proven is the
highest-waste failure mode for a project this size).

**Consequences:** `primitive_unit.gd` is the only mesh-generation code
needed through M3.

**Revisit trigger:** Revisit once M3 is complete and playtesting
suggests visual fidelity is limiting engagement, or once tiers 2/3 are
explicitly prioritized.

---

### D-012 · 2026-07-28 · Provisional
**Decision:** LOD is deferred to M5, implemented only for the tiers M4's
profiling shows are actually necessary. When built: **simulation** LOD is
keyed to server-computed game-state salience (in combat / near enemy /
near contested objective) and is identical for all observers — never
keyed to any individual client's camera. **Render** LOD may be keyed to
camera freely.

**Rationale:** Building LOD before M4 means building a complex,
fairness-sensitive system against guessed numbers instead of measured
ones. Keying simulation fidelity to an individual client's camera would
make combat outcomes depend on spectator behavior — a competitive-
fairness bug, not just a technical one. `CLAUDE.md`'s "LOD is planned,
not a fallback" is about keeping per-squad update cost measurable and
swappable from the start, not a mandate to build LOD first.

**Rejected alternatives:** Camera-keyed simulation LOD (rejected —
fairness bug); building full LOD before M4 (rejected — no measured data
to size it against).

**Consequences:** Per-squad update cost should be kept measurable and
swappable from M1 onward even though LOD itself isn't built until M5.

**Revisit trigger:** M4's profiling data determines which LOD tiers (if
any) are actually needed.

---

### D-013 · 2026-07-28 · Accepted
**Decision:** Global time dilation (PA-style slowdown) is an emergency
safety valve only, with a written trigger threshold once defined — never
the primary mechanism for handling scale.

**Rationale:** Matches `CLAUDE.md`'s existing non-negotiable. LOD (D-012)
and curve-based sync (D-003) are the primary scale mechanisms; time
dilation is a last-resort fallback for when those aren't enough in a
specific match.

**Rejected alternatives:** Time dilation as a routine scale-management
tool (rejected — degrades the play experience broadly instead of
targeting the actual cost).

**Consequences:** None yet — unscheduled until M5 or later.

**Revisit trigger:** Define the exact trigger threshold when this is
first implemented, not before.

---

### D-014 · 2026-07-28 · Accepted
**Decision:** Headless dev tooling (server, bots, GUT tests, terrain
preview) is containerized. The GUI Godot editor and the GUI game client
run natively via a portable, gitignored install — flagged as `CLAUDE.md`
exceptions, not eliminated. `EDOTMW_RUNTIME=native|docker` lets the
`justfile` recipes run against either backend, since WSL2 is currently
broken on the dev machine and Docker Desktop depends on it.

**Rationale:** Dave wants easy, complete teardown — no stray processes,
containers, or installed toolchains left on the machine. GPU-accelerated
GUI Godot in a container on Windows (via WSLg/X-forwarding) is slow and
fragile, and pointless given the dev machine's integrated Iris Xe GPU
anyway. The native-fallback runtime abstraction means M0 isn't blocked on
fixing WSL2.

**Rejected alternatives:** Containerizing the GUI client (rejected —
fragile, no GPU benefit on this hardware); requiring WSL2 fixed before
any dev work starts (rejected — unnecessarily blocks M0).

**Consequences:** `justfile` recipes are the stable interface; only the
backend invocation differs by `EDOTMW_RUNTIME`. Teardown for the native
path is `rm -rf tools/` (portable binaries) plus clearing
`%APPDATA%\Godot` if needed; for the docker path it's `just nuke`
(remove containers, image, `tools/`, `artifacts/`).

**Revisit trigger:** Once WSL2 is repaired and the docker path is
verified working, `EDOTMW_RUNTIME=docker` can become the default; native
stays as the fallback either way for the GUI pieces.

**Amended 2026-07-29 — automated GUI testing, without a GPU.** This entry
rejected containerising the GUI client, and that judgement stands *for
interactive development*: GPU passthrough into a container on this
hardware is fragile and buys nothing. `just run-client` is still native.

But the rejection was overly broad, and it left M1's client with no
automated verification at all — it had never rendered a frame anywhere.
The gap was never really about GPUs: **rendering does not require a GPU,
it requires a rasteriser.** Mesa's llvmpipe renders Godot's Compatibility
(OpenGL) backend entirely in software, under a virtual X server, in a
plain container. Verified here at OpenGL 4.5 core against Godot's 3.3
requirement.

So `just test-client` renders the real client scene against a real
server, screenshots it, and asserts on the result. Nothing is installed
on the host and no GPU is involved. Teardown is unchanged: the X server
dies with its container, and `just nuke` removes the image.

Software rendering is a feature here rather than a compromise — output
does not vary by driver vendor or version, so frames are comparable run
to run. What it deliberately does **not** cover is real-GPU appearance
and performance, which stay a human judgement made via `just run-client`.

Two traps this laid, both worth knowing:

1. The `gui` stage extends `base` and is therefore *last*, and Docker
   builds the last stage by default — so a bare `build: .` silently gave
   the **server** an X server and an OpenGL context instead of running it
   headless. Every headless service now pins `target: base` explicitly.
   Caught by the tightened log scan on its first run after the change.
2. Godot defaults to Forward+/Vulkan. The image ships software *OpenGL*,
   not software Vulkan, so the client hung at startup emitting no
   diagnostic whatsoever until `--rendering-method gl_compatibility` was
   passed.

**And it exposed a pre-existing hole in this entry's own guarantee.**
`docker compose down` removes what `compose up` created; it does **not**
reliably remove a still-running one-off `compose run` container, and
`--remove-orphans` does not either. A client-test container that hung at
startup survived a full `just nuke` and was still running half an hour
later — the exact stray-container failure this decision exists to
prevent, sitting undetected because nothing ever checked. `just down`
now also sweeps by `com.docker.compose.project=edotmw` label, which is
scoped to this project exactly as the pinned `-p edotmw` is and cannot
touch anything else. Verified: run `test-client`, then `nuke`, then
confirm zero containers and zero images remain.

The lesson generalises past Docker: **the teardown guarantee needs its
own check.** It was asserted in this entry from M0 onward and was, for
some paths, simply not true.

**Update 2026-07-28:** WSL2 repaired (firmware virtualization was
disabled — fixed in BIOS) and Docker Desktop installed. Docker path
verified end-to-end: `docker compose build server` succeeds (fetches
pinned Godot 4.7.1 inside the image per D-001), and
`docker compose run --rm bots -- --clients=3` runs `bot_client.gd`
through the full bind-mount + entrypoint chain correctly.
`docker compose down --remove-orphans` tears down cleanly. Trigger met
— `EDOTMW_RUNTIME` default switched to `docker` in the justfile; native
remains the fallback for the GUI editor/client (unaffected by this
change).

---

### D-015 · 2026-07-28 · Accepted (pending Dave's review of concrete M3 file output)
**Decision:** Milestone ladder M0 (skeleton) → M1 (movement + netcode
proof) → M2 (combat + fog) → M3 (launchable MVP) → M4 (scale-out
profiling) → M5 (LOD) → M6 (second civ) → M7 (Steam). M3's cut lines: 4
players, ~120-150 soldiers/player at ~12-15 squads/player (squad count
per player stays a small fraction of D-018's full-scale ~50/player — see
D-018 consequences), 1 civilization, fixed torus map, 3-4 unit types,
primitive meshes only, no simulation LOD, LAN/direct-IP only, no AI
opponent, replays included (near-free given D-003).

**Rationale:** Full derivation and per-milestone exit criteria are in the
2026-07-28 planning session (see project history / commit that adds
this file). Deliberately shrinks nearly every dial except squads/player,
since squad count is the axis the architecture is actually sensitive to.

**Rejected alternatives:** Scaling every dial down proportionally
(rejected — would hollow out the validation of the squad-atomic
architecture, the thing M1-M3 exist to prove).

**Consequences:** M0 deliverables (this commit and the files alongside
it) should make `CLAUDE.md` actually true: real `justfile` recipes,
real directory layout, this decision log, and container/native
scaffolding.

**Revisit trigger:** Re-derive squad/soldier counts if D-018 changes.

**Update 2026-07-28:** M0 exit criteria verified and met: `just
test-unit` runs GUT 9.6.1 headless via `docker compose run --rm test`
(2/2 smoke tests pass, including a `UnitDef` default-value check), and
`just nuke` confirmed to remove all containers/images plus
`tools/`/`artifacts/`/`.godot`/`.godot-container`, leaving the repo as
pure source. One operational note for M1: Godot's headless import step
(`godot --headless --path . --import`) must run before `gut_cmdln.gd`
can resolve GUT's and the project's own global `class_name`s (`UnitDef`,
`PrimitiveUnit`) — baked into the `test-unit` recipe now, keep this in
mind for any other headless recipe (`run-server`, `gen-terrain-preview`)
implemented in M1.

**Post-M0 review 2026-07-28.** A review pass over the M0 deliverables
found and fixed four real defects, all of which would have surfaced as
confusing failures during M1:

1. `bootstrap` only printed instructions, so the stated exit criterion
   ("fresh clone + bootstrap + `just test-unit` works") did not actually
   hold — and could not, since a fresh clone has no `just` to run
   `just bootstrap` with. Resolved by adding `bootstrap.ps1` (fetches
   pinned `just` into `tools/`) and making `just bootstrap` really fetch
   portable Godot for the native runtime.
2. Recipes invoked each other as a bare `just`, which is never on PATH
   (it lives in `tools/`). Broke `default` and every step of
   `test-load`. Now `{{just_executable()}}` — **and it must be quoted**:
   unquoted, bash eats the Windows path's backslashes and the command
   silently becomes `C:Usersdmaso...`. Worth remembering for any future
   recipe that interpolates a path on Windows.
3. `test-load` ran the bots in the foreground and only then slept, so
   `DURATION` measured nothing. Bots now run in the background for the
   requested duration, and teardown is trapped on `EXIT INT TERM` so an
   interrupted load test cannot leave containers running.
4. Nothing exercised the `.tres` files or `primitive_unit.gd` — the
   suite would have stayed green with a completely broken unit roster,
   despite D-010 being the premise the project rests on. `test_unit_defs.gd`
   now loads and schema-checks every `.tres` in `/units/` and asserts a
   squad renders as exactly one `MultiMesh` child (D-009). Verified to
   fail correctly by introducing a deliberately malformed unit.

Also noted, deliberately left as-is: `just nuke` deletes `tools/`
including the running `just` binary. That is correct behavior for
D-014's teardown guarantee; it's now documented rather than surprising.

---

### D-016 · 2026-07-28 · Accepted
**Decision:** Replays are the curve log from D-003 — adopted from M1
onward as the primary desync-forensics tool.

**Rationale:** D-003 makes curve logging nearly free, and replay capture
is valuable for debugging netcode/desync issues from the very first
milestone rather than being bolted on later.

**Rejected alternatives:** Building a separate replay-recording system
(rejected — redundant given D-003).

**Consequences:** None beyond ensuring curve logs are written to
`artifacts/` in a replayable format from M1.

**Revisit trigger:** None currently.

---

### D-017 · 2026-07-28 · Accepted, chunk size Open
**Decision:** Terrain uses a chunked hex mesh (not one mesh per cell) with
biome coloring and elevation vertex offset. Chunk size is determined by
profiling, not chosen upfront.

**Rationale:** One-mesh-per-cell is a known performance problem at
10,000+ cell map sizes (per `CLAUDE.md`); chunking is a hard requirement,
not a style choice. Chunk size has real tradeoffs (rebuild cost on
elevation edits vs. draw-call count) that are better measured than
guessed.

**Rejected alternatives:** One mesh per cell (rejected — doesn't scale);
picking a chunk size upfront without profiling (rejected — premature).

**Consequences:** `gen-terrain-preview` tooling should make chunk-size
experimentation fast.

**Revisit trigger:** Pick a concrete chunk size once M1's terrain work
starts and can be profiled.

---

## 2. Open Questions / Not Yet Decided

Ordered by how much they block. ~~Struck through~~ entries are resolved
and now live as decisions above.

**Resolved this session:**
- ~~Q1 — What does "500 units" mean?~~ → D-018 (2,000 soldiers/player,
  ~50 squads/player, ~40 soldiers/squad)
- ~~Q2 — What is the Rome Total War half of the hybrid?~~ → D-019
  (formations & morale/routing only, no campaign layer)
- ~~Q9 — Simulation tick rate?~~ → D-020 (10 Hz; per-LOD-tier variation
  still open, deferred to M5 with D-012)
- ~~Q6 — C# in the shipping build?~~ → D-021 (no; GDExtension per-kernel
  is the escape hatch, and D-009's C# clause is narrowed accordingly)

**Blocking M1:**
- ~~D-006 confirmation~~ → confirmed 2026-07-28. The
  derived-soldier-positions keystone is Accepted, scoped by the purity /
  one-way-cosmetic-offset / deterministic-reassignment clauses in D-006's
  confirmation block. No longer blocks M1.
- ~~Q6 — C# in the shipping build?~~ → D-021 (no). Note for the record
  that the premise of this question — that it turns on export matrix and
  platform support — did not survive examination; it turned on toolchain
  cost and reversibility instead. **Nothing now blocks M1 on the
  decision side.**

**Blocking M2:**
- ~~Q7 — Combat model~~ → D-024 (2026-07-30): squad-level stochastic
  resolution, server-only, casualties as integer decrements to `alive`.
  The shape question is closed; per-unit tuning *values* are ordinary
  data work under D-010, not an open decision. Note what settled it —
  `alive` is the only formation input a death changes, so D-006 clause
  3's deterministic reassignment holds by construction and no
  per-soldier identity is needed anywhere.
- ~~Q9 — Simulation tick rate~~ → D-020 (10 Hz). The remainder — whether
  the tick rate **varies by LOD tier** — is still open and deferred to
  M5 with D-012, so it no longer blocks M2.
- ~~Fog reveal/conceal semantics~~ → D-025 (2026-07-30): true-position
  pop-in, announced stale ghost, per-player vision field. D-004 is no
  longer Provisional. **Nothing now blocks M2 on the decision side**;
  M2's exit criteria are D-026.

**Still open within M2's scope, deliberately deferred:**
- **Terrain-occluded line of sight.** D-025 makes vision radius-only;
  elevation does not occlude. Deferred rather than forgotten — it needs a
  height field the simulation does not carry yet, and it extends D-025's
  vision field rather than replacing it.
- ~~**Rally vs. permanent rout.**~~ → resolved 2026-07-30 as **rally with
  hysteresis**, which is what M2 already implements. D-024 said this call
  was best made against something playable; M3 is that thing, so the
  decision is to keep the implemented behaviour and revisit after the
  first real playtest rather than change it unplayed. D-024 no longer
  carries an open item.

**Raised by M2's review, 2026-07-30 — logged rather than fixed:**
- ~~**Simultaneous vs. sequential combat resolution.**~~ → **resolved
  2026-07-30 (M3): the round is now simultaneous.** Every attack reads
  strength and rout state from a snapshot taken at the start of the
  round, so squad id no longer decides mirror engagements. Two tests
  guard it, and perturbing the change back to live state makes them fail
  by exactly one soldier (13 vs 12) — the first-strike advantage, made
  visible. Original finding follows, kept for the trail. `Combat.resolve()`
  iterates attackers in squad-id order and applies damage immediately, so
  a lower-id squad kills part of its enemy *before* that enemy fires, and
  the enemy then attacks at reduced strength. It is deterministic, so
  replays are unaffected — but it is not neutral: identical unit types
  share an `attack_interval` and both start at `_last_attack_tick = -1`,
  so they fire on the same ticks indefinitely and the bias never averages
  out. Squads are spawned in join order, so **player 1 systematically
  wins mirror engagements.** Resolving from the round-start snapshot
  (`before_alive`, already taken) would make the round simultaneous. Left
  open because simultaneous-vs-sequential changes battle outcomes and
  therefore wants a D-024 amendment, not a silent patch.
- **Squads render off the map at the seam.** M2's `test-client` frame
  shows a squad drawn below the terrain's bottom edge, outside the
  meshed domain. `StateCurve` stores continuous *unwrapped* axial space
  by design (read its header), so a squad mid-seam-crossing samples to a
  position outside `[0, width) × [0, height)` while the terrain is meshed
  once. Client-side rendering only — the simulation wraps correctly, and
  no D-026 criterion covers it. Invisible until M2 because M1's frame had
  12 squads in one lane and none crossed a seam.

~~**Blocking M3**~~ — **all seven closed 2026-07-30.** D-027 is the
milestone's definition of done. Its shape: full gathering economy,
gatherer *squads* not individual workers, round-trip hauling, four
resources, player-placed construction, elimination victory, four unit
types with counters, and a visually wrapping torus. The seven remaining
items resolved as:

- ~~Are resource wallets private?~~ → **Private to owner.** Showing an
  opponent your stockpiles leaks information of the same family as
  D-003's intent leakage, and fog exists to withhold exactly that.
- ~~Which buildings exist?~~ → **Four**: town centre (gatherer squads,
  doubles as drop-off), barracks (military squads), storehouse (cheap
  forward drop-off), **defensive tower**. The tower is the consequential
  one — it makes buildings *attackers*, not merely destructible targets,
  which is a larger change to `combat.gd` than being a target. See D-029.
- ~~Do resource nodes deplete?~~ → **Finite, generous yields.**
  Depletion is what makes armies contest new ground as a match runs.
- ~~Where do nodes come from?~~ → **Derived from terrain biomes.** This
  invalidates `terrain_gen.gd`'s standing comment that it exposes
  `biome_color` "rather than a biome enum for now: M1 has no gameplay
  that reads biome" — biome becomes first-class simulation data. See
  D-037.
- ~~4-player fairness, given generated nodes?~~ → **Quadrant-symmetric
  generation.** `_sample` already embeds the map on a 3D torus with
  angular `u`/`v`, so doubling both makes the noise repeat twice per axis
  and the four quadrants come out bit-identical *by construction* — no
  scoring heuristic, no seed rejection. Fairness becomes a property of
  the generator. See D-036.
- ~~Population cap?~~ → **Hard per-player squad cap**, sized to D-015's
  12–15 squads, bounding the match on the axis the architecture is
  actually sensitive to. **Gatherer squads count against the same cap**
  (decided 2026-07-30) — one shared ceiling covering military and
  economy alike, so every villager crew is an army slot not spent. That
  is the economy-versus-army tension made structural rather than a
  balance number, and it means the cap bounds *total* squad count, which
  is what keeps M2's measured per-squad budget valid at 4 players.
- ~~Is 64×32 big enough?~~ → **No. The map becomes 128×64 (8,192
  cells).** Evidence: M2's load test gated only 5 of 48 squads, and one
  squad's vision covers ~169 cells, so twelve squads nearly blanket the
  old map. Watch item: `FlowField.build` is a BFS per destination, and
  D-021 names that solver over 10,000+ cells as the prime GDExtension
  candidate — 8,192 sits just under it, so flow-field cost is measured
  rather than assumed.

**Blocking M4/M5:**
- ~~**Q8 — Map size in cells at ship**~~ → **answered by M4's profiling,
  not before it** (2026-07-30). Flow-field build is a BFS per destination
  over every cell, and D-021 already names that solver over 10,000+ cells
  as the prime GDExtension candidate — so map size is an *output* of
  profiling rather than an input to it. M4 sweeps cell counts through and
  past that threshold, finds where the solver breaks, and the ship size
  is chosen from that curve. Torus parity constraints from D-008 still
  bound whatever is chosen.
- ~~**Q15 — Scale validation hardware**~~ → **accept late validation of
  client rendering** (2026-07-30). Note precisely what this defers: Q15
  is about the *client* drawing 40,000 soldiers, which is GPU-bound and
  which the dev laptop cannot do. It is not about the simulation — D-009
  keeps squad state in packed arrays outside the scene tree, so a
  headless server at ~1,000 squads is pure CPU and runs locally, and
  `bot_client.gd` already runs N virtual clients in one process (D-018's
  memory analysis) deriving soldier transforms without rendering them.

  So M4 proceeds as **simulation and network scale-out, measured
  headless**, and the consequences for the two decisions that wait on it
  are unequal: **D-021's GDExtension trigger is fully served** (its named
  candidate, the flow-field solver, is server-side), while **D-012's LOD
  tiers are only partly served** — simulation LOD is measurable, but
  rendering LOD is not, and M5 must not design that half blind.

  **Deferral trigger:** client-render scale must be measured before M5
  commits to any *rendering* LOD tier, and in any case before M7 (Steam).
  Shipping without ever having drawn the target soldier count is the risk
  this decision knowingly accepts; the trigger is what keeps it accepted
  rather than forgotten.

**Blocking M7 / product-level:**
- **Q3 — Who runs the server?** Dedicated (whose money, per-match cost?),
  player-hosted (lower unit ceiling), or Steam relay with a host player.
  Constrains the netcode budget and the business model.
- **Q5 — Is 20 players a design target or an engineering ceiling?** If a
  design target, matchmaking, drop-in/drop-out, and AI takeover for
  disconnects are all in scope and are large.
- **Q10 — Reconnection and desync recovery policy.**
- **Q11 — Anti-cheat posture.** Authoritative server (D-002) helps; the
  leak surfaces are curve horizon clipping (D-003) and client-derived
  soldier positions (D-006).
- **Q12 — Art direction** for mesh tiers 2 and 3 (D-011), and who
  produces it.
- **Q13 — Persistence/saves** for long matches on a seamless map.
- **Q14 — Terminology: what does "seamless" mean here** — no loading
  screens between regions, or one contiguous map? Implies very different
  streaming work.
