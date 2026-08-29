### D-20260828 · 2026-08-28 · Accepted — a player may concede, and conceding is a cause of defeat rather than a second definition of it

**Decision:** A player in a running match may **surrender**. Surrender
razes everything that player owns — squads and buildings — and D-033's
ordinary defeat rule notices on the next tick.

- `C2S_SURRENDER`, **no payload**: who is conceding is read from the
  connection it arrived on, exactly as `C2S_LEAVE_MATCH` does.
- Server-validated through the same shape every other player-level
  command uses: a known connection, a RUNNING match, and a player who is
  not already out. A refused surrender says why (D-034).
- `BuildingSim.eliminate_player` is added beside `SquadSim`'s, razing
  through the existing `damage()` path so the destruction replicates like
  any other razing rather than through a second mechanism.
- `server: MATCH_SURRENDER player=N` is a structured marker, so a harness
  can tell a conceded match from an annihilated one.

**Explicitly OUT of scope**, and named here so they are not read as
forgotten: **a time limit / score victory, and alternative victory
conditions** (economic, territorial, wonder). #279 asks for surrender
first and calls those follow-ons. They are the harder half — a score needs
a definition of who is *ahead*, which this game has never had to compute.

**Rationale.** Elimination is currently the only exit (D-033). At D-056's
1–2 hour target that means a player who has lost has no honest way to
stop, and every playtest runs to the bitter end. The cheapest real fix is
the one every RTS has.

**The design question is not "how does a match end" — it is "how many
definitions of defeat are there".** D-033's answer is one:

> *no living squads AND no living buildings.*

and `server.gd`'s disconnect handler already states the pattern this
follows:

> *"An abandoned army does not get to keep standing on the field. Wiping
> it is the CAUSE of defeat; MatchState's ordinary rule notices the effect
> on the next tick, so 'defeated' keeps exactly one definition."*

So surrender adds **no new elimination path, no new victory path, and no
new field on `MatchState`**. It razes, and the rule that already exists
does the rest. Everything downstream — `standing_of`, the D-102
scoreboard, `_check_victory`'s team clause (D-050), `MATCH_ELIMINATED`,
`MATCH_OVER`, `MATCH_RESULT`, the ladder's per-match reporting — works
untouched, because none of them learn a new concept.

**Why it razes the base as well as the army, which is the one real design
call here.** Three reasons, in order of force:

1. **Otherwise it does not work.** D-033's rule is an AND. A surrendering
   player whose town centre still stands is not eliminated, so the match
   does not end, so the surrender did nothing. Measured on the disconnect
   path, which has exactly this gap today: after the wipe, `squads=0
   buildings=1 eliminated=false phase=RUNNING`. Filed as **#292**.
2. It is what conceding means. A player who has stopped playing must not
   leave a base on the map producing, blocking ground and claiming
   territory (D-062).
3. It keeps surrender and disconnect the same act with different
   politeness, which is what they are.

**Rejected alternatives:**
- *Mark the player eliminated in `MatchState` directly and leave their
  forces standing* (rejected — that is a second definition of defeat, and
  it leaves an army with no owner fighting on. D-033's whole point is one
  definition, and this project has paid for second definitions
  repeatedly.)
- *A `surrendered` flag beside `eliminated`* (rejected — every reader of
  standing, victory and the scoreboard would need to learn it, and each
  is a place the two can disagree. The one thing that genuinely cannot be
  inferred is the DISTINCTION between conceding and being wiped out, and
  that is carried by a log marker for harnesses rather than by simulation
  state.)
- *Requiring an in-game confirmation before the command is sent*
  (accepted in spirit, placed in the CLIENT: the server must not be the
  thing that decides a player meant it, and a confirmation the server
  enforced would be a second round trip for a decision the player has
  already made. The menu asks; the wire states.)
- *Team surrender — one player concedes for the side* (rejected — a
  player may only concede for themselves. Allies keep playing, and
  `_check_victory`'s `_all_allied` clause already ends the match when the
  last of a side goes. Anything else lets one player end another's match.)
- *AI surrender* (out of scope, deliberately: the plumbing supports it —
  an AI is a client without a socket (D-051) and can send the same
  command — but *when* a computer should concede is a behaviour decision
  needing its own measurement, and a badly judged one would make the
  ladder shorter and less informative rather than more.)

**Consequences:** a surrendering player's buildings are razed, which
generates ordinary building-destroyed replication — clients need no new
handling. `just ai-ladder` gains a second way for a match to be decided
rather than truncated, which is directly upstream of
`D-20260828-a-harness-asserts-the-match-ended`: that entry made the ladder
assert matches END, and this gives a losing side a way to end one. A
ladder run's duration therefore becomes even less predictable from
`MATCHES x SECONDS`, which is already recorded there.

**A note on what surrender does NOT do:** it does not return the player to
the lobby. `C2S_LEAVE_MATCH` (D-075) already does that and is a different
act — "I am done with this match" versus "I have lost this match". A
player who surrenders stays connected and watching, which is what makes
the distinction worth having: the alternative is that the only way to
concede is to leave, and then nobody can spectate their own defeat.

**Revisit trigger:** the moment a time limit or a score victory lands, the
question "who is ahead" acquires an answer, and surrender should be
re-read against it — a concession while ahead on score is a different
thing from a concession while losing, and only one of them is what this
entry is about.

---
