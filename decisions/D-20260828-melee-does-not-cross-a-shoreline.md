# D-20260828 · 2026-08-28 · Accepted — melee does not cross a shoreline, and a wall is not a shoreline

**Decision:** naval stage 5 (`docs/plans/naval.md` §2.5, cut-list row 5).
`Combat._can_reach_tier` becomes `_can_reach_domain`, and it enforces
**two rules rather than one**:

1. **A shoreline stops melee in BOTH directions.** Land melee cannot
   reach a ship; a ram cannot reach the shore. Ranged crosses either way.
2. **A wall stops melee in ONE direction, exactly as it always did.** You
   cannot melee somebody on top of a wall from the ground (D-076), and a
   wall-top squad CAN melee the attackers at its foot.

`SquadSim` declares `DOMAIN_GROUND`, `DOMAIN_WALL_TOP` and
`DOMAIN_WATER`. Nothing else changes: ships are squads, so `combat.gd`
keeps its bucket map, its disk scan and D-024's arithmetic untouched.

## The naval plan's "same sentence" is not the same sentence

§2.5 says:

> **Melee cannot cross a domain boundary. Ranged can.**
> […] This is the same sentence D-076 already enforces between ground and
> wall-top.

**It is not.** D-076's predicate is:

```gdscript
if target_tier != 1:
    return true
return attacker_tier == 1 or attacker_class == "missile"
```

— which refuses melee *up* onto a wall and permits melee *down* off one.
That asymmetry is the point of the wall: a defender who climbs can fight
the attackers at its foot, and climbing is a defensive choice rather
than a way to remove yourself from the battle.

Implementing §2.5 as written makes the rule symmetric and **takes that
away**. A wall-top squad would become unable to fight the ground.

**No test covered it.** `test_wall_top.gd`'s melee test uses an ARCHER
as the wall-top defender, so it asserts that a ranged defender shoots
back — the melee-downward case is unasserted, and the symmetric version
passes the whole existing suite. Verified by writing it: with melee
refused across every boundary, the only red is the new test in this
stage's own file.

So the plan is followed for water and **not** followed for walls, in the
open. The alternative was a silent behaviour change to a shipped rule,
discovered later by somebody wondering why their wall defenders had
stopped fighting.

## Rejected alternatives

- **The symmetric rule, as §2.5 literally reads.** Above. If the owner
  *wants* wall-tops to stop meleeing the ground, that is a change to
  D-076 and belongs in D-076's file with its own reasoning — not a side
  effect of adding boats.
- **A separate `_can_reach_shoreline` beside `_can_reach_tier`.** Two
  predicates answering "may this attacker reach that defender", called
  from the same two sites, which would come to disagree the first time
  somebody added a domain.
- **Keeping `_can_reach_tier` as a forwarder.** Two names for one rule;
  the next reader would not know which was current. Renamed outright,
  and a test fails if the old name returns.
- **Special-casing rams.** A ship with a short `attack_range` is a ship
  that can only fight other ships. That is a data consequence of the
  roster, and the plan says so.
- **Putting the domain constants in `combat.gd`.** `_tier` is
  `SquadSim`'s field and stage 2 will dispatch on these; a bare `2` in
  `combat.gd` would be a second definition of the same fact.

## Consequences

- **`DOMAIN_WATER` is declared before anything can be in it.** Stage 2
  puts squads there; this stage needs to name the domain it refuses
  melee across. Declaring it early costs nothing and is the alternative
  to a literal.
- **Thirteen tests, every one observed to fail** — including
  `test_a_wall_top_squad_can_still_melee_the_ground`, which is red under
  the plan's literal reading and is the whole argument above expressed as
  a check.
- **The live half is stage 2's.** Nothing puts a squad in
  `DOMAIN_WATER` yet, so these drive the predicate directly rather than
  through a played tick. What stage 5 owes is a rule that is right
  before anything depends on it; a ship actually failing to be meleed is
  stage 2's gate.
- **This branch is on the naval chain and expects a rebase.** It is
  based on stage 1 because stage 2 does not exist yet; the predicate
  takes plain integers and a string, so stage 2's `movement_domain` and
  field dispatch land beside it without touching it.

## Revisit trigger

A domain that is not mutually exclusive with the others — cargo aboard a
ship is the named candidate, and §3 keeps it out of the world entirely
for exactly this reason. If a squad can ever be in two domains, this
predicate stops being a function of two integers and the question
reopens as a decision.
