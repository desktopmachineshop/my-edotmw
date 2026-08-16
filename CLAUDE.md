# CLAUDE.md — Project Instructions

This file is read automatically by Claude Code at the start of a session.
It exists so you don't have to re-derive the architecture from scratch
every time — the full reasoning lives in `game_design_decisions.md`;
this file is the condensed "ground rules" version.

## Current status

**M1 (movement + netcode proof) complete**, as of 2026-07-29 — declared
done, then audited and found incomplete, then actually finished. At M1's
completion `just test-unit` was green at 141 tests across 10 scripts
(now 158 across 12 — see M2 below); `just test-load 4 12` runs 4 bots
against the server end to end and reports a clean verdict. Every
justfile recipe is real.

The headline measurement (M1, movement only): **~1.5–2.7 µs per
squad-update** at 48 squads, against D-020's ~50 µs budget. That is the
number D-018's full-scale target and D-021's no-C# call both depend on,
so re-measure it (via `just test-load`, which prints it) whenever the
simulation changes shape. It moves run to run with host load — the
order of magnitude is the result, not the third digit.

**Always quote it with a squad count.** It is total tick time divided by
(ticks × squads), so per-tick fixed overhead lands in the per-squad
figure and inflates it when squads are few: a real play session with 12
squads measured ~3.9 µs against ~2 µs for the same code at 48. Comparing
the two numbers directly would read as a 2x regression that isn't there.
Since the whole point is extrapolating to ~1,000 squads, if anything
this metric flatters low counts and understates headroom. This rule
applies to any future number the same way, M2's included.

**Read the audit block at the end of D-022 before adding any test or
check.** M1's first "complete" was wrong in two ways that are easy to
repeat: a test that supplied both client and server the same inputs
itself, and so could not see them disagreeing in the live system; and a
log grep for a word no code path ever printed, which passed vacuously
for the whole milestone and hid the first bug. The standing rule that
came out of it: **every check must be observed to fail before it is
trusted.**

**M2 (combat + fog of war) complete**, as of 2026-07-30 — landed, then
reviewed against D-026 and found to fail three criteria, then actually
finished. `just test-unit` is green at **165 tests** across 12 scripts;
`just test-load 4 12` and `just test-client` both report clean verdicts
that now require combat and fog to have *demonstrably happened*. The two
things that were blocking it are both decided: **D-024** (combat resolves
squad-level and
stochastic, server-only, integer decrements to `alive` with a fractional
carry, morale/rout per D-019, deterministic from a seed) and **D-025**
(fog stays curve gating — a per-player vision field with an O(1)
per-squad lookup, radius-only; reveal is a truthful pop-in, conceal is an
explicit wire event that leaves a stale client-side ghost). `combat.gd`
and `vision.gd` now exist, wired into `squad_sim.gd`; the protocol
carries casualty/rout and conceal events; `just test-unit` is green at
**158 tests** across 12 scripts. D-026 is M2's exit criteria, written
down before the code the same way D-022 was for M1 — read it before
treating anything above as settled, since "landed" and "meets D-026" are
different claims.

**M3 (launchable MVP) complete** — exit criteria are D-027, sliced into
(1) map foundations, (2) playable skirmish, (3) torus presentation, (4)
buildings, (5) economy. `just test-unit` is green at **345 tests**.

*Slice 1, landed:* the map is 128×64, biome is simulation data rather
than colour (D-037), and spawn points come from `MapConfig` instead of a
formula duplicated between server and client. Terrain generation was
briefly quadrant-symmetric, for provably fair spawns — that was dropped
(D-036 revised) because it made every map the same map four times.
Fairness is a resource post-pass now, and as of **D-039 spawns are
scattered randomly at a minimum spacing** rather than placed on a grid,
so adjacency differs every match.

*Slice 2, sim half landed:* combat rounds resolve **simultaneously** —
attacks read a start-of-round snapshot, so squad id no longer confers a
first strike and player 1 no longer wins mirror engagements. The roster
is four units with a real counter triangle in `.tres` data (D-032).
Matches have a lifecycle (`match_state.gd`, D-033): a lobby, elimination
when a player has no living squads, and a winner. Disconnect wipes the
abandoned army and the ordinary rule notices — defeated has one
definition.

*Slice 2, rest landed:* selection (click, shift-extend, box drag,
Ctrl+1-9 groups) and a HUD on a `CanvasLayer`. Right-click orders the
SELECTION and does nothing when nothing is selected. Commands are move,
stop, attack-move, build and produce, each its own opcode validated
server-side through one shared helper.

*Slice 3, landed:* terrain is drawn nine times, tiling across both seams,
so the world no longer visibly ends; the camera wraps in continuous
lattice coordinates (round-tripping through `world_to_cell` would snap
panning to cell centres). Wrap-aware minimap.

*Slice 4, landed:* `building_sim.gd` — a SIBLING of `SquadSim`, with its
own id space. Both sims mint ids from their array length, so the first
squad and the first building are both entity 0; `wire_id()` and separate
plumbing keep them apart, and a test builds one of each at the same local
index to prove nothing leaks. Buildings see, shoot (town centre and
tower), are constructed by squads, and use **persistent-explored** fog —
once seen, never un-known — whose hash must therefore be taken over the
*ever-revealed* set, not the currently-visible one.

*Slice 5, landed:* `economy.gd` — four resources, biome-derived depleting
nodes, and round-trip hauling by gatherer SQUADS, which is what keeps
D-005 intact. Production is per building, gated on ownership, the def's
`produces` list, the shared squad cap and affordability (all-or-nothing).

**The opening changed in M3 and is worth knowing before reading any
test:** a player starts with ONE founding party and no base. Founders
fight better than line infantry, and only they can build a town hall —
expressed in `BuildingDef.built_by`, which is also how they are barred
from building anything else. Everything else is produced.

**Use `just test-load 4 120`.** Two separate reasons, both learned the
hard way:

- Spawns are far apart on a 128×64 map, so four armies cannot reach each
  other quickly. A short run fails with `casualties_applied=0
  conceal_events=0 reveal_events=0` — the verdict correctly reporting
  that combat and fog never happened rather than passing vacuously.
- **A town hall takes 40 seconds and the founding party is spent on it
  (D-031), so a player owns no soldiers until production finishes.** Any
  run shorter than ~90 s reports `soldiers=0` and fails, and that is the
  check working, not a bug. `4 40` was the recommendation here for a
  whole milestone and could not have passed since D-031 landed;
  `test-client`'s 15 s default had the same problem. **When the opening
  changes, every timing tuned against the old one is stale** — that
  applies to the load test, the capture scenario, and any scripted bot
  phase.

**M4 (scale + performance): every measurement it set out to take is
taken.** They live in D-038 and D-040 through D-042. At D-018's target of
20 players:

- **bandwidth 595 B/client/s**, zero budget overruns — not close to a
  problem, which is D-003's curve sync doing its job
- **server 42.5 MB** at 120 squads; **~1.4 MB per virtual client**
- **40.8 µs/squad at 120 squads** live, inside D-020's ~50 µs — but read
  the squad-count caveat above before comparing it to anything
- **0 ticks over D-020's 100 ms budget** in a 20-player match, worst tick
  38.1 ms
- **transport: peak RTT 14 ms, peak loss 0.98%, 0 desyncs** — reliable
  delivery is genuinely absorbing loss, not idling, so unreliable-with-
  resend is rejected (D-042). Note curve packets carry no sequence
  number, so **in-order delivery is load-bearing**, not incidental
- **client derivation 0.72 µs/soldier** — *but see M5: that was measured
  with no terrain sampler attached, and the real client always has one,
  so it understated the true cost several-fold.* A player's own
  2,000-soldier army costs ~1.4 ms/frame, but all 40,000 visible at once is 174% of a
  60 fps frame (D-041). Frustum culling before deriving is the next
  lever, ahead of any LOD work
- the sweep (`just profile`) remains the authority on *scaling*, since a
  live match cannot reach 1,000 squads — but see the blind-spot warning
  below before trusting it alone: **33 µs/squad and a 73.4 ms worst tick
  at 1,000 squads**, inside the 100 ms tick

**The flow-field spike is fixed (D-040), and the tick budget is met.**
A BFS is now spread across ticks under a per-tick CELL budget
(`field_cells_per_tick`, 4,096). Worst tick at 8,192 cells went **344 ms
→ 28.6 ms**, and at D-018's full 1,000 squads **1,211 ms → 73.4 ms**,
inside D-020's 100 ms with ~27% headroom. Worst tick is now *flat in map
size* — 32,768 cells costs the same spike as 2,048 — so **Q8's map-size
bound is no longer the solver**. D-021's GDExtension hatch stays shut and
its one named candidate is retired: the solver never needed native code,
it needed to stop doing a whole solve in one slice.

Two things to carry forward. A partially expanded field is **correct
wherever it is defined** (BFS finalises a cell the first time it reaches
it) — but UNREACHABLE means "not reached yet" until `is_complete()`, and
reading it as "no path" would silently cancel every order in a wave.
Budgeting **cells** works where D-038's budget on **builds** failed,
because partial progress is kept instead of discarded.

