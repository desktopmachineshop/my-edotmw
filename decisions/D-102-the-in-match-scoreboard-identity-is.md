### D-102 · 2026-08-16 · Accepted — the in-match scoreboard: identity is public, strength is fog

**Decision:** A match carries a **player scoreboard**, opened from the
in-game menu (ESC → Players, beside Settings — D-063), listing every seat
in the match. What it may show is decided by where the fact came from,
not by what is convenient:

1. **Identity is public and is not gated.** Name, human/AI, civ (as
   RESOLVED — a seat that said Random shows what it drew), team and
   colour are all lobby facts: every player chose them in front of every
   other player. They need no new plumbing at all, because the seat list
   already survives the whole match on the client (`ClientState.lobby`)
   and `colour_of` is already the one definition every surface draws
   from (D-052).
2. **Standing is public and travels on the wire.** `MatchState.Standing`
   is PLAYING / ELIMINATED / VICTOR, produced by
   `MatchState.standing_of`, attached to each seat by
   `MatchState.scoreboard()`, and carried as one byte per seat inside the
   existing `S2C_LOBBY` packet. The server re-broadcasts that packet when
   a player is eliminated and when the match ends.
3. **Army size is NOT public.** The strength columns (squads, men) are
   derived client-side from `ClientState.composition` and shown only for
   **yourself and your allies**. Everybody else gets `Scoreboard.UNKNOWN`,
   drawn as a dash, and the panel says why on its face.
4. **Eliminated players stay listed**, dimmed and marked (D-033). The
   board never shortens.
5. The deciding lives in `scoreboard.gd` — all-static and pure, the same
   split as `render_cull.gd` and `selection_pick.gd`. `client.gd` only
   draws what it is handed.

**Rationale.**

*Why it exists at all.* Raised from the #29 lobby playtest, where it
blocked a pass criterion outright: "each player has a distinct colour,
consistent between world, minimap and HUD" could not be judged, because
the tester could not remember which player was which once the lobby
closed. Colours were fully built, tested for distinctness and drawn
consistently — and unusable. That is this project's recurring
"mechanism correct, feature absent" shape (D-055, D-061, D-065, D-066)
applied to **legibility** rather than to numbers: nothing failed, and a
player still could not use the thing.

*Why standing had to go on the wire, and identity did not.* The split
was found by checking the encoder rather than trusting a decision entry,
which is D-065's lesson. Identity was already there and complete. Standing
was not there at all: elimination has been a server-side `print` since
D-033, and the client's own defeat screen records — accurately — that it
"structurally cannot know whether hjalmar is still fighting or already
out". A client cannot derive standing through fog, so a scoreboard that
tried would be guessing.

*Why it rides on the seat list rather than in a message of its own.*
Standing IS a fact about a seat, and the seat list is already "the whole
thing, sent on any change" (see `encode_lobby`). A separate standings
message would be a second list that could be ordered differently from
the first — and seat ORDER is what colour is derived from (D-052), so two
orderings is exactly the drift worth refusing. The cost is a byte per
seat on a packet sent a handful of times per match.

*Why army size is derived rather than sent.* This is the load-bearing
half. A scoreboard showing every player's army size would be a fog bypass
with a friendly face — the maphack D-004/D-025's architecture exists to
make impossible, shipped as a menu item. Deriving from `composition`
means there is no packet carrying another player's strength, so no future
caller can leak one: the gate is structural rather than remembered. Own
and ally counts are *complete* rather than partial, and not by luck —
`SquadSim.visible_to` sends a player their allies' squads unconditionally
(D-050), which is precisely why allies can be totalled honestly and
enemies cannot.

*Why VICTOR is not `player == winner`.* `MatchState.winner` holds one id
and a TEAM can win (D-050). Testing equality with it would leave one of
two victorious allies reading as still playing, in the one moment the
board is looked at hardest. VICTOR is "not eliminated when the match
finished", which is the same rule `_check_victory` already uses.

**Rejected alternatives.**

- **Show everyone's army size.** The obvious reading of "current stats",
  and a fog bypass. Rejected on D-004/D-025; the whole reason this
  project's fog is curve gating is that the client does not HAVE the
  data to leak, and a scoreboard that asked the server for it would put
  it there.
- **Show a partial enemy count — "what you can see".** Worse than a
  dash: a number that looks total and is not is precisely the
  "numbers all correct while the picture is wrong" failure this project
  has hit repeatedly. A dash is the truth, and the panel says which rule
  produced it.
