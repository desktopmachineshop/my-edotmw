# D-20260817 · 2026-08-17 · Accepted — an AI asks `are_allied`, not "is this mine"

**Decision:** every place `ai_player.gd` decides whether something is a
target goes through one predicate, `AiPlayer._hostile(who)`, which is
`not state.are_allied(who, player)` — the client's mirror of the
simulation's own alliance rule (D-050). No scan in that file compares
owner ids to decide allegiance.

Three clauses:

1. **"Not mine" is not "theirs."** A match has up to 20 players and D-050
   puts some of them on your side. The ownership test answers a different
   question from the one every one of these scans was asking, and the two
   answers differ exactly when a teammate exists.
2. **One test, not two.** `are_allied(a, a)` is true, so `_hostile`
   *replaces* the ownership check rather than sitting beside it. Two
   conditions where one will do is two conditions that can be changed
   apart.
3. **The metric is held to the same rule as the behaviour.**
   `peak_enemy_buildings_known` counts through `_hostile` too. An
   instrument that shares the blind spot of the thing it measures reports
   the defect as health.

## Rationale

`ai_player.gd` contained **zero** references to teams or alliance —
`grep -E 'are_allied|allied|team'` over the whole 996-line file returned
nothing. Its targeting filtered on ownership alone, in two places:

```gdscript
if int(info["owner"]) == player or bool(info["destroyed"]):      # buildings
if int(state.composition[id].get("owner", 0)) == player:          # squads
```

So every allied building and every allied squad was a valid attack
objective.

