# D-20260819 · Stances are standing orders: guard, skirmish, hold fire

**Status:** ACCEPTED — workstream 7 of
D-20260818-battle-quality-outranks-player-count. **Relates to:** D-034
(attack-move — an explicit attack order outranks every stance), D-058
(the same ride-along machinery), combat.gd's own idle-pursuit header,
which has named "a per-squad control to opt out" as future work since
the pursuit shipped.

## Decision

One stance byte per squad — three flags, ordered by `C2S_ORDER_STANCE`,
carried in SQUAD_INFO for the panel's benefit but NOT hashed (the
owner/tier family: a fact the client is told, never derives):

- **GUARD** — hold position. The squad opts out of idle pursuit
  (`assign_idle_engagements` skips it) and stands where it was put. It
  still fights whatever walks into reach, and an explicit attack-move
  works exactly as ever.
- **SKIRMISH** (missile squads) — keep the distance. An idle skirmishing
  squad with an enemy inside `SKIRMISH_TRIGGER_CELLS` (3) steps
  `SKIRMISH_STEP_CELLS` (4) directly away, server-side, and keeps
  shooting — kiting as a standing order instead of a click drill. Only
  while IDLE: a player's live order always outranks the stance, which is
  the same suggest-vs-set principle D-065 bought for shapes.
- **HOLD FIRE** — no attacks while held; an explicit attack order
  RELEASES the hold (weapons-free is what clicking an attack means).
  Found at design time: gating on the attack-move flag instead falls to
  D-034's halt, which spends that flag on contact — a held squad
  ordered to attack would fire once and fall silent. Also opts out of
  idle pursuit, since chasing something you will not shoot is theatre.

**Walk/run is deliberately NOT here.** Without fatigue, "run" is the
strictly better speed everywhere — the exact trap charge's expiry
deadline guards. It arrives with workstream 11 as fatigue's spending
control, and this entry says so rather than shipping a free lever.

## Rejected alternatives

- **Stances in the composition hash.** They change no derived geometry;
  hashing them buys nothing and makes every toggle a desync surface.
- **Skirmish as client-side micro** (the client auto-clicking). The
  server is the authority (D-002), and a stance the server does not
  enforce is a stance a laggy client does not have.
- **A single enum instead of flags.** Guard+hold-fire is a real posture
  (a silent picket); an enum forbids it for no reason.

## Revisit trigger

If skirmish stepping fights the separation rule or walls (the D-067
opposed-arithmetic family), the trigger is a red test in THOSE files —
the step goes through the ordinary move order precisely so every
standing movement rule applies to it. AI use of stances is behaviour
work under the ai-opponent increments.
