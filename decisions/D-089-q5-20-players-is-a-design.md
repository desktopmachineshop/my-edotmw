### D-089 · 2026-08-14 · Accepted — Q5: 20 players is a design target, and what M8 owes it

**Decision (the owner's call, 2026-08-14):** 20 concurrent players is a
**design target** — the product's headline match, not merely the ceiling
the architecture was sized against. What that obliges, scoped honestly:

- **Discovery:** Steam lobby browser plus friend invites, mapped onto
  the existing lobby (D-048/D-050 — seats, teams, civs, AI). **No
  skill-based matchmaking service** — discovery is lobbies, not MMR
  queues; a matchmaker is a standing service with a population
  prerequisite this game does not have and M8 must not pretend it does.
- **Fill:** a 20-seat match must start without 20 humans. AI players
  (D-051) fill empty seats — already real (`just run-server AI=3`), the
  lobby already seats them.
- **Resilience:** drop-OUT hands the army to an AI (D-090); drop-IN is
  D-090's repossession — a returning human reclaims their own seat, and
  a NEW human may take over an AI-held seat mid-match through the same
  machinery. That last is what makes a 20-player match fillable in
  practice rather than only at the lobby screen.

**Rationale:** the alternative reading (engineering ceiling, design for
2–8) was recommended and declined. Taking 20 seriously as design means
the fill/resilience machinery above is core product, not tooling — a
20-human lobby that dissolves on its third disconnect is not a 20-player
game. Note the architecture side owes nothing new: D-018/D-020's budgets
were always sized at 20, and D-042 measured transport at 20.

**Rejected alternatives:** matchmaking service (above); spectator-slot
drop-in (observers are cheap under D-003 — a spectator is a client with
maximum vision — but it is scope, and nothing in the 20-player claim
needs it; noted for later, not built in M8).

**Consequences:** M8's headline verification (D-094 criterion 8) is a
20-seat match through Steam networking with real remote humans in it.
The per-connection-ownership defect family (D-038's amendment) becomes
seat-identity work in D-090 — binding by SteamID, not connection.

**Revisit trigger:** if real playtests show the fun ceiling is well
below 20 (coordination, readability, pacing), the design target moves
and this entry is superseded — the engineering ceiling stays where
D-018 put it either way.

**Amended 2026-08-18**
(D-20260818-battle-quality-outranks-player-count): the trigger above is
effectively pulled, from a direction it did not anticipate — the owner
priced battle quality above headcount rather than finding 20 un-fun.
The design-target number is now an output of that programme's measured
result. Everything else here stands: discovery, AI fill, drop-in/out
resilience and SteamID repossession are needed at any headline count.

---
