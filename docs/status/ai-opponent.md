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
**And the retry had nowhere else to go (#217, 2026-08-28).** An AI seat
whose SPAWN CELL held a resource node never founded a town centre — not
late, ever. `_found_town` sited itself at `ClientState.spawn_cell_of`,
which never moves, so every five-second retry re-sent the identical
refused order for the whole match: `buildings=0`, `peak_wood=200` against
a 150-wood hall, eliminated as soon as its two opening squads died. It
now walks outward from home through `TorusSpace.disk_offsets`
(nearest-first, D-067), skipping cells it can SEE are blocked and
advancing one acceptable cell per refusal.

Four things worth carrying:

- **`docs/status/m6.md`'s paraphrase of D-107 — "It retries against a
  different site now" — was FALSE when written and is true now.** D-107's
  own entry never claimed it; the summary invented the half that would
  have made the fix complete. Same family as the doc-comment defects
  CLAUDE.md lists, one level up: **a status doc describing behaviour is
  not evidence of it either.**
- **The AI already knew how to vary a site — just not for the hall.**
  `_raise_buildings` has used `_site_beside` since it was written, and
  the repro log shows a *barracks* refused and immediately placed
  elsewhere. The town centre was the only build in the file retrying a
  constant cell, which is what makes this an omission rather than a
  design.
- **The retry advances on every attempt, not on a refusal it recognises.**
  The AI cannot model every rule the server enforces — `terrain_passable`
  is set by `client.gd` and never for an AI seat, so steep ground and
  water are not on this client at all, and an enemy's no-build claim may
  be under fog. Skipping only what it KNOWS would rebuild #217 for every
  reason it does not. The node check is an optimisation that makes the
  common case converge on the first attempt; the widening is what makes
  it converge at all.
- **The loop was invisible, not absent**, because `_report_refusals`
  dedupes on message text: one `AI_REFUSED` line stood for a spin that
  ran the whole match. Worth knowing before reading any AI log as a
  count of anything.

**The A/B, on one tree, from the issue's own repro** (`--map=ladder
--lobby=0 --players=0 --ai=2 --seed=2 --run-seconds=150`):

| | before | after |
|---|---|---|
| seat 1001 founds | never (`a food source is in the way`) | `began town_centre at (24, 36)` |
| buildings | 1000: 1, **1001: 0** | 1000: 2, **1001: 2** |
| squads_peak | 12 / **2** | 19 / **18** |
| CIVS_FIELDED | emberdeep=14, **gildedreach=2** | emberdeep=22, **gildedreach=20** |
| outcome | `MATCH_ELIMINATED 1001`, `MATCH_OVER winner=1000` | no elimination, one attack at 145.6 s, still playing at the cap |

The `after` run also shows the widening doing the half the node check
cannot: one `Too close to another building` refusal for seat 1001,
retried past rather than spun on.

**The first version of the fix ran out of sites, and only a played match
found it.** It skipped `_found_attempts` acceptable cells and fell
through to `home` once it passed the end of the list — so after about a
dozen refusals it rebuilt #217 exactly. A four-AI run on `ladder` at seed
7 reached that: a seat sent its twelfth attempt at 56 s and every attempt
from then on at the same blocked start. The list is CYCLED now, which
also covers a refusal that clears later (an enemy claim razed, a node
worked out), since the site comes round again. **Every unit test passed
throughout** — the exhaustion needed more retries than a fixture had
reason to run, and the instrument that saw it was a printout from a real
match.

**And that same run turned up a defect that is not the AI's at all
(#247): `civs/gravesworn.tres` ships `starting_wood = 140` against a
150-wood town centre**, so that civ begins the match unable to raise the
one building its opening crew exists to raise. The AI then deadlocks —
every five-second founding retry re-claims the crew off hauling (the #123
fix), so it never gathers the ten wood that would break it: `workers_peak=1`,
`peak_wood=140` flat for the whole match, eliminated. Filed rather than
fixed, because which number moves is a balance call. **Read any ladder
result involving gravesworn as suspect until it is settled.**

**And it means ladder numbers can contain matches nobody played, again.**
A seat that never founds is eliminated and the harness reports a decisive
win with plausible `AI_STATS` for the winner — D-107's own failure
arriving through a different door, since the match *did* leave the lobby
and the started-check passes. Read any strength result taken before this
with the founding rate beside it.
