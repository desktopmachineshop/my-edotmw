### D-069 · 2026-08-04 · Provisional — the epoch ladder: five rungs, antiquity to high medieval
**Decision:** **Five epochs**, spanning antiquity to the high medieval
period. The ladder is **shared by every civ** — same count, same gate
shape — and civs differ in what each rung *contains*, never in its
structure.

**The filter every rung had to pass: it must name a new verb, not a
bigger number.** A rung whose honest one-line justification is "the
stats go up" was cut rather than rewritten.

| # | The epoch is when… | Verb | Player time |
|---|---|---|---|
| 1 | …a **place** becomes possible. Founding party, first town hall, gatherers, levy foot. | settle | 0–15 |
| 2 | …a **standing army** becomes possible. Barracks-line specialists; the counter triangle arrives whole. | field | 15–33 |
| 3 | …**combined arms and holding ground** become possible. Cavalry, missile specialists, towers and claimed ground. | hold | 33–55 |
| 4 | …**siege** becomes possible. Fortified ground becomes attackable again; heavy horse. | break | 55–75 |
| 5 | …**elite and scarce** troops become possible. Knights, per-civ signature units, the castle tier. | decide | 75+ |

**Epochs 3 and 4 are a matched pair and must ship together.** Epoch 3
makes ground holdable; epoch 4 makes it breakable again. Shipping 3
without 4 produces the *turtle-to-last-epoch* failure in its purest form
— a game where the correct move is always to fortify and wait.

**The advance gate is data, not code:** a new `/epochs/*.tres`
(`EpochDef`) carrying index, display name, `cost_*`, `research_time` and
prerequisite building ids. Researched at a town centre, occupying it for
the duration. Same reasoning as D-010 — the pacing lever most likely to
need a hundred tuning passes must be editable as text, and **no script
may name an epoch** any more than it may name a civ (D-047).

**The gate's job is to create the bank-versus-army fork in D-068's row 2**,
so it has to cost enough that paying it visibly means not fielding troops
for a stretch. Provisional, and explicitly to be replaced by telemetry:

| Advance | food | wood | gold | stone | research |
|---|---|---|---|---|---|
| 1→2 | 500 | 300 | — | — | 90 s |
| 2→3 | 800 | 500 | 200 | — | 120 s |
| 3→4 | 1200 | 800 | 500 | — | 150 s |
| 4→5 | 1800 | 1200 | 900 | 400 | 180 s |

Sanity check against measurement rather than feel: Legion banked a peak
of 2,480 with no epochs to spend it on (D-056). The 4→5 advance is
deliberately priced above that peak, because a stockpile that can absorb
an advance without a decision is not a gate.

**Scope fences — what this milestone does NOT add**, so that the ladder
is not read as licence: no naval, no heroes or unique-hero mechanics, no
campaign layer, no per-civ *mechanics* beyond knobs every civ has (D-047),
and **no wall system**. Epoch 3's "hold" is delivered by towers,
`no_build_radius` claimed ground (D-062) and building health, all of which
exist. A real wall system is a substantial piece of pathfinding and
rendering work and needs its own decision; if epoch 3 proves hollow
without it, that is the trigger to open one.

**Rejected alternatives:**
- *Four epochs (AoE2's count).* Rejected — historically produces 25–45
  minute matches; reaching 90 would need each rung stretched well past
  the point where its content stays interesting.
- *Six.* Rejected — a sixth rung could not pass the new-verb filter
  without either splitting siege in two or reaching into gunpowder, which
  the chosen span excludes.
- *Per-civ epoch counts or asymmetric ladders.* Rejected — a balance
  problem of a different order, and it breaks the shared advance gate
  that makes "who is ahead" legible to both players and the AI.

**Consequences:** the archetype vocabulary grows from 8 to roughly 25–30.
D-047 binds the client's train keybinds to *archetype*, so that table
stops fitting on a keyboard — the UI must become epoch-scoped. This is
the *unlock overload* failure mode and D-074 owns detecting it.

**Revisit trigger:** any rung that telemetry shows is entered and left
without the player's behaviour changing is not an epoch, it is a stat
bump, and should be merged into its neighbour.

---
