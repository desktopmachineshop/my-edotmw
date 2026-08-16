### D-046 · 2026-08-02 · Accepted — M6's exit criteria
**Decision:** M6 is **"a civilization is data"** — proved by a second
civ, a lobby that lets people choose one, and AI players an admin can
seat. Written before the code, per D-043's standing rule.

**The governing constraint, because two of the answers pull against each
other.** M6 wants asymmetry that is *real* — unique units, different
stats, and different mechanics — and it wants adding a civ to need no
new code. Mechanical asymmetry is exactly the thing that normally becomes
`if civ == "romans"`, and the third civ then needs a programmer.

So the rule for this milestone: **mechanical asymmetry is expressed as
declarative parameters the engine already interprets, never as a per-civ
branch.** A civ that wants a genuinely new *mechanic* is a schema
addition (logged against D-010) implemented generically for every civ —
one more knob everybody has, which one civ happens to turn. That is what
keeps "a mix of all three" and "data, not code" from being contradictory,
and criterion 3 below is what makes it falsifiable rather than an
intention.

**The criteria:**

*Civilizations as data (D-047)*

1. A `CivDef` resource in `/civs/*.tres` defines a civ: display name,
   which units and buildings it may field, starting stockpile, and its
   declarative modifiers. Server, client and tests discover civs through
   one loader, the way `UnitRoster` does for units.
2. A **second civ exists and is genuinely different**: at least one
   exclusive unit the other cannot build, different stat tuning on the
   shared core, and at least one mechanical difference expressed purely
   as `CivDef` data.
3. **The falsifiable one.** A test asserts that **no `.gd` file mentions
   any civ id**. Adding a third civ must require only `.tres` files. This
   is the criterion the whole milestone turns on, and it is trivially
   observed to fail by hardcoding one civ id anywhere.
4. Production, construction and the roster all filter by the acting
   player's civ, server-side. A player cannot build another civ's units,
   and a test proves the server refuses it rather than the UI merely
   hiding it (D-002 — the client is not trusted).

*Lobby, admin and AI players (D-048)*

5. A lobby phase with **seats**: each seat has an occupant (human, AI, or
   empty) and a civ choice. The match starts when the admin starts it,
   not when a connection count is reached.
6. **One admin**, the first human to connect. If they leave, it passes to
   the next human deterministically. Only the admin may add or remove AI
   players, set an AI's civ, or start the match.
7. **Each human picks their own civ**, and the server enforces that: a
   client changing another seat's civ is refused, and a test proves it.
8. **"Random" is always an option**, resolved at match start, **uniform
   across civs** — no weighting toward any civ for now. Resolution is
   seeded so a replay reproduces the same draw (D-016). A test asserts
   the distribution is flat over many draws, and that the same seed
   yields the same civ.
9. **AI players are server-side and see only what a human in their seat
   would see.** They read the world through the same `visible_to(player)`
   gate that gates replication (D-025), so an AI cannot read through fog.
   A test proves an AI's knowledge is a subset of its vision — the same
   shape as D-026 criterion 6's fog check, and for the same reason: an AI
   that cheats is not a test of the game.

*It has to work*

10. `just test-load` runs a match with **both civs present**, and the
    verdict fails if either civ never fielded a unit — a run where
    everyone happened to be one civ proves nothing about the second.
11. Replays reconstruct a match including civ assignment (D-016).
12. `just test-unit` green; `just test-client` green and the PNG
    inspected; `just test-load 20 120` still clean with zero ticks over
    D-020's budget.
13. Every new check **observed to fail** before it is trusted (D-022).

*The question M3 left open*

14. **A human session against AI players of the other civ**, judged on
    whether the asymmetry reads as interesting rather than merely
    different. This closes D-027's last criterion, which has been
    outstanding since M3 and which no automated check can answer.

**Rejected alternatives:** Stat-tuning-only asymmetry (rejected — it
would prove the data pipeline while telling us nothing about whether the
architecture supports asymmetry anyone would notice). Per-civ code
branches (rejected — it makes civ 3 a programming task and quietly
converts D-015's "4-6 civilizations at launch" into six engineering
projects). Assigning civs by slot with no lobby (rejected — the lobby is
also where AI players get seated, and AI opponents are a shipped feature
of this game rather than test scaffolding).

**Consequences:** `bot_client.gd`'s role splits. It stays the load-test
harness; the *in-game* AI is a separate, server-side thing that occupies
a seat. Those are different jobs and conflating them would give the load
test a stake in AI quality.

**Revisit trigger:** If criterion 3 cannot be met without contorting the
data model — if some mechanic genuinely resists being a parameter — that
is worth knowing early. Record the mechanic, take the code branch
deliberately, and amend this entry rather than pretending the rule held.

---

**Audited 2026-08-02 — 13 of 14 met; the last one needs a human.**

| # | Verdict | Evidence |
|---|---|---|
| 1 | Met | `CivDef` in `/civs/*.tres`, `CivRoster` loads them |
| 2 | Met | Northmen field skirmishers and no heavy foot; Legion field heavy foot and no cavalry; shared archetypes tuned apart |
| 3 | **Met** | no `.gd` outside `tests/` names a civ; observed failing by putting one id in a comment |
| 4 | Met, and structurally | the wire carries an ARCHETYPE, so a client cannot name another civ's unit at all |
| 5 | Met | seats with kind, civ, team |
| 6 | Met | first human is admin, passes to the lowest remaining |
| 7 | Met | server-side; a player changing another seat's civ is refused |
| 8 | Met | uniform over 4,000 draws, seeded, resolved at start |
| 9 | **Met, and structurally** | AI is a client without a socket (D-051) |
| 10 | Met | `CIVS_FIELDED 2 of 2 — legion=50, northmen=70` at 20 players; observed failing when forced to one civ |
| 11 | Met | `replay-info` reports `Player 1 = legion, Player 2 = northmen…` |
| 12 | Met | 339 tests; `test-load 20 120` clean, 0 of 1,323 ticks over budget; `test-client` clean **and the PNG opened** |
| 13 | Met | every new check perturbed and watched to fail |
| 14 | **Outstanding** | needs a human at the wheel |

**Criterion 12 is the one worth reading twice, because it nearly passed
while broken.** The capture reported `ok` — 96 soldiers, 97 distinct
colours, zero desyncs — over a frame containing **no terrain at all**.
D-049 made the client wait for map settings before generating the world,
and those were only sent when an admin started a lobby; a server without
a lobby never sent them. Every number was identical to a healthy run,
because the HUD and the soldiers were genuinely fine. Only the world was
missing.

Two things came out of it. The settings are now sent from
`_admit_player`, which both ways of starting a match go through. And the
capture's verdict asserts the terrain was actually built — a check whose
failing state was not simulated but *observed*, since the previous run
produced exactly it.

The lesson is one this project keeps paying for and had written down
already: **"a green run is not the same as a run that happened", and a
green verdict is not the same as a correct picture.** The recipe's own
docstring says the PNG "is meant to be looked at, not just asserted
about" — and it was not looked at for three commits, which is precisely
how long the regression survived.

**Two things deliberately not done**, recorded so they are choices rather
than oversights: seats cannot be opened or closed (a slot is a human who
joined or an AI the host added), and the AI is not good — it founds,
gathers, trains and attacks the nearest enemy it can see, with no
scouting, no expansion and no use of the counter triangle it is subject
to.

---