**A green `just profile` is not a green server.** The sweep reported a
healthy ~29 ms worst tick while a live 20-player match spiked to 866 ms.
The cause was `UnitRoster.by_id` re-scanning `/units` from disk on every
call — and `SquadSim.tick` calls it once per squad a building finishes,
so twenty simultaneous completions spent **858 ms in a filesystem walk**.
A sweep resolves its UnitDefs once at setup and structurally cannot see
this. Where the sweep and a live run disagree, believe the live run.

The server now reports `worst_tick`, how many ticks exceeded budget, and
a **per-phase breakdown on any over-budget tick**. That is what found it;
every hypothesis formed before instrumenting was wrong.

**Before theorising about an anomalous run, read the server log.** The
first 20-player run reported "zero movement" and invited theories about
spawn placement. The cause was 2,700 lines of "tried to order squad N it
does not own": ownership was cached per connection at join, so every
*produced* squad was refused. Fixing it exposed two more defects whose
symptoms had been cancelling each other out. See D-038's amendment.

Measured after that change: **72.4 µs per squad-update at 48 squads —
vision 14.0, combat 42.7**, on 128×64. Quadrupling the map area cost
essentially nothing against M2's 70.8, because vision and combat scale
with their disk *radius* rather than map area and flow fields stay shared
per destination (D-007). Fog now gates 21 of 48 squads from the
best-informed client, against 5 of 48 on the old map.

The M2 measurement it replaces, from `just test-load 4 12` on 64×32:
**70.8 µs per squad-update at 48 squads — vision 15.3, combat 45.5.** Against D-020's
~50 µs that is 1.4x over the "half a core" aspiration, but it
extrapolates to ~71 ms inside a 100 ms tick at D-018's ~1,000 squads, so
D-020's actual revisit trigger (exceeding the tick budget at full scale)
is **not** tripped. Two things to carry forward: **combat is now the hot
spot**, not vision, so it is where M4 profiling should start; and the
per-squad figure is dominated by genuinely per-squad work, so unlike M1's
number it does not shrink as squad count grows.

That figure was 282 µs/squad before review — vision alone was 232. The
cause was calling `TorusSpace.distance()` once per candidate cell while
stamping a hex disk. **A hex disk is translation-invariant on a torus**,
so the offsets within a radius are computed once and cached
(`TorusSpace.disk_offsets`) and reused by both `vision.gd` and
`combat.gd`. If you add another radius-scanning system, use that table —
do not reach for `distance()` per cell.

**M5 (client scale) — the milestone D-015 called "LOD", renamed on
evidence.** Exit criteria are D-044; the work is D-045. M4's numbers made
"LOD" wrong in both directions: the simulation did not need it (the tick
budget was already met), and the client had never been measured at all.
So M5 measured the client first and built only what the numbers asked
for.

`just bench-render` is the new recipe — **native, because it needs a real
GPU**; `test-client`'s software rasteriser can say whether the picture is
correct but never how fast it is. It prints the video adapter, and **a
frame time without hardware attached is not a number anyone can use**,
the same rule as never quoting µs/squad without a squad count.

On Intel Iris Xe integrated, at 1,000 squads / 26,644 soldiers:

| | ms | fps |
|---|---|---|
| baseline | 94.50 | 10.6 |
| + terrain sampled from a precomputed field | 66.70 | 15.0 |
| + cull before derive (wrap-aware) | 56.06 | 17.8 |
| + render LOD | 35.66 | **28.0** |

500 squads now runs at ~57 fps. **The measurement overturned one of M5's
own criteria before it was written**: batching squads by unit type was
planned on the assumption of ~1,000 draw calls, and the real number was
154 — Godot already frustum-culls per-squad `MultiMeshInstance3D`s. The
frame was 97% CPU, all derivation, so batching would have solved nothing.
That is what taking a baseline first is for.

**Three rules carried out of it.** Terrain elevation is memoised
(`TerrainGen.elevation_field`) — sampling noise per soldier per frame was
the third instance of the same defect, after `distance()` per cell in
vision and `by_id` per produced squad. Culling on a torus must test the
**wrapped** copy (`TorusSpace.lattice_steps` is now the one definition,
shared with terrain tiling and camera wrap) or armies vanish at the seam.
And render LOD draws a distant squad **thinner, never smaller** — unit
size is tactical information a player reads off the screen.

**Watch `test-client`'s casualty gate.** It is meant to prove combat
happened and is now satisfied by *founding a town hall*, because
consuming the founding party reports through the casualty path. It passes
without any fighting. Recorded in D-045; fix it when next touching the
capture scenario.

**M6 (civs, lobby, AI) — in progress.** Civs are data (D-047), the lobby
seats humans and AI with teams and shared vision (D-048/D-050), colours
are per player (D-052), and AI players are clients without a socket
(D-051) held to every rule you are. `just ai-ladder` measures AI strength
(D-054); `just run-server AI=3` seats opponents without a lobby so a
human can play one.

**The single most important thing M6 found: nothing could destroy a
building, so no match could be won** (D-055). `BuildingSim.damage()` was
fully written and called by nothing outside its own tests for two
milestones. Buildings shot at squads; squads never shot back. Every AI
ladder match drew at the time cap, and that was read as an AI weakness
through several rounds of AI work before anyone checked. Fixing it took
the ladder from **0 of 3 decided to 2 of 3 with no AI change at all**.

**So: grep for uncalled public members.** This was the THIRD
declared-and-unread mechanic here, after `UnitDef.cost` and
`BuildingDef.cost`. The shape is always a field or method with no caller,
and it survives because *nothing fails* — the game runs and quietly lacks
a rule. No test can see it, because the code under test is correct. This
is the one defect class this project's testing discipline is blind to by
construction.

**And there is a harder variant of it, found by playing (D-061).** Three
of the four interface bugs fixed there were rules that WERE fully written
and DID have callers — the caller was simply unreachable. Rally orders
were encoded, validated server-side and drawn on the ground, and the
client returned two lines before the branch that sends them, because
selecting a building clears `_selected` and the guard against ordering an
empty selection fired first. `health_fraction` was on the wire, in
`ClientState` and drawn by the panel, and only ever carried 1.0 because
nothing marked a damaged building dirty. A grep for uncalled members
finds none of these. **Nothing but using the thing does** — so when
something that plainly ought to work does not, suspect an unreachable
branch before suspecting the mechanic is missing.

**Its sibling, found the same way (D-065): a decision entry saying a
field is on the wire is not evidence that it is.** D-058 made formation
mutable, replicated state and describes the server resending "ordinary
`SQUAD_INFO` — the message that already carries shape". `SQUAD_INFO` did
not carry shape, and still resolved it from `UnitDef` on the client. Every
server-side part D-058 describes was real and correct, so nothing failed;
the formation buttons simply did nothing, and every gathering crew that
reached a node desynced its owner permanently. **When a decision says a
field is replicated, open the encoder and look for it.** And when a
feature "does nothing", suspect the wire before the UI — the button had
been correct all along.

**A fourth, and the cheapest to check for (D-100): a doc comment on a
field is not evidence that anything writes it.** `MapSettings.seed` said
"Rolled per match unless someone pins it" for a whole milestone and
nothing anywhere rolled it, so every lobby match — every match a human
plays — generated the identical world from seed 1337. One line away,
`civ_rng` was seeded from the same absent `--seed` argument defaulted to
**0** where the map defaulted it to **1337**, so a seat set to Random
resolved to a real civ (the visible half working) and to the SAME civ
every match. Neither can fail a test, and the only instrument that sees
them is somebody playing twice and recognising the coastline. **When a
comment describes behaviour in the passive voice — "is rolled", "is
sent", "is resolved" — grep for the writer before believing it.**

The second half of D-065's bug is worth its own rule: **a per-tick
assertion silently outranks a player's order.** The economy re-asserted a
gathering crew's shape every tick, so a player's choice survived 100 ms.
Anything the simulation sets every tick now goes through
`SquadSim.suggest_shape`, which a player's `set_shape` latches out.

**And a third of the same family (D-066): a mechanism can be correct, its
data nonzero, and the feature still absent.** Buildings shot exactly as
designed; a town centre cost a lone attacking squad **4 men out of 36**,
because `BuildingDef.damage` is a FLAT per-shot number while a squad's
volley is `UnitDef.damage x alive` — the same word, ~40x apart. Every
buildings-shoot test used a caricature def (damage 40, 0.1 s interval) to
see a casualty in five ticks, and the only test touching shipped data
asserted `damage > 0`. **A test that proves the mechanism says nothing
about whether the shipped numbers do anything** — for anything a player
is supposed to FEEL, run the whole encounter with shipped defs and assert
what it costs.

**The shipped rule is now D-067's** (D-066's 45/80 lasted a day): **one
squad of any starting troop cannot raze a defended building; two can.**
Town centre damage 60; tower 85 at 1700 HP. Two measured exceptions,
both tested and both in D-067 — founders (a player only ever has one
party) and northmen_skirmishers against a tower (no tower HP/damage pair
exists that stops a lone militia squad and still loses to two of them).

