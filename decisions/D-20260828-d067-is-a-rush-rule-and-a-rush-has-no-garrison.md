### D-20260828 · 2026-08-28 · Accepted — D-067 is a RUSH rule, and a rush has no garrison

**Decision:** D-067's pair rule — *two squads of any line troop take a
defended building* — is **scoped to a building with no troops standing at
it**, and says so. A garrisoned base is not required to fall to two
squads, and that is the design rather than a gap in it.

Two clauses come with the scoping, because a scope without a floor is
just a weaker rule:

1. **A garrison must not make a base invulnerable.** With the attack
   re-tasked as a player or the AI does, the roster's heavy line troops
   take both buildings through a screen.
2. **"Defended" now means two measurable things and both are tested.**
   `tests/test_siege_against_a_garrison.gd` measures the garrisoned case;
   `tests/test_buildings.gd` keeps measuring the ungarrisoned one. Whichever
   numbers D-067's successor carries, both conditions are now measured
   rather than one.

**Rationale.** From #227: D-067's rule is only ever measured against a
building with no troops anywhere near it — `_rush_cost` places the
building and the attackers and nothing else. So "defended" in those test
names means *the building shoots back*, while in a match it also means
*somebody is standing there*, and the issue reported the rule reversing
under the second reading.

**Re-measured against PR #222's re-derived numbers** (town centre 2400,
tower 1250), 11 line troops x 2 buildings, one screening `gildedreach_levy`
on the approach:

| | razed | building HP left |
|---|---|---|
| no garrison | **22 of 22** | 0 |
| one screen, BEHIND the building | **22 of 22** | 0 |
| one screen, on the approach | **0 of 22** | **full, every time** |
| three squads against that one screen | 0 of 22 | full in 20 of 22 |
| one screen, attack re-issued every 5 s | **6 of 22** | 0–1463 of 2400, 0–1250 of 1250 |

Three things fall out of that table, and only the first is about balance.

**The screen INTERCEPTS; it does not add damage.** The behind-the-building
control reproduces the undefended result exactly, 22 of 22. So this is a
fact about position, not about the defender having more army — which
matters, because those two want completely different fixes.

**Most of "a screen is absolute" was a fixture artefact, and it is now
its own issue (#249).** D-034 halts an attack-move on contact and
*nothing ever resumes it*: `stop()` clears the flag, and
`assign_idle_engagements` pursues squads and has no building arm. So a
squad that halted three cells short, killed the screen, and went idle
stands there for the rest of the match. Re-issuing the identical order
every five seconds — which is what a player does and what `ai_player.gd`
already does on a cooldown — takes the table from **0 of 22** to **6 of
22 razed with real damage almost everywhere else**. Nothing else differs
between those two rows. The permanence was the bug; the defensive value
is real.

**And what remains after that is a defender being rewarded for
defending.** Two squads of a mid-roster line troop, re-tasked, still lose
to one screen plus the building's own fire. A ~45 RP screening squad
buying that much is a strong return, and it is on the same axis as #219
(counters not felt squad-for-squad) and #220 (`gravesworn_levy` leading
both power and cost-efficiency) — cheap line infantry is the roster's
best purchase in several unrelated measurements at once. **That is a
roster question and is deliberately not answered here**, because
answering it by moving the tower and town-centre numbers would move
D-067's ungarrisoned rule at the same time, and those numbers were
re-derived nine hours ago in `D-20260827-a-buildings-hp-is-one-knob-and-
the-rule-needs-two`.

**Rejected alternatives:**
- *Requiring two squads to take a garrisoned base* (rejected — it makes a
  garrison worthless, and the only lever that would deliver it is
  building HP, which is D-067's ungarrisoned rule wearing a different
  hat. A defender who spends 45 RP on a picket should get something for
  it.)
- *Naming the siege train as the answer and asserting it* (rejected FOR
  NOW, and it is the most likely eventual answer — breaker, engine, ram
  and bombard are already carved out of D-067 for exactly this class of
  reason. Not asserted yet because their behaviour against a screen has
  not been measured, and #227 asked for the rule's scope rather than for
  a new one.)
- *Fixing the attack-move resume here* (rejected — it is a live gameplay
  defect that reaches players and the AI, it wants its own change and its
  own encounter test, and folding it into a decision about a rule's scope
  would bury it. #249.)
- *Adding the defender variant to `_rush_cost`* (rejected — worker 86 is
  re-deriving `test_buildings.gd` on a branch based on PR #222, and two
  agents editing one fixture is the collision the orchestrator split this
  work to avoid. Its own file also makes the two claims separable, which
  the #152 post-mortem is a live argument for.)

**Consequences:** D-067's pair rule keeps its meaning and gains a stated
boundary. `test_siege_against_a_garrison.gd` deliberately does NOT assert
that every line pair damages a garrisoned building — `thornwood_levy`
against a garrisoned tower does zero even when re-tasked, because the
tower outranges it and kills it on the approach. Asserting the general
case would have been a guard that fails on an honest roster; the file
asserts the invulnerability floor on the heavy troops, where the answer
is stable.

**Measured:** the table above, from `tests/test_siege_against_a_garrison.gd`,
native runtime (docker OOMs on this host, #153/#223). Combat is pure
GDScript over a seeded RNG (D-024) and reads no imported asset, so the
runtime does not bear on it. `just test-unit siege_against` — 4 tests
passing.

**Revisit trigger:** if the attack-move resume in #249 lands, **re-run
this table** — the re-ordered column becomes the ordinary column, and the
6-of-22 figure is what the rule's floor was set against. And if the
roster question behind #219/#220 is answered by changing what cheap line
infantry costs or does, the garrison case moves with it and this scope
should be re-derived rather than assumed to have survived.

---
