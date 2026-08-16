### D-107 · 2026-08-16 · Accepted — an AI seat acts only while the match is running, and latches on effect rather than on intent

**Numbering note.** Written as D-099 by inspection of this file, which
then topped out at D-098, and renumbered to **D-107** on rebase. D-099 is
spoken for: the coordinator of the seven parallel fix branches assigned
#68=D-099, #70=D-100, #66=D-101, #76=D-102, #71=D-103, #73=D-104,
#75=D-105, #78=D-106 — and this branch (PR #77) was opened after that
assignment and is not in the list. D-107 is the first id past every
assigned one, which is the only choice that cannot collide with a branch
still in flight. See D-100's own numbering note for the *other* collision
(ground cover holds a D-100 in force with no heading here), and D-081's
for the precedent. **The trap both notes record is the same one, and it
applies to this entry too: the highest heading in this file has never
been the highest number in force.** Do not pick an id by grepping `###
D-` alone — check `docs/plans/`, the code citations, and what is open.

**Decision:** Three rules, all about the AI seat, all bought with the
same defect (issue #61, found while staging the #39 siege playtest):

1. **An AI acts only once its own client says the match is running.**
   `AiPlayer.update()` returns immediately unless `state.welcomed` and
   `not state.in_lobby()`. The fact comes off the wire (S2C_LOBBY's
   phase, D-048), not from the server object — because D-051's whole
   claim is that an AI knows exactly what a client in its seat knows.
2. **An order is latched on its EFFECT, never on having sent it.**
   `_found_town` stops when it can SEE a town centre it owns, not when
   it remembers asking for one. It is bounded on the other side by
   `_founder()`: it cannot ask at all unless it holds a squad whose
   archetype the shipped `BuildingDef.built_by` allows to found one.
3. **Anything a client is TOLD goes to `server._recipients()`**, which is
   sockets and AI seats alike. `_clients` is only for things a SOCKET has
   — ENet statistics, disconnects, D-075's "no humans, no server".

And one harness rule, which is CLAUDE.md's standing "assert the thing
happened" applied to the one harness that lacked it: **`just ai-ladder`
fails unless every match is observed to leave the lobby.**

**Rationale:** The server ticks AI brains from the moment a seat exists.
In a no-lobby match (`--ai=n`) that is at boot, before anybody has
connected and while `MatchState.phase` is still LOBBY. So `_found_town`
fired on tick 0, `server._validated_squad` dropped the order on its
not-running guard *without a word*, and `_founded = true` was set on the
line before `send.call(order)`. One attempt, spent into a closed door,
never repeated: **every AI opponent in every match, on every map, sat on
its founding party for the whole game** — no town centre, no gatherers,
no barracks, no army. `just quick-test`, `just run-server AI=n` and every
lobby with an AI seat were all matches against opponents that did
literally nothing.

Nothing failed, and nothing could. `tests/test_ai_player.gd` drives the
brain with the match already running, so it exercised the logic and never
the timing. The ladder — the one harness that would have noticed — could
not start a match either (below), so it reported ten minutes of nothing
as `draws (time cap)` and that was read as an AI weakness through several
rounds of AI work.

Two more defects fell out of the same path:

- **`ClientState.spawn_cell_of` disagreed with the server about where a
  player starts.** It computed `(player - 1) % spawn_cells.size()` under
  a doc comment claiming it "mirrors server.gd's own wrap … so both sides
  answer this the same way". It did mirror it, until the server moved to
  the SEAT index (`MatchState.spawn_index`) precisely because AI ids start
  at 1000 and any modulo of a player id collides. So an AI that got as far
  as founding would have founded on a rival's start. Fixed by deleting the
  copy: `MatchState.spawn_index_in` is now static, takes a seat list, and
  the client passes the one it already holds.
- **`just ai-ladder` could not start a match at all.** `server.gd`
  computed `players_expected = maxi(1, --players) + ai_wanted` and the
  recipe passed `--players=1 --ai=2` while launching no human, so two of
  three expected participants ever arrived. `maxi` now wraps the SUM, so
  `--players=0` is expressible, and the recipe says so.

**Rejected alternatives:**

- *Gate the AI in `server.gd` instead* (`if _match.is_running(): for
  brain in _ai_players`). One line, and untestable: server.gd needs a
  live ENet host, which is why MatchState exists at all. The rule would
  have been correct and unguarded, and this is a defect class that
  survives precisely by nothing failing.
- *Remove the `_founded` latch outright.* Measured, and wrong: the AI
  re-sends forever and the log fills with "gatherers cannot build a Town
  Centre" the moment the founders are consumed. The fix is not "retry
  blindly", it is "latch on what actually happened, and know when asking
  is illegal".
- *Put the player's own spawn index on the wire as a new WELCOME field.*
  Works, but adds a protocol field to carry a fact the client can already
  derive — and derive from the SAME list, in the SAME order, using the
  SAME function the server uses. A second definition is what broke this.
- *Have the ladder detect a stuck lobby by watching for silence.* An
  absence of evidence, which is the exact shape of the vacuous log-grep
  that hid a live bug for the whole of M1. It greps for a structured
  marker the server prints when a match actually starts.
- *Let the ladder keep exiting 0 on a lobby-locked run.* This is the
  `test-load` lesson verbatim: a harness that reports a game that was
  never played, in the vocabulary of a game that was played badly, is
  worse than no harness.

**Consequences:**

- Measured on the ladder map, one 180 s match, before → after:
  `squads_peak` **1 → 24**, `buildings` **0 → 2**, `first_attack`
  **never → ~175 s**. No AI logic changed; only its timing.
- `server._note_match_started()` exists for the no-lobby path, where
  nobody presses start and `_on_match_started` never runs. It prints the
  same `server: match started` marker the lobby path does — so "did a
  match actually start" has ONE marker in the log however it began — and
  broadcasts the lobby, which is how an AI seated during the lobby learns
  the phase changed.
- `_seat_ai` now records its civ in `_civs`. It did not, so `_civ_of`
  fell through to `all[(player - 1) % all.size()]` — the same id-modulo
  family — and an AI reported one civilisation in `AI_STATS` while
  fielding another's troops.
- `_validated_squad` now `_notify`s "The match has not started" instead of
  dropping in silence. D-034's rule is that a refused order says why;
  this was the exception, and the silence is most of what made the lost
  founding order hard to find.
- **CLAUDE.md's ladder numbers were measured against an AI that never
  played** and are void. So is anything derived from them.
- `just ai-ladder` now runs a genuinely all-AI server (`--players=0`).
  That is also the first thing in this project to hold a running match
  with no socket attached; D-075's "no humans, no server" is untouched,
  because it fires only on a disconnect.

**Revisit trigger:** If an AI ever needs to act during the lobby — a
seat that picks its own civ, say — `match_running()` is the one place to
widen, and it must widen by asking a *different* question rather than by
being removed. And if `just ai-ladder` ever reports a draw at the cap
again, believe it this time: the "match actually started" assertion is
what makes that reading honest.

**The lesson, which is the point of this entry:** this is D-061's family
— a mechanic fully written, correct, and reached from an unreachable
branch — with a new wrinkle worth naming on its own. **A latch that
records an INTENT will eventually be read as a record of an OUTCOME.**
`_founded = true` above `send.call(order)` is nine characters of
optimism, and it cost the game every AI opponent it ever had. Latch on
the effect, or do not latch.

---