**And the defect that was hiding under it: `TorusSpace.disk_offsets` was
not sorted by distance.** It enumerates dq-major from `-radius`, so its
first entries are the far edge of the disk — while three callers walked
it looking for "the nearest free cell". A second melee squad sent at a
building was shoved four cells away, outside its own reach, and stood
idle for the rest of the match: two squads dealt 1560 damage where one
dealt 1461. The table is sorted nearest-first now, which made all three
callers' doc comments true at once. **The standing "reach for
`disk_offsets` before `distance()`" rule still holds — and the table is
ordered, so "walk outward until you find one" is now a thing you may
actually do with it.** Measured after: `test-load 4 120` clean,
**59.60 µs/squad at 52 squads** against 60.72 before, so the per-radius
sort costs nothing.

**The ladder still decides at these values:** `just ai-ladder 3 600` gives
**2 of 3 decided, 1 draw**, one win each civ, first attack ~195 s — the
same 2-of-3 D-055 measured before the buff. Read at **420 s** the same
build reported 3 of 3 drawn, which was the CAP truncating longer matches,
not a weaker AI. **A stronger defence lengthens matches, so quote a
ladder result with its cap** — the same rule as quoting µs/squad with a
squad count.

**Check which instance you are on before believing a load-test failure.**
Two runs failed with `buildings_known=0` and identical numbers, and it
looked exactly like the change under test. A second container held port
4433 and the bots were reaching that one — the tell was **server-side
instrumentation printing nothing at all**, which no code-level bug can
do. `docker ps` first. That incident is why D-095 exists: every checkout
now derives its own compose project and host port (see the isolation
section below), so `just down` is scoped to THIS worktree's containers
and cannot remove anybody else's. `just instance` prints what this
worktree resolved — read that line before believing a failure.

**Target match length is 1–2 hours, and the game is nowhere near it**
(D-056). Matches decided at ~200–230 s. Measured cause: with no modifier,
one 36-strong militia squad razed a 900 HP town centre in **2.1 seconds**
— a base evaporated the moment any army arrived, and that number was
introduced by D-055 the same day it made buildings damageable at all.

Two data changes toward it: `UnitDef.damage_vs_buildings` (default 0.15,
a schema addition against D-010) and roughly tripled building health, plus
**`squad_cap` 15 → 40** against D-018's ~50/player target — an "army" was
about six squads once gatherers were paid for.

**Neither reaches 1–2 hours, and is not meant to.** The structural cause
is that **there is no progression at all** — four buildings and four
units per civ, no ages, no tech, no upgrades — so after roughly three
minutes there is nothing to do but fight. **Don't try to reach an hour by
tuning health.**

**And a fourth instance of the `distance()`-per-candidate defect** landed
in the same change and was caught by `test-load`: scanning every building
per squad cost ~15 µs/squad, bucketing it cost ~1.3. After vision (M2),
`UnitRoster.by_id` (M4) and terrain noise (M5), treat this as a standing
rule — **any radius scan reaches for `TorusSpace.disk_offsets` before it
reaches for `distance()`.**

Two M6 numbers left honestly open. The rise from M4's **40.8 µs/squad at
120 squads** to **~77** is *not* the siege pass (measured with it
disabled) and is still unattributed to whichever of civs/teams/economy
caused it. And worst-tick figures from that session are unreliable — a
run with strictly *less* work reported 146 ms where a fuller run reported
52 ms, because the host was building containers throughout. Zero dropped
ticks in both.

**M7 (real models and textures) — complete, as of 2026-08-14.** The
ladder gained a rung: art is M7 and Steam becomes M8. Exit criteria are
**D-085**; the work is **D-081** (art direction and pipeline, superseding
D-011 and closing Q12), **D-082** (animation) and **D-083** (terrain
texturing). (These were first recorded here as D-063/D-064/D-065/D-066 —
IDs that collided with unrelated, already-real entries. Corrected
2026-08-11; see D-081's editorial note in `game_design_decisions.md` for
why.)

Landed: eight authored unit archetypes and four buildings, animated,
on textured terrain, all generated from committed Python and rendering
through the shipping path. See "Mesh pipeline" below for the rules that
came out of it — they matter more than the asset list.

**Two of M7's defects were invisible to every number and visible in a
picture**, which is now three milestones running. Every soldier rendered
black because a MultiMesh overrides the shader's `COLOR` with its own
per-instance colour, so vertex colours never reach the fragment stage on
the path this game renders through. And every `box()` was wound
inside-out, which cost nothing but lighting until a building got big
enough to look inside. Neither would have failed a test that counted
things.

**D-085 criterion 11 is now discharged, with a caveat (D-086,
2026-08-11).** `just bench-render` was re-run on Intel Iris Xe integrated
graphics — the same hardware M5 used, no discrete GPU was available — and
the cost of animated vertices at D-018's full scale is measured, not
extrapolated: **53.93 ms mean / 18.5 fps at 1,000 squads (27,300
soldiers)**, against M5's pre-authored-model 35.66 ms / 28 fps on the
same hardware. Authored VAT models cost **51% more** at full scale than
the primitive capsules M5 measured. This also discharges Q15's re-armed
trigger. **Criterion 14 (a human plays a match with the new art) is
discharged, 2026-08-14** — closed by the live human playtests of
2026-08-12/13 (see D-076's amendments and D-085's own), confirmed by the
owner as real matches with the authored models and D-086's lighting on.
That closes the last open criterion and is what moved M7 from *landed* to
*complete* — the landed-vs-complete distinction M2 and M6 both had to
learn, honoured this time. The one caveat that survives: criterion 11's
numbers are all from integrated graphics, and the discrete-GPU re-run
trigger in D-085 stays armed.

**The ground is continuous, and cliffs are drawn (D-096/D-097,
2026-08-15).** The owner's complaint was that the ground read as a
honeycomb of flat hexes and no cliff was visible anywhere. Four causes,
all in the code, none visible to any number:

- vertex colour was one flat value per cell, so it stepped at every
  boundary. A shared corner now takes the mean of its three cells — the
  same trick D-084 used for heights — and `biome_color()` stays the
  single source of truth, so the minimap and the preview PNG cannot
  drift. The preview PNG is byte-identical before and after, which is how
  that is checked;
- the centre vertex sat at the cell's own elevation and domed each hex.
  That is `TerrainGen.pillow` now, shipping at 0.15 against the old
  implicit 1.0. `height_at` reads the same array, so the sampler follows;
- each hex sampled its own inset, hash-rotated atlas tile. UVs are
  continuous across cells now and still CELL-derived, never from world
  position (D-035). `TerrainChunk.uv_scale` is arithmetic rather than a
  constant: the texture meets itself across the seam only if the map
  period is a whole number of repeats on BOTH axes, and stepping `height`
  in r moves world x as well as z;
- `surface_field` averaged corners across the passability boundary, so a
  mountain was a smooth ramp that happened to be grey. Corners now
  average WITHIN a passability class and step between them, and a rock
  skirt fills the step.

**`shaders/terrain.gdshader` is the project's first terrain shader**, and
continuous UVs are why: a continuous coordinate over an eight-tile atlas
walks out of one biome's tile into its neighbour's, and wrapping it back
is a per-fragment decision. Each cell carries three tile indices,
constant over the cell (an interpolated INDEX would ask for tile 4.7),
and each vertex its weights over them. The fragment samples with
**explicit gradients**, because `fract` tears the derivative once per
repeat and the implicit version draws a bright seam every few hexes in a
ruler-straight line. Cost, measured before deciding, on Intel Iris Xe:
**+0.11 ms terrain-only and nothing resolvable at 1,000 squads /
27,300 soldiers** against a 2 ms budget — the frame is CPU-bound on
soldier derivation, 48 ms of 52, so two more ground taps are nearly free.

**A one-cell blend is not enough at high contrast, and that took a second
pass to learn.** Blending a corner over its three cells makes every
transition exactly ONE CELL wide. At grass-to-sand that reads as soft; at
sand-against-water — the strongest contrast on the map — one cell is one
HEX, the 50% contour runs along the hex edges because that is where the
three weights are equal, and the shoreline comes out visibly scalloped.
An isolated sand cell in open water rendered as a clean six-pointed STAR.
So two more things: the contour is pushed off the lattice by a
low-frequency periodic warp of the corner weights (`blend_warp`, sampled
at the CORNER so all three owners agree), and the band is widened past
one cell by letting a centre take some of its own already-blended corners
(`centre_bleed`). **Warping alone was measured and was not enough** — its
first version moved the rendered picture by at most 19/255, because
`FastNoiseLite` rarely approaches ±1 and an amplitude that reads as "most
of a hex" displaces about a third of that.

The centre-vertex invariant changed with it and the new one is narrower
but still real: **a cell whose six neighbours share its biome carries
`biome_color` at every vertex exactly**; boundary cells deliberately do
not, because that is the feathering. The test asserts the interior case
exactly rather than loosening to a tolerance everywhere.

**And a perturbation the suite failed.** Sampling the warp at the calling
CELL rather than at the corner — which gives a corner's three owners
three different answers — left every test green, because `build_fields`
computes each corner once and hands the same cached triple to all three.
**The cache made the mesh watertight however wrong the arithmetic was.**
Only calling the function from each of the three sides can see it. When
an optimisation makes a property hold structurally, the test for that
property has to bypass the optimisation.

