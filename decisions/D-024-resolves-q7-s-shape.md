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