**It targeted an ally preferentially, not occasionally.** Buildings are
scanned first and nearest wins (that ordering is deliberate — see
`_enemy_target`'s own doc). Allies start near each other, and D-050 gives
teammates shared vision, so a teammate's town centre is both close and
*guaranteed known*, while an enemy's base has to be scouted first —
buildings are persistent-explored (D-030), so an unscouted enemy base is
not in `state.buildings` at all. For an AI with a teammate, the nearest
known building is very often the teammate's.

**And it could not recover, because the correct rule is what traps it.**
`combat.gd` gates all three damage paths on `sim.are_allied` — squad vs
squad, squad vs building, and the buildings' own return fire — so the
allied building is never destroyed. The target is re-picked every attack
window, always by nearest, always the same one. The army arrives and
mills there for the rest of the match. **A livelock, and the visible
symptom is the correct rule meeting the incorrect targeting**: friendly
fire being properly refused is what turns "the AI attacks its ally" into
"the AI's army is permanently parked on its ally". Reported by the owner
from a playtest (issue #83).

**Why nothing caught it: the AI has never been run with an ally.**
`just ai-ladder` is a free-for-all — the recipe passes `--players=0` and
a plain `--ai=N` and assigns no teams at all. `tests/test_ai_player.gd`
seated its AI with `"team": 0` in both places it built a lobby, and team
0 is explicitly *not* a team (D-050), so `are_allied` was false for every
pair every fixture ever built. Every automated exercise of the AI has
been teamless, and the one configuration that breaks it is the one
nothing runs.

This is the declared-and-unread family CLAUDE.md warns about, wearing its
other face. The usual shape is a member with no caller. Here the rule was
written, tested, and *enforced everywhere it mattered* — the AI was
simply never told it existed. Nothing failed; the game ran and one
participant quietly lacked a rule. Same consequence as the note already
standing for walls ("no AI builds or uses walls, so `just ai-ladder`
cannot exercise any of this feature"): a feature the AI is blind to is a
feature the ladder cannot measure.

## A third site the issue did not name

`_enemy_target` was the first, not the only. `_next_place_to_look` — the
scouting fallback, reached when nothing is in sight — skipped exactly one
spawn cell, its own, and marched the army at everyone else's in turn. A
teammate's start is the one place on the map *guaranteed* to hold nothing
this AI has not already been shown, because D-050 shares their vision, so
that leg is wasted by construction. It is not a livelock (`_looked`
advances), which is why it survived the reading that found the other two:
the symptom is a slower AI, not a stuck one.

`_friendly_homes()` reads the seat list through `ClientState.spawn_cell_of`
rather than repeating the seat-index arithmetic locally — that copy is
precisely what once sent every AI to found its capital on another
player's spawn (see `spawn_cell_of`'s own doc, and
D-20260817-starting-positions-follow-the-seats).

The other three `owner` comparisons in the file (`_owned_building_count`,
`_train`, `_producible_archetypes`) are `== player` and stay that way:
they mean "a building I may give orders to", which is ownership, not
allegiance. An ally's barracks is not one this AI can produce from.

## Rejected alternatives

- **Add `or state.are_allied(...)` beside the ownership test**, as the
  issue's suggested patch does. Correct, and it leaves two conditions
  encoding one rule, in four places, free to be edited apart. The issue
  itself flags this and recommends collapsing; clause 2 is that
  recommendation taken.
- **Teach the AI to fight allies only when it has no other target.** The
  premise is wrong: it is not an ordering problem. An allied target can
  never be resolved at all, so any fallback that can reach one is a
  fallback that can hang.
- **Have the server refuse an attack-move onto an ally.** Untrue to the
  order — attack-move onto friendly ground is a perfectly legal thing for
  a human to do (repositioning through a teammate's base), and D-051 says
  an AI is held to the rules a human is held to, not to extra ones.
- **Read teams from `MatchState` on the server side.** An AI seat is a
  client (D-051) and must decide from what a client in its seat knows.
  `ClientState` already holds the seat list (D-048) and already mirrors
  the rule; reaching past it would be the one thing the whole design is
  arranged to prevent.

## Consequences

- `ai_player.gd` gains `_hostile` and `_friendly_homes`; `_enemy_target`,
  `_record_stats` and `_next_place_to_look` route through them.
- **Nothing changes in a free-for-all.** With no seat list, or with every
  seat on team 0, `are_allied(a, b)` is `a == b` — byte-for-byte the old
  ownership test. Existing ladder numbers stay comparable.
- Cost: `are_allied` is a linear scan of ≤20 seats, run once per known
  building at `THINK_INTERVAL` (1 s) and once per candidate when an
  attack window opens. Nothing per-tick, nothing on the wire, nothing on
  the server. Deliberately not memoised — this is a 20-element walk, not
  the per-cell `distance()` family CLAUDE.md's standing rule is about.
- **`peak_enemy_buildings_known` changes meaning in a teamed match** and
  only there: it now answers the question its own comment says it exists
  to answer. `buildings_raised` still counts what *this seat* put up, so
  `mine` stays an ownership test.
- Five tests in `tests/test_ai_player.gd`, all observed red before the
  fix: the teammate's town, the ally-only world (target must be
  `(-1, -1)`), the teammate's army, the metric, and the scouting leg.
  The fixture (`_teamed_world`) asserts its own teams reached the AI, so
  it cannot pass by the alliance simply never arriving.

## What this does NOT fix, and why it is separate

**Allied AI behaviour is still not exercised end to end.** Closing that
means a teamed ladder, and on inspection it is not the small change the
issue estimated:

- the server has no CLI for teams at all — `--ai=N` seats every AI on
  team 0, and `MatchState.set_team` is lobby-and-admin only by design;
- and **`_sim.teams` is never assigned on the no-lobby path.**
  `_on_match_started` (the lobby path) sets it; `_note_match_started`
  (`--lobby=0`, which is what the ladder, `test-load` and `test-scenario`
  all run) does not. Dormant today, because nothing without a lobby has
  ever had a team to hand over — and it means a `--ai-teams` flag alone
  would seat allies whose alliance the *simulation* never learns, i.e.
  allies that shoot each other.

That is a decision-sized change to shared server startup, so it is filed
rather than smuggled in here. The unit tests above are the other candidate
the issue names, and they are the ones that can see this defect today.

## Revisit trigger

An AI acquiring any other rule that partitions players — a diplomacy
state, a truce, a non-aggression window. `_hostile` is the seam those
belong in, and a second predicate appearing beside it is the thing to
catch. Also: the ladder gaining teams, which is when `_sim.teams` on the
no-lobby path stops being dormant.