**The finding worth carrying forward: a truthful drawing of the
passability boundary draws nothing.** The natural height step where two
classes meet on the shipped map has a **median of 0.20 world units along
the coast and 0.66 at a mountain foot**, because elevation is smooth
noise and `passability` is a level set on it — so the boundary can never
fall where the ground is already steep. Drawn faithfully it produced
**87 rock faces on the whole 8,064-cell map**, which is this project's
"mechanism correct, shipped numbers do nothing" failure wearing a green
verdict. Mountains are therefore LIFTED onto their own tier
(`cliff_rise`, 2.0 world units): the wall still stands exactly where
`passability` changes, and the lift only makes it tall enough to see.
363 faces now.

**And a related fact about the shipped map that is not a rendering
matter:** 21.7% of its cells are impassable and 20.9% are water, which
leaves roughly **66 mountain cells and 80 land/mountain edges** on 8,064.
Cliffs there are mostly coastal. If more rock is wanted the lever is
`mountain_level` and the `/terrain` presets.

**`just gen-terrain-shot` is the new recipe, and it exists because the
old instruments structurally could not see any of this.**
`gen-terrain-preview` draws a top-down biome map from `biome_color` and
reports chunk counts — every number healthy throughout. `test-client`
renders the real thing and points its camera at a spawn, which is
walkable ground by construction and therefore the one place a cliff
cannot be. The new recipe frames the terrain on the longest run of
passability boundary on the map, from a shallow angle, in the SHIPPING
lighting rig. **Look at `artifacts/terrain-3d.png`.**

Three smaller things bought the same way. The rock face's normal is
tilted ~27 degrees up while its geometry stays vertical, because D-086's
rig has no shadows and a truly vertical normal drew mountain walls at
sRGB 0.09 — dark enough to read as holes cut in the world. Colour steps
with the height at a cliff, or a mountain plateau is painted in the
colours of the valley below it. And `TerrainGen.corner_cells` returns its
three owners SORTED, because float addition is not associative and three
owners summing one triple in three orders can differ in the last bit —
which makes watertightness a property of the arithmetic rather than of a
tolerance.

Terrain meshing for the standard map costs **~600 ms to ~1,100 ms** at
client start as a result, once per match. Frame cost of the whole change,
terrain only, on Intel Iris Xe: **3.97 ms to 4.05 ms**.

**And a warning about the numbers, which cost an hour to work out.** The
1,000-squad `bench-render` absolutes from that session are junk: the same
unchanged build measured **52.1 ms early and 181.1 ms three hours later**,
after continuous GPU benchmarking, with worst frames near 900 ms. The A/B
deltas taken from interleaved pairs are still sound — that is what
interleaving is for — but any absolute quoted from a long benchmarking
session should be checked against a fresh one. This is the same lesson as
M6's worst-tick figures taken while the host was building containers.

