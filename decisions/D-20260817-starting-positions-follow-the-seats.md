# D-20260817 · 2026-08-17 · Accepted — starting positions are the seat count, and neither they nor the seed are lobby controls

**Decision:** `MapSettings.player_slots` is DERIVED from the lobby's seat
list, not set. `MatchState._seats_changed()` re-derives it at every site
that adds or removes a seat, clamped to `[MIN_PLAYER_SLOTS,
MAX_PLAYER_SLOTS]` = [2, 24], and reverted if the result is a map the
generator refuses. Two consequences follow, and both are the point rather
than fallout:

1. **`set_map_option`'s `player_slots` case is gone.** A setter for a
   derived value is a knob whose answer the next join silently overwrites.
2. **The lobby shows neither a "Starting positions" row nor a "Seed"
   row.** Reroll stays: asking for a different map is a real thing to
   want; typing the number that produces one is not.

## Rationale

Reported by the owner from a lobby playtest, 2026-08-17 (#103): "the
starting positions and seed number shouldn't be displayed. Starting
positions should always just be the number of players in the lobby."

Both rows were controls that asked a player to answer a question they
cannot have an opinion about. And the starting-positions one was **already
answering it wrongly by default**: `MapSettings.player_slots` defaults to
8 (20 on the shipped map config), so a lobby of three generated twenty
starting positions, seventeen of which nobody stood on — and, because
`MapConfig.spawn_points` scatters at a minimum spacing (D-039/D-104),
three players were flung as far apart as twenty would have been. The
number was never a preference; it was the seat count, written down twice
and allowed to disagree.

**Why the derivation lives in `MatchState`.** That is where seats are, and
the rule is a rule rather than a UI state — the same reason "only the
admin may seat AI" lives there and not in `server.gd` (D-048). The lobby
packet already carries `map_settings.to_dict()` and is already
re-broadcast on every seat change, so the client's preview, its spawn
markers (D-104) and the server's generator all follow with nothing new on
the wire.

**Why clamped, and why reverted rather than refused.** Two is
`MapSettings.validate`'s own floor, and a one-seat lobby is an ordinary
state on the way to a match rather than an error. At the other end, a
small map may not seat everyone at `min_spawn_spacing`; the server already
tolerates that — it warns and plays on, sharing starts (server.gd's
"not fatal: a short-seated map still plays") — so a seat change that would
produce an invalid config keeps the previous value instead of rejecting
the player. Refusing to seat somebody because the map is small would be a
worse answer than a warning.

**Why the seed row goes but the seed mechanism stays.** `--seed` and
replay reproduction (D-100) both pin, and `set_map_option("seed", ...)` is
how. Removing the option would have taken those with it, so only the row
went. What a player wants from that row is a *different map*, and the
Reroll button beside it already did exactly that — the server draws the
number, and asking leaves it unpinned so the lobby keeps rolling between
matches.

## Rejected alternatives

- **Hide the rows, keep `player_slots` settable.** The smaller change, and
  it leaves the default wrong: three players still get a twenty-start map,
  which is the half of the report that is about how the match plays rather
  than how the panel looks.
- **Derive it at read time instead of on seat change** — e.g. have the
  spawn config ask the match for a count. Rejected because
  `map_settings.to_dict()` is the wire payload the lobby preview and the
  server generator both read, so the number has to be *in* the settings;
  computing it somewhere else would leave two answers again, which is the
  defect being fixed.
- **Grey the rows out for non-admins and leave them for the host.** The
  host has no more of an opinion about how many starting positions a
  four-seat lobby wants than a guest does.
- **Clamp the seat count to what the map can seat, refusing joins past
  it.** Turns a warning into a lockout, and makes the map's size a
  moderation tool. The short-seated warning already exists and already
  says the right thing.

## Consequences

- `MatchState` gains `_seats_changed()`, `MIN_PLAYER_SLOTS`,
  `MAX_PLAYER_SLOTS`, and calls at all four seat-mutation sites
  (`_seat_human`, `add_ai`, `remove_ai`, `remove_human_seat`).
  `set_map_option` loses one case.
- `client.gd` loses two `MAP_OPTIONS` entries and `_map_row`'s `"int"`
  kind, which existed only for those two. A `"reroll"` kind replaces it:
  a button for the admin, "Chosen by the host" for a guest.
- **Spawn placement changes in every match, tests included.** A 4-bot
  `test-load` now generates 4 starting positions where it generated 20, so
  spawns are closer and the armies are in contact. Measured, `4 150`,
  same host, current `main` once and this branch twice:

  | tree | verdict | conceal | reveal | ghosts_peak | µs/squad @ 34 squads | worst tick |
  |---|---|---|---|---|---|---|
  | `main` | FAILED | 2 | 0 | 2 | 47.25 | 24.7 ms |
  | branch | ok | 16 | 1 | 15 | 58.04 | 38.8 ms |
  | branch | FAILED | 15 | 0 | 15 | 62.25 | 46.6 ms |

  Three things to read out of that, in descending order of confidence.

  **Conceal roughly EIGHTFOLDS and repeats** (2 → 16, 15; `ghosts_peak`
  2 → 15, 15). Squads now enter and leave each other's vision constantly,
  where on a 20-start map four bots barely met. That is the change doing
  what it says.

  **The clean verdict did NOT repeat, and must not be read as fixing
  #69.** `reveal_events` — which needs a conceal AND a return, and is the
  last fog gate to be satisfied — went 1 then 0, against `main`'s 0.
  `docs/status/load-testing.md` records that gate failing on `main` in
  four runs of five and warns in as many words that a single green run is
  not a measurement; quoting the one clean run here would have been that
  exact mistake. What can be said is that this branch is **no worse than
  `main`** on it, and that the conceal half suggests where to look:
  contact, not fog.

  **The per-squad cost rises 11–15 µs at the same 34 squads, and all of
  it is vision + combat** (10.3 → 13.7 and 25.6 → 34.1). That is armies
  being in range of each other, not slower code — nothing per-tick
  changed. Quote it with its squad count, as ever, and note the host was
  running another session's load test during the third run. 0 desyncs and
  0 dropped ticks in all three; worst tick well inside D-020's 100 ms.
- The lobby's spawn preview now draws exactly as many markers as there are
  players, which is the first time that picture has meant anything
  (D-104 fixed the markers; this fixes their number).
- One fewer settings row makes the GAME SETTINGS panel shorter, which is
  slack for D-20260817-lobby-fits-the-window's `DESIGN_HEIGHT` pin rather
  than pressure on it.

## Revisit trigger

A lobby that wants a map deliberately larger than its seat count — a
2-player match on a 20-start world, for the space rather than the
opponents. That is a real preference and this decision cannot express it;
the shape it would take is a MAP SIZE choice (which already exists) plus a
spacing preference, never a re-exposed slot count. Also: any future seat
mutation added outside `MatchState`, which the source-scan half of
`tests/test_starting_positions.gd` is there to catch.
