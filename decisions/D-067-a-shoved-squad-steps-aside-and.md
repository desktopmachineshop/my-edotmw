### D-067 · 2026-08-04 · Accepted — a shoved squad steps aside, and one squad cannot take a base
**Decision:** Two things, found together because the second could not be
delivered without the first.

1. **`TorusSpace.disk_offsets` is sorted nearest-first.** It enumerated
   dq-major from `-radius`, so its first entries are the FAR edge of the
   disk. Three callers walk it looking for "the nearest free cell" and
   each silently took one up to `radius` away, always in the same
   direction.
2. **The anti-rush rule the owner asked for**, now that the first fix
   makes it expressible: **one squad of any starting troop must fail
   against a defended building; two must succeed.** Town centre damage
   **45 → 60**; tower **80 → 85** and **1400 → 1700 HP**.

**How the ordering defect showed itself.** Two militia squads ordered
onto one town centre dealt 1560 damage in 30 s against a single squad's
1461 — the second squad was displaced four cells by `_separate_arrivals`,
which is outside a 1.9-range unit's one-cell reach, so it stood there for
the rest of the match doing nothing. Ranged units never showed it: they
were displaced within their own range and kept firing, which is why the
symptom read as "buildings feel weak" rather than "half my army is idle".

`_free_cell_near`'s doc comment said "the nearest cell"; `_approachable`
said "walks outward"; `_spawn_cell_near` said "prefers to stand a new
squad right at the door". All three were describing an order the table
did not have. Sorting it (cached per radius, ties broken by (dq, dr) so
it stays a total order for replays) made all three true at once, and the
two-squad damage went to ~2x on the first run.

**The rule, and what it cost to find.** Measured across every unit in the
roster, both buildings, one squad and two, 600 s cap:

| | result |
|---|---|
| town centre 60 | no unit takes it solo; every line troop takes it with two |
| tower 85 / 1700 HP | no unit takes it solo; every line troop but one takes it with two |

**Two exceptions, both deliberate and both tested.** *Founders* are
excluded from the two-squad rule: a player has exactly one founding party
and spends it raising the town hall (D-031), so two of them is not a
situation the game can produce. *northmen_skirmishers* cannot take a
tower with two squads — they are the cheapest, flimsiest unit (30 food,
42 HP a man, 1260 to a squad), the tower outranges them 5 cells to 3, and
each shell kills two of them at once, so they rout (threshold 36) and
spend the fight cycling. **No tower HP/damage pair exists that stops a
lone militia squad and still loses to two skirmisher squads** — swept
across (1400–2400 HP) x (75–140 damage). The roster spans 1260 to 3360
effective squad HP; one flat number cannot separate those two cases.
Wanting it needs a mechanic (siege equipment, a damage type), not another
number. A test asserts skirmishers still do real damage to a tower, so
the carve-out cannot quietly become "harmless".

**Rejected alternatives:**
- *Tuning damage without fixing the ordering* (rejected — impossible: two
  melee squads were not twice one squad, so no value could satisfy both
  halves of the rule).
- *Giving `disk_offsets` a second, sorted table* (rejected — two tables
  and a choice at every call site, when no caller wants the unsorted one).
- *Stopping a lone squad by raising building HP alone* (rejected — HP
  lengthens the fight for attacker and defender alike; it moves both
  halves of the rule the same direction).

**Consequences:** every "nearest cell" search in the sim changed
behaviour — production spawns, approach cells, arrival separation — all
in the direction their comments already claimed. Sieges are now
manpower-limited by the contact ring, which is realistic and which nobody
has designed: a building can only be surrounded by so many squads, and
the rest queue behind. Ladder decidability is the thing to watch (D-055).

**Decidability held** (`just ai-ladder 3 600`): **2 of 3 decided, 1 draw
at the cap**, one win each civ, first attack ~195 s — the same 2-of-3
D-055 reports for the pre-change baseline. An earlier 3-of-3-draw reading
was taken at a **420 s** cap and was not comparable: stronger defence
lengthens matches, so a cap that used to be generous now truncates them.
**When a change makes matches longer, the cap is part of the measurement**
— re-read a ladder result against the cap it was taken at before
concluding anything from it.

**Measured after, through the wire** (`just test-load 4 120`): clean
verdict, 0 desyncs over 476 hash checks, `buildings_known=7`, and
**59.60 µs/squad at 52 squads** against 60.72 for the same scenario
before — the sort is per radius and cached, so it costs nothing per call.
Worst tick 76.6 ms, 0 dropped ticks.

**A note on how nearly this was misattributed.** Two load runs failed
first, both reporting `buildings_known=0` with byte-identical numbers,
and the obvious suspect was this change. It reproduced with the change
reverted, and server-side instrumentation printed nothing at all —
because a second server container held port 4433 and the bots were
reaching it, not the one under test. The rule from D-038's amendment
applies to the harness as well as the code: **read the log before
theorising, and if the instrumentation is silent, doubt the setup before
the diagnosis.**

**Revisit trigger:** if a later unit lands outside the measured band —
tankier than legion_heavy or flimsier than skirmishers — the single flat
`BuildingDef.damage` stops expressing this rule and needs to become
something that scales.

---