**Resource nodes are forests now (D-087, 2026-08-14).** Placement is a
per-biome density field riding the same moisture noise `biome_at`
classifies with — dense forest hearts, groves thickening toward the
treeline, orchards mid-moisture, arid trees and palms on dry ground and
beaches, stone at the mountain FOOT (its old MOUNTAIN-cell placement was
unreachable scenery; the AI's give-up mechanism existed because of it).
Standard map: **1,920 natural nodes vs ~134 before (~14x)**. Trees
(wood/food) carry `TREE_STOCK` 105 — one shipped gatherer crew works one
out in **~60 s**, pinned by a test against the shipped def — while
gold/stone keep 2400. A worked-out tree auto-retargets its crew to the
nearest surviving node of the SAME kind within 8 cells (never
substituting kinds). Depletion is a fog-gated wire event
(`S2C_NODES_DEPLETED`): told when the knower can SEE the cell, stale
ghost-tree otherwise; the client fells it with a tip-and-sink animation.
Rendering is 50 authored variants (10 species × 5, split from
`tree-variants.glb` by `split_markers.gd`) picked per cell by
`resource_visuals.gd` (pure/static — species by biome+moisture, 35%
boundary borrowing so treelines fray, hash yaw/scale), batched into one
MultiMesh per (16-cell chunk, model) with the torus tax paid per chunk.
Bots finally ORDER the gatherers they produce — the haul cycle had never
run under `test-load`'s wire before — and report `nodes_felled` in the
verdict (a metric, not a gate: a felling needs ~3 minutes of match, and
gating would re-set D-031's stale-timing trap).

**D-086 (2026-08-11): the lighting layer M7's art never had.** The
"low poly vs cartoon vs current" style question turned out to have a
false premise — the game was already low poly at the extreme end (two
primitives, 72-256 tris/soldier against a 300 budget); what actually
separated the three options was lighting, and the project had almost
none (one `DirectionalLight3D`, a flat navy `BG_COLOR`, no shadows, no
sky, no tonemap, no fog, duplicated by hand across three files). Chose
**polished low poly**: `world_look.gd` is now the one definition of the
rig (guarded by a test that scans every other script for a stray
`DirectionalLight3D`/`Environment` construction); sky, sky-sourced
ambient, ACES tonemap and depth fog replaced the flat void at a measured
cost of essentially zero (54.26 ms vs 53.93 ms mean at 1,000 squads); the
8-colour terrain palette was re-tuned for the new tonemap. **Shadows were
evaluated against the bench-render number above and explicitly deferred**
— at 1,000 squads the frame was already 3.2x a 60 fps budget before
spending anything on a shadow pass; 250 squads (76.6 fps) has headroom
for a future squad-count-gated version. Cartoon/toon shading was rejected
for the same reason: its outline pass would double the per-soldier vertex
shader (including the VAT's three `texelFetch`es) and cannot be verified
by `test-client`'s software rasteriser at all (Forward+-only
`CompositorEffect`).

**The gaps between hexes are fixed (D-084).** They were pre-existing
rather than M7's, but textured ground made them the most obvious thing on
screen. Each hex corner now takes the mean of the three cells meeting
there, so neighbours agree and the surface is watertight; the centre
vertex keeps its own elevation, which leaves each hex a very shallow
pillow. Normals are derived instead of hardcoded `Vector3.UP`, so slopes
finally shade.

**The simulation did not change and must not.** `elevation_at` stays
discrete per cell and `passability` still thresholds it — only the
picture interpolates. That split is what made this a rendering change
with no desync surface, and **it stops being free the moment elevation
acquires tactical meaning** (terrain-occluded line of sight is still
open).

`TerrainGen.surface_field` is one array of 7 heights per cell, read by
BOTH the mesher and the client's ground sampler
(`TerrainChunk.height_at`), which is why they live in the same file. A
sampler that matched the mesh only by being written correctly twice would
eventually drift, and the symptom is an army floating with every number
green. The sampler is also a hot path — once per soldier per frame — and
is no longer a single array index; its cost on real hardware is
unmeasured.

D-006 (derived soldier positions) is Accepted and implemented in
`formation.gd`. Its three binding clauses are load-bearing for
everything built so far: soldier position is a **pure function** of
(squad curve, formation shape, slot index, terrain sample) with no
per-soldier integration state; client-side cosmetic offsets are
**one-way** and never read back by simulation; casualty slot
reassignment is **deterministic** (the formation restamps — soldiers
don't walk into a vacated slot). Emergent per-soldier movement of any
kind — local avoidance, collision push-back, jostling — is out of bounds
and is the explicit revisit trigger.

`Formation` is an all-static class on purpose: there is nowhere to put
per-soldier state, so the purity clause is enforced rather than merely
documented. Cosmetic motion lives in its own file (`cosmetic_offset.gd`)
for the same reason — the one-way boundary is structural. Combat's
resolution of Q7 (D-024) satisfies this trivially rather than delicately:
`alive` is the only formation input a death changes, so casualty
reassignment needs no per-soldier identity anywhere, and `Formation`
gained no instance state to support combat.

**Between M7 and M9, three days of playtest-driven work landed (2026-08-11
to 08-14) that belongs to no numbered milestone.** `just test-unit` is
green at **563 tests** across 37 scripts (measured 2026-08-14);
`test-load` clean at **57.88 µs/squad** (4 bots, the usual ~52 squads —
quote it with the count, as ever). The pieces:

- **Walls, gates, and a walkable wall-top tier (D-076)** — the feature
  D-069 explicitly fenced out of M9 and said needed its own decision.
  Chained single-cell buildings, not edges; the wall-top is a second
  `FlowField` layer with its OWN cell budget (sharing D-040's counter
  would halve ground-pathing throughput on any tick both run); climbing
  is one explicit teleport hop through an access tower's door, which is
  what keeps a squad's tier legal under D-006 (nowhere for a
  partial-climb value to live). Tier-1 squads fight with their own stats
  plus a range bonus and can only be hit by tier-1 or ranged attackers.
  Two standing gaps: **no AI builds or uses walls, so `just ai-ladder`
  cannot exercise any of this feature**, and the geometry/placement UX
  is only proven by playing (it lives in `client.gd`, unreachable from
  GUT).
- **The playtests that closed M7's criterion 14 also earned their keep in
  bugs.** The best one: `_finish_build` consumed ANY builder on
  completion, not just founders — so every gatherer that finished a
  barracks, tower or wall had been silently vanishing since D-031. The
  declared-and-unread defect family, in its over-READ variant; nothing
  fails, the game just quietly loses a rule. Found only by playing.
- **Sandbox mode (D-077)** for dev testing, structurally unable to leak
  into a real match; **leave-to-lobby and no-humans-means-no-server
  (D-075)**; the in-game UI reworked to the reference design; authored
  models for resource nodes and the wall family; tower upgrades.
- **An in-match scoreboard (D-102)**, from the #29 playtest, where the
  absence of one blocked a pass criterion outright: per-player colours
  were fully built, tested for distinctness and drawn consistently, and
  a player could not tell which colour was whose once the lobby closed.
  **That is the "mechanism correct, feature absent" family applied to
  legibility** — nothing failed, and the feature was half-delivered.
  Everything the board needed for IDENTITY was already on the client;
  the half that did not exist was **standing**: elimination has been a
  server-side `print` since D-033 and the wire carried none of it, which
  the client's own defeat screen had recorded correctly for two
  milestones. **The board is also the fog line applied to a menu** —
  army size is derived from what the server already sent (own and ally
  only, D-050), never asked for, so an enemy's total is a dash and there
  is no packet a future caller could leak one from.

**M8 (Steam) is PLANNED but NOT BUILT** — the planning session ran on
2026-08-14 and produced **D-087 through D-094**, closing every question
in the old "Blocking M7 / product-level" block (Q3, Q5, Q10, Q11, Q13,
Q14). Everything in them is design; no code, no export preset, no
Steamworks anything exists in the repo. The shape:

- **M8 is Steam-ready, not launched** (D-087). Its output is a private
  depot branch and a repeatable playtest loop; the public launch waits
  on M9's content. "Seamless" closed by inspection: one contiguous
  wrapped map, true by construction since D-008.
- **Player-hosted first, official dedicated later** (D-088, owner's
  call). The host runs the authoritative sim **in-process** — the
  loopback peer D-051's AI clients already use connects the host's own
  client; remote players arrive over Steam relay. D-042's
  reliable-ordered contract is a hard requirement on the Steam path.
  ENet stays for LAN, docker, bots and the whole test estate.
  Host-quit kills the match and the host is trusted — both accepted
  with eyes open, both fixed by dedicated-later.
- **20 players is a design target** (D-089, owner's call): Steam lobby
  browser + invites, AI seat-fill, drop-in/drop-out. No matchmaking
  service.
- **Reconnection is repossession** (D-090): disconnect hands the seat
  to an AI immediately (no grace-period limbo, no timeout — the AI is
  the grace mechanism); rejoin reclaims by **SteamID, not connection**
  (the D-038 ownership-cache lesson); desync recovery is
  drop-and-rejoin, cheap because D-025's reveal semantics make every
  join cheap. Supersedes D-033's wipe-on-disconnect for humans.
- **The server IS the anti-cheat** (D-091): no kernel AC; fog gating
  means the maphack's memory isn't there. Ranked play is explicitly
  gated on dedicated servers.
- **No saves** (D-092): reconnection + replays cover the real need;
  revisit triggers named.
- **GodotSteam behind one script** (D-093): D-021 amended by exactly
  one category (platform integration). One boundary script names
  Steam, a grep-test enforces it (the D-046-criterion-3 pattern), and
  absent Steam costs Steam features, never the game — docker and every
  test recipe stay Steam-less by construction. Still no C#.
- **Exit criteria are D-094** — ten of them, written before the code.
  The load-bearing early ones: a protocol **version handshake** (none
  exists today, and Steam's rolling updates make mixed versions
  routine) carrying SteamID seat identity, and the export→depot→install
  loop, since the headline criterion (a 20-seat match with ≥3 real
  remote humans over the real internet) needs playtesters on installed
  builds. Criterion 9 finally takes the discrete-GPU `bench-render`
  number Q15 has been waiting on. Criterion 10 is a human playing
  end-to-end through the Steam build — the D-085-criterion-14 lesson,
  applied from day one.

**M9 (epochs, six civs) is PLANNED but NOT BUILT** — the planning
milestone Q15 reserved ran on 2026-08-04 and produced **D-068 through
D-074**. Everything in them is design; **no code or `.tres` was written**,
so treat the schema in D-070 and D-010's log as a specification, never as
a description of the repo. The shape:

- **Five epochs, antiquity → high medieval** (D-069), each earning its
  rung by adding a new *verb* — settle, field, hold, break, decide — not
  bigger numbers. The ladder is shared by all civs and lives in
  `/epochs/*.tres`; **no script may name an epoch**, exactly as none may
  name a civ.
- **Six civs** (D-071): Legion, Northmen, Magyars, Byzantines,
  Carthaginians, Chinese — filling one seven-column frame, no two
  matching on more than one column.
- **Rosters grow by replacement** (D-070), which costs ~90–130 unit
  `.tres` at completion and is accepted knowingly.
- **An army becomes a running cost** (D-068). Per-soldier food upkeep;
  unpaid upkeep decays morale through D-019 rather than killing anyone.
  **`squad_cap` stops being a design lever and reverts to an engineering
  ceiling** for D-018/D-020 — upkeep is what a player should feel.
- **D-068 is the derivation base.** Its six-phase table is what D-069's
  timings and D-072's costs are derived from. The whole current match
  fits inside its first row.

**Two things M9 must fix before it starts, both found during planning:**
three `CivDef` knobs (`squad_cap_bonus`, `production_speed`,
`gather_speed`) are shipped with non-default values and **read by
nothing** — the fourth declared-and-unread instance, and two of the six
civ identities depend on them. And M6's unattributed **40.8 → ~77
µs/squad** rise must be explained first, or M9's own tick-budget numbers
cannot be interpreted.

**A power budget now exists for balancing units** (D-072):
`V = sqrt(DPS × EHP)` against `RP = food + wood + 1.5×(gold + stone)`.
Run against the shipped roster it found that **militia leads on both
power and cost-efficiency for both civs**, and that `legion_heavy` has
lower DPS than `legion_militia` at 2.5× the cost. Two rules came out of
it: price must buy power, and no unit may lead on both axes within its
role.

## What this project is

A large-scale real-time strategy game, inspired by *Empires: Dawn of the
Modern World* and *Rome: Total War* (formations and morale/routing,
specifically — not a campaign layer), targeting **20 concurrent players
/ 2,000 soldiers each (40,000 total, ~50 squads/player, ~1,000 squads
total) on a single seamless map**, 4–6 civilizations at launch, shipping
on Steam. Built in Godot specifically because its plain-text asset
formats (`.tscn`/`.tres`) make the project directly editable by Claude
Code — that's a design constraint, not an afterthought.

**Before making any architectural decision, check `game_design_decisions.md`
first.** It's the living record of every major call made so far, with
rationale and rejected alternatives attached. If a decision isn't in
there yet, flag it explicitly rather than picking silently — this
project's whole workflow depends on decisions being written down, not
just implemented.

## Non-negotiable architecture (do not casually deviate from these)

- **Client-server, not lockstep.** Server is authoritative. Clients send
  input, receive curve-based state updates, interpolate locally.
- **Curve-based state sync.** Object state (position, build progress,
  etc.) is sent as keyframed curves, not per-tick snapshots. If an
  object isn't changing, it costs zero bandwidth. This is also the
  mechanism fog of war uses to gate what a client receives — don't build
  a separate fog-of-war data-hiding system, extend this one.
- **10 Hz simulation tick** (D-020). That is the rate authoritative state
  advances — it is *not* the curve keyframe emission rate or the
  flow-field recompute rate, both of which are lower and tuned
  separately. Don't collapse these into one number: an idle squad must
  still cost zero bandwidth regardless of tick rate. Per-squad update
  cost is budgeted against a 100 ms tick.
- **Squads, not individual units, are the atomic simulation unit** for
  movement and production. Pathfinding, networking, and unit production
  all operate at squad granularity. Don't reintroduce per-unit
  pathfinding or per-unit production queues.
- **Flow-field pathfinding**, computed per squad destination, not
  per-unit A*.
- **Wrapped flat hex grid (torus)**, not a true geodesic sphere. Every
  distance/neighbor/noise calculation must be wrap-aware (modulo
  indexing, toroidal distance via ghost-copy comparison, periodic noise
  sampling). This is a recurring "tax" — expect it in pathfinding,
  vision, minimap rendering, and terrain generation alike.
- **LOD is planned, not a fallback.** Combat resolution, economy
  simulation, and tick rate all vary by proximity to player attention
  (full fidelity near active play, aggregate/statistical far away).
  Global slowdown (PA-style time dilation) is an emergency safety valve
  only — never the primary way this project handles scale.
- **Everything that can be data-driven should be.** Unit stats, civ
  configs, terrain-gen parameters: plain text (`.tres`/JSON), not
  hardcoded. This is what makes the project actually editable via
  Claude Code rather than requiring the Godot editor GUI.
- **Combat is squad-level, stochastic, and server-only** (D-024). A
  squad-vs-squad engagement resolves as aggregate arithmetic over
  `alive`, `damage`, and `attack_interval`, rolled from a seeded RNG —
  never a per-soldier resolution, and never a client-side roll (clients
  receive outcomes, so there is no client RNG to diverge). Casualties
  are integer decrements to `alive`, with fractional damage carried in a
  per-squad accumulator. `alive` is the *only* formation input a death
  changes, so casualty slot reassignment (D-006 clause 3) needs no
  per-soldier identity anywhere — don't reintroduce one to make combat
  feel more "precise". Morale and routing are per-squad values (D-019),
  not per-soldier.
- **Fog of war is still curve gating, and only that** (D-004, D-025).
  Vision is a per-player field, stamped once per player over cells from
  their own squads, then a single O(1) lookup per squad
  (`Vision.is_visible`) — never a per-pair distance test, and
  radius-only: elevation does not occlude in M2. Reveal is a truthful
  pop-in (the same horizon-clipped curve any squad gets, sent fresh, no
  synthetic catch-up). Conceal is an explicit wire event, not an
  inference from a curve going quiet, because a client can't otherwise
  tell "out of vision" from "merely late". A concealed squad becomes a
  client-side ghost — last-known curve and composition, frozen — and a
  ghost must never be folded into `composition_hash()`: the server
  hashes exactly `visible_to(player)`, and a client that counted its own
  ghosts would hash a strictly larger set and desync on a perfectly
  healthy system. Don't build a second data-hiding mechanism anywhere —
  extend this one.

## Project layout

```
--- simulation core (all pure/headless, no scene tree) ---
torus_space.gd           THE wrap-aware hex grid (D-008). Every distance,
                        neighbour and world conversion goes through it.
                        Each method normalises its own inputs, so
                        forgetting to wrap cannot produce a wrong answer.
flow_field.gd            Per-destination flow field (D-007). One field
                        serves every squad heading there — that sharing
                        is the scaling claim, so don't make it per-squad.
state_curve.gd           Keyframed state curves (D-003). Stores points in
                        CONTINUOUS UNWRAPPED axial space; read the header
                        comment before touching it, or seam crossings
                        break in a way that looks like a netcode bug.
curve_replicator.gd      Per-client gating, horizon clipping and the
                        budgeted invalidation scheduler (D-003/D-004).
formation.gd             Derived soldier positions (D-006). All-static
                        and pure — no instance state, by construction.
animation_state.gd       Which clip a soldier plays and at what phase
                        (D-082). All-static, so there is nowhere for the
                        phase accumulator D-006 forbids to live.
cosmetic_offset.gd       Client-only visual jitter. One-way: simulation
                        must never read it back (D-006 clause 2).
squad_sim.gd             The authoritative 10 Hz sim (D-020) over packed
                        arrays (D-009). Ticked by an explicit
                        accumulator, never _physics_process (D-023).
combat.gd                Squad-vs-squad combat resolution (D-024),
                        server-only. A bucket map plus a per-attacker
                        disk scan, not a pairwise squad×squad scan —
                        same cost shape as vision.gd, same reason.
vision.gd                Per-player vision field over cells (D-025).
                        Stamped once per player, then an O(1) lookup
                        per squad — closes the "visible_to() returns
                        every squad" stub D-022 flagged for M1.
terrain_gen.gd           Periodic (seam-continuous) terrain noise, plus
                        `build_fields` — heights, colours, biomes and
                        passability in one pass (D-096). `corner_cells`
                        is THE definition of which three cells meet at a
                        corner, and it returns them sorted so all three
                        agree bit for bit.
terrain_fields.gd        What `build_fields` returns. One object, because
                        surface and colours are indexed identically and a
                        caller that paired them wrongly would just paint
                        the ground wrong with nothing failing.
terrain_chunk.gd         Chunked hex meshing (D-017) — never per-cell.
                        Owns the continuous cell-derived UVs (D-096), the
                        per-cell atlas tile slots the shader blends, and
                        the cliff skirts (D-097).
render_cull.gd           Wrap-aware render culling and LOD selection
                        (D-045). All-static and pure, so the half with
                        the interesting failure mode — which lattice copy
                        of a squad to draw — is testable without a GPU.
world_look.gd            The one definition of the lighting rig — sun,
                        sky, ambient, tonemap, fog (D-086). All-static,
                        guarded by a test that fails if any other script
                        constructs a DirectionalLight3D or Environment
                        directly. client.gd, bench_render.gd and
                        model_preview.gd all build off this now, so the
                        shipping rig and the benchmark rig cannot drift
                        apart the way three hand-copies did before.
hud_layout.gd            Where the HUD's pieces go, for a window of any
                        size (D-061). Scale AND anchoring — either alone
                        looks sufficient and is not. All-static, pure.
                        Also owns the HUD's non-obvious arithmetic: the
                        match clock, the n/cap readout, and the compass
                        dial's geometry (D-063).
scoreboard.gd            Who is in this match, and what this player is
                        ENTITLED to see about them (D-102). All-static and
                        pure. Identity (colour, civ, team) is public and
                        needs no plumbing — it was already on the client.
                        Army size is DERIVED from what the server chose to
                        send, never asked for, so an enemy's total cannot
                        be leaked by a future caller: own and ally counts
                        only, everyone else a dash. Standing (playing/
                        eliminated/victor) is the one thing here that had
                        to go on the wire, because fog makes it
                        underivable.
selection_pick.gd        Which thing a click selected, from every
                        candidate's screen geometry (D-061). Same split
                        as render_cull.gd: the client needs a GPU, the
                        ranking that was wrong does not.
ground_cover.gd          Which decorative props dress a cell (D-100).
                        Same shape as resource_visuals.gd and the exact
                        OPPOSITE of what it dresses: cover is client-
                        derived, NOT fog-gated, and costs nothing on the
                        wire, because a grass tuft leaks no information.
                        All-static and pure. A cell holding a node,
                        building or wall gets none — the caller supplies
                        that fact rather than the module reading sim
                        state.
replay_log.gd            Replays ARE the curve log (D-016), byte-
                        identical to the wire format.

--- networking ---
net_protocol.gd          The one definition of the wire protocol, shared
                        by server, client and bots so they can't drift.
client_state.gd          Everything a client knows, with no rendering
                        attached. The GUI client and the load-test bots
                        both run THIS — so test-load exercises the real
                        client path, and the client's logic is testable
                        headless even though the client itself isn't.
server.gd / server.tscn  Headless authoritative server (D-002).
client.gd / client.tscn  GUI client. Native-only, needs a GPU (D-014).
bot_client.gd            Headless load-test bot. Runs N *virtual*
                        clients in one process, not N processes (memory
                        budget — see D-018).

--- data ---
/units/*.tres          Unit definitions (UnitDef resources) — the MVP
                        roster lives here. Add new units by adding a
                        .tres file, not by writing new unit classes.
unit_def.gd             UnitDef schema — extend fields here when a new
                        unit needs a stat that doesn't exist yet, and
                        record the change in D-010's schema log.
/civs/*.tres           Civilizations as data (D-047). A civ fields a
                        SUBSET of unit archetypes and tunes them its own
                        way, so the same type is not the same troops in
                        two armies. Mechanical differences are declarative
                        knobs EVERY civ has — never a per-civ branch, and
                        a test fails if any .gd file names a civ at all.
civ_def.gd              CivDef schema; civ_roster.gd loads them.
unit_roster.gd          Loads /units in a stable order. Server, client
                        and tests all discover units through this.
/maps/*.tres            MapConfig resources (torus dimensions, squads
                        per player). Height must be even — D-008.
map_config.gd           MapConfig schema.
primitive_unit.gd       One MultiMesh per squad (D-009). Wears an
                        authored model when the UnitDef names one, the
                        tier-1 primitive when it does not.
unit_mesh.gd            Loads authored models, their VATs and their
                        materials. CACHED — a .glb is a scene, and
                        loading one per squad is the M4 `by_id` defect
                        with a bigger constant.
/shaders/*.gdshader     Unit opaque, unit ghost, building static (D-082);
                        VAT sampling shared via a .gdshaderinc. Plus
                        `terrain.gdshader` (D-096): three atlas taps per
                        ground fragment on continuous UVs, which is what
                        a fixed-function material cannot express.
/art/**.py              Committed asset GENERATORS (D-081) — the source
                        of truth for every model and texture. Plain
                        Python; `bpy` is imported only by art/lib/bake.py.
/generated/             Committed build output: .glb, VAT .exr, the
                        terrain atlas, and a manifest whose source hash
                        makes a stale build a test failure.
art/scatter/props.py     The ground-cover props (D-100). Fails its own
                        build on an inside-out part, a prop tall enough
                        to hide a soldier, or one that does not sit on
                        y=0 — the checks a triangle count cannot make.
                        Props carry real glTF MATERIALS, not vertex
                        colours: they are drawn from a MultiMesh, and a
                        MultiMesh overrides COLOR (see art/lib/bake.py).
model_preview.gd         Renders every authored model, animated, and
                        screenshots it. The picture is the point.
cover_preview.gd         The same idea for ground cover: every prop, on
                        generated terrain, with a real squad standing in
                        it so "cover never hides a unit" is looked at
                        rather than asserted.

--- tooling ---
justfile                 The full command vocabulary for local dev,
                        testing, and export. Use these recipes rather
                        than reconstructing godot/steamcmd invocations.
instance-id.sh           THE definition of this checkout's dev-instance
                        identity (D-095): instance name from the git
                        branch, udp port hashed from it. The justfile
                        derives its per-worktree compose project, ports
                        and container names from this — nothing may
                        re-derive it. See "Multi-agent isolation" below.
scenario.gd              Applies a mid-game world (D-098). ALL-STATIC,
                        like formation.gd: a scenario is an opening
                        position, not a participant. Goes through the
                        game's own add_squad/add_building/credit, and is
                        the SAME applier the live server uses.
scenario_def.gd          The scenario schema; scenario_squad.gd and
                        scenario_building.gd are its entries. Offsets are
                        relative to a player's home, so one loadout drops
                        onto any map.
scenario_world.gd        A complete headless world for a GUT test, in one
                        call. Exposes the sim's OWN Vision, never a
                        second one.
/scenarios/*.tres        The shipped mid-game starts. `just scenarios`.
bench_render.gd          Client render benchmark (D-045). NATIVE — it
                        needs a real GPU, and prints which one.
terrain_preview.gd       Headless terrain preview + chunk profiling. The
                        PNG is a TOP-DOWN biome map, so it can show a
                        palette drifting and cannot show how the ground
                        looks — that is terrain_shot.gd's job.
terrain_shot.gd          A rendered picture of the ground in the SHIPPING
                        lighting rig, framed deliberately on the longest
                        stretch of passability boundary on the map
                        (D-096/D-097). Software-rasterised, so it answers
                        "is the picture right" and never "how fast".
replay_info.gd           Reads a replay back and reconstructs state.
game_design_decisions.md The living design doc. Read before deciding,
                        update after deciding.
bootstrap.ps1            Fresh-clone entry point. Fetches `just` into
                        tools/ so the recipes below can run at all.
                        Nothing is installed system-wide.
/tests/*.gd              GUT tests, run headless by `just test-unit`.
                        Each file names the decisions it guards in its
                        header — they exist to make silent architectural
                        drift fail loudly, so read that header before
                        changing what a test asserts.
Dockerfile               Pinned Godot headless image (D-001/D-014).
docker-compose.yml       server / bots / test services. Teardown-scoped:
                        pinned project name, --rm, no restart policy,
                        no named state volumes.
.godot-version           The pinned Godot version. Both the container
                        build and `just bootstrap` read this — bump it
                        here, not in either of them.
/tools/                  Gitignored. Portable `just` and (native runtime
                        only) portable Godot. `just nuke` deletes it.
```

## Mesh pipeline — the tiers, as they now stand

D-011's three tiers are **superseded by D-081**. Tier 1 (primitives) is
still there as the fallback, tier 2 (parametric composition) turned out to
be *how* tier 3 is written rather than a stop on the way, and tier 3 is
built:

- **Authored tier (current):** stylised low-poly, ~300 tris/soldier,
  silhouette first. Generated by committed Python under `art/` driving
  **Blender headless as a library** (`bpy`, a PyPI wheel — no GUI, no GPU,
  no system Blender). `just build-assets` writes `generated/`.
- **Primitive tier (fallback):** `UnitDef.model_id` / `BuildingDef.model_id`
  default EMPTY, and an empty id means "use the capsule". So bots, tests
  and a clone that has never run `build-assets` all still work — a failed
  art build costs fidelity, not the game.

**Both the generators and their output are committed** (D-081). The
generators are the source of truth; `generated/` is committed anyway so a
fresh clone plays without installing anything. Two runs of
`build-assets` must be **byte-identical** — fixed seeds, sorted iteration,
no timestamps — and a test fails if `generated/` is stale with respect to
`art/`.

**Soldiers are animated by a vertex animation texture (D-082), and the
phase is DERIVED, never accumulated.** `phase = fract(t*rate + hash(slot))`,
computed in the shader from `TIME`. That is the whole reason animation is
legal under D-006 clause 1: there is nowhere for per-soldier state to
live. `animation_state.gd` is all-static for the same structural reason
`formation.gd` and `cosmetic_offset.gd` are. **A phase counter advanced by
delta time, or a blend weight carried between frames, breaks it** — those
are integration state in a cosmetic disguise.

Terrain is textured by a **per-biome atlas that MODULATES the vertex
colour** (D-083) — `TerrainGen.biome_color()` is still the single source
of truth, which is what keeps the minimap and the preview PNG from
drifting from the 3D view without either of them being touched. Terrain
UVs come from the **cell**, never from world position, so all nine torus
copies agree by construction.

Three things bought the hard way, all in one milestone:

- **Godot's `detect_3d/compress_to` silently re-imports any texture used
  in 3D with VRAM block compression and mipmaps.** On a vertex animation
  texture that is corruption — neighbouring texels are unrelated vertices.
  Import settings are generated data now, not something remembered.
- **A rebuild is invisible to Godot until it re-imports.** Verifying a
  fresh bake against a stale `.godot` cache gives confident wrong answers;
  `build-assets` ends in an import for this reason.
- **Every `box()` was wound inside-out for a whole milestone.** Nothing
  failed — a small convex object under back-face culling shows its far
  side and the silhouette is identical — but normals derive from the
  winding, so everything was lit by the inverse of the sun. It was only
  visible once a *building* was big enough to see through. **The check
  that catches this class is a picture of something large.**
  (`art/scatter/props.py` now fails its own build on a part whose signed
  volume is negative, which is the same check without waiting for a
  building — but only for props.)
- **A colour that crosses an asset pipeline is not the colour that comes
  out** (D-100). Ground-cover props carry glTF materials rather than
  vertex colours, because a MultiMesh overrides `COLOR`; Godot's importer
  then converts `baseColorFactor` linear → sRGB and NOTHING converts it
  back, so an authored 0.36 rendered as 0.63 and every fern looked
  frosted beside ground painted with the same numbers. `bake.py`
  pre-compensates and a test compares the imported material against the
  authored value in the manifest. Same family as the VAT's silent VRAM
  compression: **assert the value on the far side of the boundary.**

## Multi-agent isolation (D-095) — HARD RULES

Several agents develop this repo in parallel, each in its own worktree,
each launching servers and clients for the owner to look at. Every
checkout is its own **dev instance**: `instance-id.sh` derives an
instance name from the git branch and a udp port from its hash
(20000–29999), and the justfile threads them through every compose
project name, container name, teardown sweep and client `--port`.
`just instance` prints this worktree's identity.

The rules, none of which need remembering because the recipes enforce
them — but which must not be undone:

- **Start and stop instances only through the just recipes, from your
  own worktree.** They are scoped so you structurally cannot touch
  another agent's containers. Never `docker rm`/`docker stop` by hand
  against anything outside your own `edotmw-<instance>` project, and
  never kill a GUI client process you did not start.
- **Never hardcode the shared literals back in** — `-p edotmw`, a fixed
  container `--name`, a `4433` host port or `--port=4433` in a recipe.
  `tests/test_multi_agent_isolation.gd` fails if they reappear. The
  in-container port is still 4433 by design; only the HOST side is
  per-instance.
- **Crossing instances is the owner's explicit call, never a default.**
  `EDOTMW_INSTANCE`/`EDOTMW_PORT` override the derivation when two
  checkouts should deliberately share; do not set them on your own
  initiative.
- **The client's title bar names its instance** (`eDotMW —
  claude-<session>  [host:port]`), which is how the owner tells several
  test windows apart. Launch clients only through the recipes so the
  `--instance` flag is always passed.
- **An agent's quick launch is the dev build:** `just quick-test`
  resolves `SANDBOX=auto` to on for `claude-*` instances (D-077's
  sandbox mode, cheats panel included) and off for the owner's own
  checkout. Pass `SANDBOX=0/1` to override either way.

## Testing — use the justfile, and use it before claiming something works

`just` lives in `tools/` and is **not on PATH** — invoke it as
`./tools/just.exe <recipe>`. On a fresh clone run `./bootstrap.ps1`
first. Recipes call each other via `{{just_executable()}}` for the same
reason; a bare `just` inside a recipe will not resolve.

**Run recipes from a bash shell (Git Bash), not PowerShell.** From
PowerShell, `just` resolves `sh` to WSL's bash and dies with
`execvpe(/bin/bash) failed` before any recipe body runs.

**Every command belongs to an INSTANCE, and a worktree is isolated
automatically** — see "Multi-agent isolation (D-095)" above for the rules.
Isolation is the default: there is no argument to remember, several
agents can run `test-load` at once without touching each other, and
`just instance` prints what this checkout resolved.

**Start mid-game when the opening is not what you are testing** (D-098).
The real opening costs ~150 s before anything downstream of it exists —
one founding party, a 40 s town hall that consumes it, production, then
armies walking across a 128×64 map. A **scenario** skips to a mid-game
world: bases standing, armies in reach, wallets full.

```
just scenarios                     # what exists and what each is for
just test-scenario siege 4 30      # real server + real bots, ~31 s
just test-unit scenarios           # one test file, ~11 s
just test-unit "" within_reach     # one test by name
```

In a GUT test the whole setup is two lines:

```gdscript
var w := ScenarioWorld.build("clash")   # two armies, already in reach
w.tick(2.0)                             # two seconds at the real 10 Hz
```

Three rules come with it:

- **A scenario is applied through the game's own calls** —
  `SquadSim.add_squad`, `BuildingSim.add_building`, `Economy.credit` —
  and `Scenario.apply_player` is the SAME function the live server uses.
  Never add a faster path that builds the world its own way; that is the
  `profile`-sweep blind spot with a new name.
- **A scenario cannot see founding, production or spawn placement**,
  because it skips them. `just test-load 4 120` still plays the real
  opening and is still the gate a change passes before it is called done.
- **`_import` is now skipped when nothing changed.** It prints when it
  skips; `EDOTMW_FORCE_IMPORT=1` forces it. If you ever suspect a stale
  cache, that flag is the first thing to try.

Lifecycle:

- `just doctor` — preflight: runtime prerequisites actually met?
- `just up` / `just down` / `just status` — all scoped to this instance
- `just instance` — this checkout's instance name, udp port and compose
  project (D-095). Read it before believing a failure is yours.
- `just nuke` — full teardown back to pure source. **Deletes `tools/`,
  including the `just` you ran it with** — that's intentional; re-run
  `./bootstrap.ps1` to come back.

Dev loop and tests:

- `just run-server` — headless authoritative server
- `just run-client [ADDRESS] [PORT]` — GUI client for a human to look at.
  **Native only**; needs a GPU (D-014), so it ignores `EDOTMW_RUNTIME` and
  says so if portable Godot is missing. WASD pans (relative to where the
  camera looks), wheel zooms, **Q/E and Ctrl+wheel turn the view**, the
  compass snaps back to north, right-click orders, ESC opens the game
  menu (D-063).
- `just test-client [SECONDS]` — the same client, rendered headlessly via
  Mesa's software rasteriser and checked automatically. Writes
  `artifacts/client-frame.png`; **look at it**, that is the point. Docker
  only. See D-014's 2026-07-29 amendment for why this doesn't contradict
  "the client can't be containerized".
- `just run-bots N [DURATION]` — N virtual load-test bots in one process.
  Requires a server to already be up (`just up`) — it deliberately does
  not start one, because a `run --rm` dependency leaks a container.
- `just test-unit [FILTER] [TEST]` — GUT unit tests, headless *(green:
  691 tests across 46 scripts, measured 2026-08-16)*. FILTER selects
  files by substring, TEST selects one test by name (D-098).
- `just test-scenario [SCENARIO] [N] [DURATION]` — the fast integration
  loop: a real server and real bots starting mid-match from a scenario
  (~31 s at DURATION=15, ~50 s at the default 30, against `test-load`'s
  ~150 s). Fails unless the server's log confirms it actually played the
  scenario.
- `just scenarios` — the shipped mid-game scenarios and what each is for
- `just test-load N DURATION` — full load test: server + N bots for
  DURATION seconds. Checks the bots' exit status, an explicit VERDICT
  line, AND a log scan for engine diagnostics. Tears down via trap on
  success, failure, and Ctrl-C. Prints the per-squad update cost — the
  number to watch — plus how many client/server state-hash comparisons
  ran and how many desynced.
- `just gen-terrain-preview [CHUNK_SIZE]` — terrain PNG into `artifacts/`
  plus chunking cost, and the count of cliff faces the shipped map draws.
  Vary CHUNK_SIZE to settle D-017 with data. The PNG is **top-down biome
  colour**, so it cannot show how the ground looks.
- `just gen-terrain-shot [HEIGHT]` — a RENDERED picture of the ground, in
  the shipping lighting rig, framed on a cliff. Software-rasterised, no
  GPU needed. **Look at `artifacts/terrain-3d.png`.** It exists because
  every number `gen-terrain-preview` prints stayed healthy for two
  milestones while the ground read as a honeycomb of flat hexes, and
  because `test-client` aims its camera at a spawn — walkable ground by
  construction, and therefore the one place a cliff cannot be.
- `just replay-info [FILE]` — read a replay back and reconstruct state.
- `just bootstrap-art` — fetch the pinned `bpy` into a gitignored venv.
  ~1 GB, and ONLY asset work needs it: everything else, including running
  and testing the game, works from the committed `generated/`.
- `just build-assets [ARCHETYPE]` — rebuild models and textures from
  `art/`. Ends in an `--import`, because Godot serves assets from its
  cache and a rebuild it has not imported is invisible.
- `just gen-model-preview [SECONDS]` — every authored model, animated, on
  real terrain, through the REAL path (a `UnitDef`, a `PrimitiveUnit`,
  the shipping shaders). Software-rasterised, so unlike `bench-render` it
  needs no GPU. It renders TWICE and fails if the two frames are
  byte-identical — a frozen VAT would otherwise produce a perfectly
  plausible still. **Look at `artifacts/models-godot.png`.**
- `just gen-cover-preview [SECONDS]` — ground cover (D-100) on generated
  terrain, through the REAL path (`GroundCover`, `UnitMesh`, one MultiMesh
  per model), with a real squad standing in it. Software-rasterised, no
  GPU. Fails if nothing was drawn or if a palette names a model that did
  not load. **Look at `artifacts/cover-godot.png`** — every prop colour in
  `art/scatter/props.py` was chosen off that picture, because a prop's
  near-vertical geometry renders a good deal darker than ground painted
  with the same number.

Every recipe listed is real and verified; none are stubs.

**Any recipe that runs Godot against this project must import first.**
Godot resolves global `class_name`s from the import cache, and without it
scripts fail to parse with a misleading "Identifier not declared in the
current scope" plus a scatter of "cannot infer type" on unrelated lines.

This was previously written as "any new *headless* recipe must depend on
`_import`" — and that wording predicted the wrong set. `run-client` is
not headless, so it was never given the step, and it failed on the first
real launch exactly this way. Headlessness was never the relevant
property; needing global `class_name`s is, and everything needs those.

Note `run-client` cannot use the shared `_import` dependency: `_import`
follows `EDOTMW_RUNTIME`, which defaults to docker and populates
`.godot-container`, while the GUI client is always native (D-014) and
reads `.godot`. It runs a native import inline instead.

**Before reporting a change as done, run the relevant test recipe.**
Given the project's performance targets (40,000 soldiers / ~1,000
squads, 20 players), "it compiles" is not the same as "it holds up at
scale" — use `test-load` for anything touching netcode, pathfinding, or
simulation cost.

**A green run is not the same as a run that happened.** `test-load` once
reported "clean" while every bot had exited non-zero, because it only
grepped for words that didn't appear. Separately, its `desync` scan
matched no code path at all and passed vacuously for the whole of M1,
hiding a live bug in which every client derived soldier positions from a
different squad strength than the server used.

So, three rules, each bought with a real defect:

1. Assert the thing *did* happen, not merely that nothing complained.
   `test-load`'s verdict now fails if zero state-hash comparisons ran.
2. **Observe every new check fail before trusting it.** Perturb the
   thing it guards, watch it go red, then revert.
3. Don't scan for scary words — scan for structured markers. The word
   scan was later fixed again after it failed a good run by matching its
   own success line, "0 desyncs".

**Client/server agreement must be tested through the wire.** A test that
hands both sides the same inputs proves `Formation` is pure — which it
is — and cannot notice the live system feeding them different ones. See
D-006's "necessary but not sufficient" note.

**Numbers can all be right while the picture is wrong.** The first frame
the client ever rendered contained no soldiers, with every numeric check
passing: 12 squads drawn, 384 soldiers derived, zero desyncs. They were
deriving at y=0 and rendering inside the terrain. `just test-client`
exists for this class of bug — and the PNG it writes is meant to be
looked at, not just asserted about.

## Conventions

- **GDScript only — no C# in the shipping build** (D-021). This is a
  yes/no answer, not a preference: don't add a `.csproj`, don't reach for
  the .NET Godot artifact, don't assume the .NET SDK is available in the
  container. If a specific kernel is measured to exceed budget, the
  escape hatch is **GDExtension (C++/Rust) scoped to that kernel** — and
  only on M4 profiling evidence, not on suspicion.
- Godot headless mode (`--headless`) for anything scriptable — server,
  bots, tests, terrain preview generation. Don't assume the editor GUI
  is available.
- New units: add a `.tres` file under `/units/`, don't hardcode stats
  in scripts.
- Any forced binary-only or GUI-only step (hand-sculpted final meshes,
  visual editor-only configuration) should be flagged explicitly as an
  exception, not treated as the default path.

## When something isn't decided yet

Check the "Open Questions / Not Yet Decided" section at the bottom of
`game_design_decisions.md`. If you need an answer to something listed
there to proceed, surface that rather than guessing — these are marked
open because they genuinely haven't been resolved, not because they
were forgotten.
