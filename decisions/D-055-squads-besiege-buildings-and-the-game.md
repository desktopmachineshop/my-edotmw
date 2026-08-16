### D-055 · 2026-08-02 · Accepted — squads besiege buildings, and the game became winnable
**Decision:** Squads damage enemy buildings, via
`Combat.resolve_squads_vs_buildings` — the mirror of the
`resolve_buildings` pass that already existed. Defenders come first: a
squad with an enemy SQUAD in range never spends its attack on a
structure. A building under construction is a legitimate target. Damage
is continuous rather than a casualty roll, and skips `bonus_vs`.

**Rationale:** `BuildingSim.damage()` was fully written — it even marked
the building dirty so destruction would replicate through the path the
server already used — and was called by nothing outside its own tests
for two milestones. Buildings were indestructible.

The consequence was larger than the omission sounds. D-033 ends a match
by elimination; a town centre that survives everything keeps producing
replacements; so **no match could be won by anybody**, human or AI. Every
`ai-ladder` run drew at the time cap, and that was read as an AI weakness
through several rounds of AI work on massing, target choice and scouting.
None of it could have mattered.

**How it was found, because the method is the transferable part:** making
enemy buildings the AI's attack objective produced a ladder result
*identical to the previous one in every statistic to three significant
figures*. That is not a small effect, it is no effect — so the new branch
could not be executing. Instrumenting the AI with `enemy_buildings_seen`
settled it in one run: legion finds all three of its opponent's
buildings, attacks 18–21 times, and destroys none.

**This is the third declared-and-unread mechanic this project has
shipped,** after `UnitDef.cost` and `BuildingDef.cost`. The shape is
always a field or method with no caller, and it survives because nothing
fails: the game runs and quietly lacks a rule. A test suite cannot see it
— the code under test is correct. **A grep for uncalled public members is
worth more here than another assertion.**

**Rejected alternatives:**
- *Reuse `_resolve_attack`.* It is steeped in squad assumptions —
  fractional casualty carry, morale, rout, `armour_class`. A building has
  none of those. Duck-typing `BuildingSim` through squad-shaped functions
  is the subtle-bug factory `resolve_buildings` already declined.
- *Carry a fractional accumulator.* D-024's accumulator exists because
  casualties must be whole soldiers. `max_health` is a float, so the
  problem does not arise.
- *Apply `bonus_vs`.* `BuildingDef` has no `armour_class`, so D-032's
  counter triangle has nothing to key on and the lookup would silently
  read 1.0 while looking meaningful.

**Consequences:** the ladder went from **0 of 3 decided** to **2 of 3**
with no AI change whatsoever — same code, same seeds. A defended base is
now a real objective, and a garrison now matters, because an attacker
cannot ignore it.

Cost, measured by `test-load 20 120`, all at 120 squads:

| | µs/squad | combat |
|---|---|---|
| pass off | 77.02 | 5.99 |
| pass on, `distance()` per pair | 92.10 | 24.24 |
| pass on, bucketed | 76.50 | 7.33 |

The first version scanned every building for every squad — ~7,700
`distance()` calls a tick — on the reasoning that buildings are rare
enough for a scan to beat a bucket rebuild. Measurement said otherwise.
**That is the fourth appearance of one defect**, after `distance()` per
candidate cell in vision (232 → 15 µs/squad, M2), `UnitRoster.by_id`
walking the filesystem per produced squad (858 ms in one tick, M4), and
terrain noise sampled per soldier per frame (M5). A hex disk is
translation-invariant on a torus: reach for `TorusSpace.disk_offsets`
before reaching for `distance()`.

Two things left open and deliberately not dressed up:

- **The 40.8 → 77 µs/squad rise against M4's figure at the same squad
  count is not this change** — it was measured with the siege pass
  disabled, so it belongs to M6's civs/teams/economy work and is still
  unattributed.
- **Worst-tick figures from this session are untrustworthy.** A run with
  strictly *less* work reported 146 ms while the fuller run reported
  52 ms, because the host was building containers throughout. Both runs
  dropped zero ticks.

**Revisit trigger:** anything wanting a different attack rate against
buildings than against squads. Defenders-first is currently enforced
twice — by `_engaged` and, implicitly, by both passes sharing one
`_last_attack_tick` clock — and the test only goes red when *both* are
removed. Splitting that clock silently removes one of the two.

---
