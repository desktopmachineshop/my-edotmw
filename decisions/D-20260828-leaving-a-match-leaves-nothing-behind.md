# D-20260828 · 2026-08-28 · Accepted — leaving a match leaves nothing behind

**Decision:** a player who leaves a running match has **everything they
own** removed, not only their army (#292, #318). Three clauses:

1. **`BuildingSim.eliminate_player(player)` exists**, the sibling of
   `SquadSim.eliminate_player`, and the disconnect path calls both.
2. **It razes through `damage()`**, so a client applies the destruction
   exactly as it applies any other one — dirty flag, then
   `S2C_BUILDING_INFO`. No second message for "the owner left".
3. **The disconnect path refreshes passability**, because it runs
   OUTSIDE the tick that would otherwise notice.

D-033's rule is unchanged and that is the point: the wipe is the *cause*
of defeat and the ordinary rule notices the effect, so "defeated" keeps
exactly one definition.

## Rationale

D-033 said a disconnect wipes the abandoned army and the ordinary defeat
rule notices. `server.gd`'s comment on the wipe said so too, naming the
rule as *"no living squads"*.

That rule stopped being "no living squads" when
`D-20260823-the-opening-is-a-crew-and-a-general` added the buildings
clause — for an unrelated and entirely correct reason: a crew that founds
a town hall is **consumed by it**, so a player making the right opening
move would otherwise be declared beaten with their hall standing.

Adding that clause **silently broke the disconnect path's stated
guarantee.** `BuildingSim` had no per-player wipe at all — no
`eliminate_player`, no raze-all, nothing — so the buildings survived,
`living_building_count` stayed above zero, and the player was never
eliminated.

**Both halves were correct on their own, which is why nothing failed.**
The wipe is real, is called, and does its job; it simply stopped wiping
enough. The comment asserting the guarantee stayed exactly where it was,
describing a consequence that had ceased to be true — the D-065 family,
and the reason this survived being read.

**What it cost a player.** A 1v1 where one side rage-quits ran to the
time cap: `_check_victory` needs one side standing, and a disconnected
ghost with a town centre counts as standing. The remaining player had no
opponent and no way to win — only a chore, marching across the map to
raze an undefended base before the game would end. At D-056's 1–2 hour
target that is the whole session, and it is worse in a hosted alpha
(#183) than in a bot run, because bots do not quit and testers do.

## Rejected alternatives

- **Changing the elimination rule** so buildings do not count for a
  DISCONNECTED player. It fixes the symptom and creates two definitions
  of "defeated" — one for people who are here and one for people who are
  not — which is precisely what D-033 exists to prevent. The next
  question ("is a disconnected player's building still a target?") would
  then have no principled answer.
- **Setting `_destroyed` directly** instead of going through `damage()`.
  Faster and silent: no dirty flag, so no client is ever told, and
  D-030's ever-revealed set means every client that has ever SEEN the
  base needs telling — including ones that cannot see it now. Observed
  to fail.
- **A dedicated "owner left" wire message.** A second thing to keep in
  step with the first, for a destruction clients already know how to
  apply.
- **Leaving the buildings and letting D-090 handle it.** Reconnection is
  repossession hands a disconnected seat to an AI immediately, which
  would make the abandoned base *defended* and this question moot — and
  it is planned and not built (`docs/status/m8-plan.md`). This is the
  live behaviour today and the two fixes are independent.
- **Razing only COMPLETED buildings.** The elimination rule counts what
  is not destroyed, not what is complete, so a half-built hall left
  standing keeps its absent owner in the match exactly as a finished one
  does. Observed to fail.

## Consequences

- **#292 and #318 are one defect and close together**, which is what the
  investigation found rather than what it assumed.
- **Eleven tests, and they were observed RED BEFORE THE FIX** — all
  eleven, reporting the issue's own symptom (`the match must end`,
  `and so does the abandoned base — this is the half that was missing`).
  That is the strongest form of the observed-to-fail rule available and
  it was possible here because the bug was reported with a repro.
- **Each rule was then perturbed individually** afterwards, because
  "everything was red before" does not tell you which test guards which
  rule: the server call, the passability refresh, ownership, unfinished
  buildings, the dirty flag, idempotence, and the comment.
- **The comment is corrected**, and a test fails if the old wording
  returns. A comment that describes a rule is a claim about another
  file, and this one was wrong for a whole milestone.
- **`test-load` and `ai-ladder` were quietly wrong in the same way** — a
  run where a client drops mid-match reported a draw at the cap that was
  not a draw. Neither harness drops clients deliberately, so no measured
  figure is known to be affected; worth knowing before trusting an old
  run that logged a disconnect.

## Revisit trigger

D-090 landing. Once a disconnected seat is repossessed by an AI, the
abandoned base is defended and this wipe becomes wrong — a player who
drops for thirty seconds should not lose their town. At that point the
wipe belongs behind "the seat was not repossessed", and that is a change
to this decision rather than to the disconnect handler.
