### D-100 · 2026-08-16 · Accepted — a lobby rolls its map; a pinned seed reproduces the whole match

**Numbering note, and an UNRESOLVED collision — read this before citing
D-100 anywhere.** This entry was written as D-099 and renumbered to D-100
on 2026-08-16 by the session coordinating seven parallel fix branches,
which assigned #68=D-099, #70=D-100 (this), #66=D-101, #76=D-102,
#71=D-103, #73=D-104, #75=D-105, #78=D-106.

**D-100 was already in force when that assignment was made**, for GROUND
COVER: merged as PR #25 (commit da23dc8), cited four times in `CLAUDE.md`
and roughly twenty times across `ground_cover.gd`, `cover_preview.gd`,
`art/build.py`, `art/lib/bake.py`, `art/scatter/*` and
`tests/test_ground_cover.gd`. It has no heading in this file — its entry
sits in `docs/plans/D-100-ground-cover.md` — which is exactly why a scan
of `### D-NNN` headings tops out at D-098 and misses it. That is the trap
the D-068 block records verbatim: **the highest heading has never been
the highest number in force.** The conflict was raised with the
coordinator, with this evidence, and the assignment was reaffirmed; it is
recorded here rather than silently absorbed, because the two D-100s mean
different things and a reader following a code citation needs to know
which. **Resolving it is still owed** — the cheaper side to move is
ground cover's, which has citations but no heading here.

**Decision:** the map seed is **rolled when a LOBBY opens, and again on
the way back to one**, unless somebody pinned it. Everything else keeps
the fixed default. Five clauses:

1. **`MapSettings.roll_seed()` is the one non-deterministic line in the
   map pipeline.** It draws into `[0, MapSettings.SEED_MAX]` — the same
   ceiling the lobby's spinner offers, so a rolled map is always a number
   the host can read off the screen and type back in.
2. **Only a lobby rolls.** `server.gd` rolls when `--lobby=1` and no
   `--seed` was given; a no-lobby start is a test harness or a dev launch
   and keeps `MapSettings.DEFAULT_SEED` (1337). Bots, scenarios,
   `test-load`, `test-client`, `ai-ladder` and `profile` are therefore
   as reproducible as they were.
3. **Choosing a seed PINS it** (`pin_seed`, set by `--seed` and by the
   spinner), and a pinned seed survives the return to the lobby. That is
   what makes "that was a good map, play it again" work, and it is the
   only way to hold a map still.
4. **A `Reroll` button beside the spinner asks the SERVER for a new
   seed** (`MatchState.REROLL_OPTION`) and leaves it unpinned. The client
   does not draw the number: the host would otherwise choose everyone's
   map, and a client-sent seed would arrive through the pinning path and
   silently stop the lobby rolling.
5. **The civ draw follows the map seed.** `MatchState.civ_rng` is seeded
   `civ_seed_base + map_settings.seed`, where the base is
   `hash(MapConfig.id)`, and re-seeded whenever the seed can have changed.
   So a pinned seed reproduces the whole match SETUP — terrain, spawns,
   combat rolls and who is playing whom — not merely the ground.

**Rationale.** `MapSettings.seed` has carried the doc comment "Rolled per
match unless someone pins it, so two matches on the same settings are
still different places" since D-049, and **nothing anywhere rolled it**.
Every lobby-started match, which is every match a human plays, generated
the identical world from seed 1337. Found in the #29 lobby playtest, by a
tester trying to work out whether they had typed the seed themselves.

One line away sat the same defect in a second dress: `civ_rng` was seeded
`hash(_config.id) + int(args.get("seed", 0))` — the **same absent
argument, defaulted to 0 here and 1337 twenty-five lines above**. A seat
set to Random resolved to a real civ, so the visible half worked; it
resolved to the same civ every match.

Both are this project's declared-and-unread family (D-055, D-061, D-065,
D-066), in the variant where the mechanism is not merely uncalled but
**documented as working**. Nothing fails. The game runs and quietly lacks
a rule, and the only instrument that can see it is a person playing twice
and recognising the coastline.

**Which way to resolve it — code or comment?** The issue flagged both as
defensible: "reproducible by default" is a real choice for a strategy
game. Rolling wins for three reasons. The written intent has stood for a
milestone and the ONLY thing contradicting it is an omission. A fixed
default makes #29's own pass criterion vacuous — "restart with the same
seed gives the same map" cannot fail when the seed never changes, which
is exactly the check-never-seen-red trap. And a map that is the same
place every time is a worse game, while a pin costs one number typed.

**Rejected alternatives:**
- **Correct the comment, keep 1337.** Cheapest, and it is what the code
  already does. Rejected: it ships "every match is the same map" as a
  deliberate design, which nobody has ever argued for, and it leaves the
  #29 criterion untestable.
- **Roll for every server, including headless ones.** Consistent, and it
  would have caught this sooner. Rejected: `test-load`, `ai-ladder` and
  `profile` compare runs against each other, and a map that changed under
  them would turn every performance regression into an argument about
  which map it was measured on. The reproducible default is load-bearing
  for the whole test estate.
- **Roll on the CLIENT and send the seed up.** The lobby already sends
  settings up, so it would have been a one-line button. Rejected under
  D-002: the host is not trusted with the world everyone plays on, and
  the same message would have to double as "pin this seed", so a lobby
  that had ever rerolled would stop rolling between matches.
- **Draw civs from their own wall-clock RNG.** Makes Random random
  without touching the map. Rejected: it breaks D-016's replay
  obligation, which is exactly why `civ_rng` was seeded in the first
  place. Following the map seed keeps the replay and makes the pin mean
  more.
- **Re-roll on `return_to_lobby` only when the host asks.** Fewer
  surprises. Rejected: it reintroduces the reported bug for the most
  common path there is — press "play again" and get the map just played
  — and the host can pin in one click if they want the rematch.

**Consequences:**
- The seed the lobby shows on arrival is now a different number every
  time, and the map preview beside it a different place. That IS the
  fix's visible surface, and the thing to look at when judging it.
- `just lobby-shot` is the headless way to see it. The server prints
  `lobby rolled map seed <n>` at startup and names the next map's seed on
  every return to the lobby, so a run can be traced without a GPU.
- #29's seed criterion is now testable the three-way way its issue asks
  for: note the map, change the seed and see it differ, set it back and
  see it return.
- Rolling costs one `RandomNumberGenerator` per lobby and nothing per
  tick. `test-load 4 240` is clean after — 4/4 bots, 952 state-hash
  checks, **0 desyncs**, 0 dropped ticks, 162 casualties, 40 nodes
  felled. **Its per-squad figure, 184 µs/squad at 35 squads, is not
  usable and is recorded only so nobody mistakes it for one**: eight
  other worktrees were running load tests on the same host, the worst
  tick was 1,423 ms, and the docker CLI itself was returning "Resource
  temporarily unavailable". Same lesson as M6's worst-tick figures and
  D-096's 1,000-squad absolutes. Nothing in this change runs per tick.
- **`test-load 4 120` failed on `reveal_events=0` twice before that**,
  and the gate was right to fire: at 240 s the same build reported
  `reveal_events=1`. Reveal is the scarcest thing that verdict asks for
  on the standard map, so a contended host is enough to lose it. This is
  the standing "quote a ladder result with its cap" rule wearing another
  hat — **when the host is loaded, lengthen the run rather than reading
  the failure as a regression.**

**Revisit trigger:** if a ranked or matchmade mode arrives (D-091 gates
ranked on dedicated servers), map selection stops being the host's to
roll at all and becomes the queue's — at which point clause 2's "only a
lobby rolls" needs a third case rather than an edit.

---
