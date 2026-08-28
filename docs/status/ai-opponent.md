**How hard the AI plays is DATA now (D-20260818-ai-profiles-are-data,
#93).** Three profiles ship under `/ai/*.tres` — easiest first by their
own `order` field — and `ai_player.gd` holds no tuning constant a profile
could have carried. Adding a fourth difficulty is adding a file: a test
fails if any `.gd` names a profile id, exactly as one does for civs
(D-046 criterion 3).

Four things to know before touching it:

- **A profile changes what the AI DECIDES, never what it KNOWS or what it
  is GIVEN.** D-051's structure — a real `ClientState` fed fog-gated
  packets, orders through the server's own dispatcher — is what makes an
  AI win mean anything, so a resource or vision bonus is rejected rather
  than balanced. A handicap, if one is ever wanted, is a *lobby setting a
  player can see*. An AI that quietly saw more would not look like a bug;
  it would look like a good AI.
- **The default profile is bit-for-bit the AI that shipped, and a test
  pins it.** That is what keeps every ladder figure taken before profiles
  existed comparable to one taken after. `AiProfileDef.new()`'s schema
  defaults are those same numbers, so a missing `/ai` costs *difficulty*
  and never the game — and an absent `--ai-profiles` leaves `test-load`,
  `test-scenario` and the old ladder invocation measuring what they
  measured yesterday.
- **Not every constant is a knob.** `FOUND_RETRY`, `UNREACHABLE_AFTER`
  and `SCOUT_LEG_SECONDS` bound a *failure* and stay constants — a
  difficulty setting able to starve an AI of its opening is a way to ship
  a broken opponent by data entry. `food_floor`/`wood_floor` are in the
  schema because the code asked for them, and every shipped profile
  carries the *same* floors: a floor is where the economy stalls, and the
  AI has already spent a whole session gathering zero wood beside a
  healthy food pile.
- **The ladder pairs profiles now:** `just ai-ladder MATCHES SECONDS AI
  TEAMS PROFILES`, e.g. `just ai-ladder 6 600 2 0 cautious,relentless` —
  a comma-separated list dealt round-robin across the AI seats. PROFILES
  is the FIFTH argument because TEAMS (#119) is the fourth: arguments are
  positional, and two changes each adding "one more" is how a run
  silently measures something nobody asked for
  (D-20260817-recipe-args-are-positional). It reports wins per profile as
  well as per player, and `AI_STATS` carries `profile=` and
  `first_attack_soldiers=`. **Quote any result WITH its cap** (the
  standing rule): a stronger opponent lengthens matches and a truncated
  match reads as a draw.
- **And a real match checks the difficulty ARRIVED.**
  `just test-ai-teams … PROFILES` fails if any seat reports no profile,
  or if a list naming two difficulties produces only one at the table.
  The unit tests prove a profile field changes a *decision*; only a
  played match proves it survives the seating path, and #119's whole
  finding is that the configuration nothing runs is the one that breaks.
  **Pair profiles on `clash`, not on the default `siege`**: `siege` hands
  a seat two military squads and the hardest shipped profile masses four,
  so it never attacks inside a short cap and the harness fails on its own
  vacuity gate — correctly. Measured at a **60 s cap**: 3/3 attacks for
  the easier profile against 16/12 for the harder, `ally_objectives=0`
  throughout.

**No strength ordering is claimed yet.** "Relentless beats Cautious" is a
hypothesis written into three `.tres` files, not a measurement; the
decision says so explicitly, and the fix if the ladder disagrees is new
numbers in the data rather than new code. What *is* verified is the
plumbing, measured 2026-08-18: one ladder match at a **100 s cap**
(`--ai=2 --ai-profiles=cautious,relentless`, seed 1) seats the two
profiles, reports each separately, and already shows the ramp the data
asks for — 16 squads / 2 buildings for the harder profile against 6 / 1.
**Neither had attacked at all** at that cap (`first_attack=never`), which
is why this is a plumbing check and not a strength result.

**And the blind spot is unchanged: the ladder is a free-for-all.** Every
AI fixture seats its AI on team 0, which is explicitly not a team
(D-050), so allied AI behaviour is exercised by unit tests and by nothing
else (#119). A profile-vs-profile win rate says nothing about how a
profile plays beside an ally.

**Still not built** (the increments are in the decision, in order):
per-seat selection in the lobby beside civ and team; the behaviour half
of #93 — defence, target selection by weakness, composition off the
counter triangle, retreat on morale, formations, walls; and a pacing
target derived from D-056's 1–2 hour match length rather than emerging
from a cooldown.

**The ladder reports every match it was asked for, since 2026-08-28**
(`D-20260828-a-harness-asserts-the-match-ended`, #224). `just ai-ladder
3 600` asked for three matches; one started, ran to ~140 s with 37 squads
on the board, died printing nothing, and the recipe reported
**`decided: 2 of 2`**.

Three things to know:

- **The denominator was counted from the survivors**, so a vanished match
  could not appear in it by construction. It is the asked-for count now,
  the recipe counts `MATCH_RESULT` lines against `MATCHES`, and it keeps
  each server's exit status instead of discarding it with `|| true` — a
  failure names the seeds that died, and flags 137 as usually this host's
  OOM killer rather than a game defect (#153).
- **This is D-107 one layer in.** That entry made the ladder assert that
  matches START — after three milestones of reporting `draws (time cap)`
  for matches that never left the lobby. Nothing asserted they END. The
  general rule: **assert both ends, and take the denominator from what
  was ASKED for, never from what came back.**
- **A ladder run's wall clock is no longer `MATCHES x SECONDS`.** A match
  decided at 95 s of a 600 s cap used to simulate 505 further seconds of
  its winner gathering against nobody — 84% of that match's wall clock.
  `--stop-after-match` (opt-in, passed by this recipe alone) stops it
  shortly after `MATCH_OVER`. **Every other harness measures the window
  it always did**, and a player-hosted server never stops by itself, so
  no figure recorded before this moves.

**Quote a ladder result WITH its cap** exactly as before — the cap is
still what truncates an *undecided* match. Measured 2026-08-28
(`just ai-ladder 2 120`, native): 2 of 2 results, `decided: 1 of 2`, with
both paths exercised in the one run — match 1 undecided ran to its cap,
match 2 was decided at 99.7 s and stopped 5.1 s later.