- **Include ally BUILDING counts alongside squads.** Buildings are
  vision-gated even for allies (`BuildingSim.visible_to` checks owner,
  not alliance), so an ally's building count would be exactly the
  partial-dressed-as-total number rejected above. Left out; if it is
  wanted, the honest fix is to make ally buildings unconditionally
  visible the way ally squads already are, which is a change to D-050
  and not to the board.
- **Invent a score.** Nothing in this project scores a player, and
  nothing counts kills, losses or razings — the defeat screen already
  says so and shows only time held. A score column would have had to
  invent both the number and the counters behind it. Standing is the
  real standing.
- **Its own `S2C_SCOREBOARD` opcode.** More wire surface for a fact the
  seat list already carries, and a second ordering of the same players.
- **Compute standing on the client from what it can see.** Impossible
  through fog, and a client that decided who was out would eventually
  disagree with the server about who won.
- **A hotkey (Tab) instead of the menu.** Not rejected on merit — the
  menu is where the issue asked for it and where a player will look
  without being told. A hotkey is cheap to add later.
- **Layout arithmetic in `hud_layout.gd`.** Suggested in the issue, and
  it turned out there is none: the panel sits inside the game menu's
  existing container row, exactly as the settings pane does, so it is
  laid out by the same containers and scaled by the same CanvasLayer
  transform. The part that was worth extracting from `client.gd` is not
  where the box goes but **what a player is entitled to see**, which is
  why the pure module is `scoreboard.gd`.

**Consequences.**

- `MatchState` gains `Standing`, `standing_of` and `scoreboard()`; the
  latter returns COPIES, so a caller cannot write match state back onto
  the lobby's seats (`start_match` reads `seat["choice"]` off them).
- `encode_lobby`/`decode_lobby` gain one byte per seat. A seat with no
  `standing` key encodes as PLAYING, which is what every call site
  predating this means. This is a mid-packet field, not a trailing one,
  so client and server must ship together — true today, and precisely
  what D-094's protocol version handshake is for once Steam makes mixed
  versions routine.
- `server.gd` broadcasts the seat list on elimination and on match end —
  which is the first time `_broadcast_lobby` has ever run outside the
  LOBBY phase. It mirrors `_match.map_settings` into `_settings` on the
  way through, and that is safe **because the two are the same object**:
  `_match.map_settings = _settings` at construction, whether or not this
  server has a lobby. The only thing that ever breaks the aliasing is
  `set_map_option`'s rollback, which is lobby-only and which this very
  assignment exists to repair. Worth writing down because it was got
  WRONG here first: this entry briefly shipped a phase guard against a
  bug that could not happen, argued from `set_map_option` being
  lobby-gated rather than from the aliasing that actually makes it a
  no-op — and the guard would itself have suppressed the repair on the
  broadcast that follows a lobby start.
- The board is refreshed on a 0.25 s throttle while open, for the same
  reason the minimap is: its numbers change at 10 Hz at most.
- **This is the first thing that shows a player their own live army size
  as a number.** If that turns out to want to be on the HUD rather than
  behind a menu, this is where the count already lives.

**Revisit trigger:** any wish to put a stat on the board that a player
could not already derive from what the server chose to send them. That is
the moment this stops being a rendering of existing knowledge and becomes
a second data channel, and it has to be argued against D-004/D-025
explicitly. Also revisit if ally buildings become unconditionally visible
(the buildings column becomes honest), or if kills/losses/razings ever
get counted (a real score becomes possible).

**Editorial note on the number.** This entry takes **D-102**. It was
written as D-101, which is what its first commit message still says, and
moved twice before landing:

- **099 and 100 were spent when it was written.** `ground_cover.gd`,
  `cover_preview.gd` and `tests/test_ground_cover.gd` all cite D-100 for
  ground cover, and no entry for either number existed in this file at
  the time — the code landed and its entry did not survive the merges
  D-098's own editorial note describes. (D-100 has an entry again now:
  the map-seed roll immediately below, itself renumbered from D-099.)
- **101 was claimed twice the same day**, by PRs #66 and #71, both
  opened before this one.

So it took the next number past the front rather than becoming the third
D-101 — and that landed on the same number the coordinating session
independently assigned this branch (#76 = D-102, see the numbering note
on D-100 below). **The IDs are stable once merged, not before**, which is
the convention here rather than a failure: several agents author entries
in parallel against one document, and whoever lands later renumbers.
---
