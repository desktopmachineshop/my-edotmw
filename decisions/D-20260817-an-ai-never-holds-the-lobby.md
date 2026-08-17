# D-20260817 · 2026-08-17 · Accepted — there is ONE way to seat an AI, and an AI never holds the lobby

**Decision:** `MatchState` has exactly one AI-seating function, `_seat_ai`,
and two doors onto it:

- `add_ai_player(player, civ)` — the participant twin of `add_player`.
  Registers the player for elimination and victory (D-033) and gives it an
  **AI seat**. This is what `server.gd`'s `_seat_ai` calls.
- `add_ai(by_player, civ, player_id)` — the lobby COMMAND. The same
  seating plus "only the admin may do this".

Two clauses follow from it:

1. **Both doors produce the same seat record.** `kind: "ai"`, named
   `AI <id>`, carrying the civ it was seated with. A seat's kind is not
   a matter of which code path happened to create it.
2. **`admin_player` is claimable only by a HUMAN seat.** `_seat_human`
   asks `_reassign_admin_if_needed()` — the function that already defined
   who may hold the chair — instead of testing `admin_player <= 0`.
   `_seat_ai` does not touch it at all.

## Rationale

Reported from playtest #30 (issue #92): after ESC → leave to lobby in a
`just quick-test SANDBOX=1` session, the human cannot start another match.
The start button reads **"Waiting for host"** and the Admin badge sits on
**Player 1000 — an AI**. All three AI seats are also labelled `human`.

The live log, from the session:

```
server: AI seated as player 1000 (northmen)
server: match started — Player 1000=legion (admin), Player 1001=northmen, ...
```

`quick-test` is `--ai=3 --players=1 --lobby=0`, so the AI seats are created
from the command line **before any human connects**. `server.gd`'s
`_seat_ai` registered each brain through `_match.add_player(player)` — and
`add_player` seats a *human*, and a human seat with nobody yet in the chair
takes `admin_player`. So the first AI became the lobby admin, and an AI
will never press start.

**This is the declared-and-misread variant of the family CLAUDE.md warns
about.** The field is not unread — the wire encodes it
(`net_protocol.gd:1032`), the client draws it (`client.gd:7628`), the
lobby's own remove/set-civ rules key off it, and `_on_match_started`
branches on it. It is simply **wrong**, on one of the two paths that write
it. `add_ai` set `kind: "ai"` correctly the whole time; every existing
lobby test went through `add_ai` and so could not see the other door. And
nothing failed: the first match plays perfectly.

**Four consequences, all confirmed against the code, three of them
invisible to any check:**

1. **A human can never start a second match** in any `--ai=N` session —
   `quick-test` and `run-server AI=3` — which is the whole of D-075's
   leave-to-lobby path for the session a solo player actually uses.
2. **AI seats display as `human`**, so every admin control that keys off
   `is_ai` (civ, team, remove) is hidden for them.
3. **A second match would seat no AI brains at all.** `_return_to_lobby`
   drops `_ai_players`/`_ai_clients` on purpose, because
   `_on_match_started` rebuilds them — from seats whose kind is `"ai"`. A
   `"human"`-kinded AI seat takes the `_peer_of` branch instead, finds no
   socket, and is skipped. The seat survives, still counts for elimination
   and victory (D-033), and can be defeated by nothing but the time cap:
   three inert players.
4. **The seat's civ was not the brain's civ.** `_seat_ai` builds the brain
   with a civ and records it in `_civs`; `_seat_human` then wrote
   `CivRoster.RANDOM` onto the seat, and `_on_match_started` re-resolved
   that and wrote it back over `_civs`. The log above shows exactly this —
   seated `northmen`, started `legion`. That is the defect `_seat_ai`'s own
   comment says it fixed ("reported one civilisation in AI_STATS and
   fielded another's troops for the whole match"), reachable again through
   the seat instead of through `_civ_of`'s modulo fallback.

**Why the admin rule is "human seat", not "empty chair".** `admin_player
<= 0` asks *is the chair empty*, which is the same question as *is anybody
in it who can use it* only for as long as nothing but a human can sit down.
`_reassign_admin_if_needed` already answered the question that was meant —
it is what hands the chair on when an admin disconnects — so the fix is to
ask it, not to write a second rule beside it. It also **repairs a session
already running with an AI in the chair**, which the empty-chair test
cannot: the first human to connect takes it back.

## Rejected alternatives

- **Fix `_seat_ai` to patch the seat after `add_player`** (set `kind`,
  overwrite the civ, clear `admin_player` if it landed on an AI). Shortest
  diff, and it leaves two ways to seat an AI that must be kept in step by
  care — which is the bug, restated. The next caller gets it wrong again.
- **Give `add_player` a `kind` parameter.** One door, but every existing
  call site gains an argument that is "human" 100% of the time, and the
  interesting asymmetry (an AI has a civ at seating; a human does not until
  the lobby resolves one) would be smuggled through a shared signature.
- **Let `server.gd` call `add_ai(0, civ, id)` with a sentinel admin.**
  Reuses one function by defeating its permission check. The check is a
  real rule about the lobby COMMAND; the seating is not the place for it.
- **Refuse `_seat_human` for ids ≥ 1000.** Makes the id range load-bearing.
  D-051 shares the id space between humans and AI on purpose, and D-052
  records what happens when a rule starts arithmetic on player ids.
- **Test it by standing up a real server.** `server.gd` needs a live
  `ENetConnection` and `_seat_ai` needs a built world to admit into. The
  rules live in `MatchState` for exactly this reason (its own header), and
  the one thing MatchState cannot see — *which door server.gd knocks on* —
  is covered by a source scan instead, the D-106 pattern.

## Consequences

- `match_state.gd`: `add_ai_player` and `_seat_ai` are new; `_register` is
  extracted from `add_player`; `add_ai` delegates to `_seat_ai` and returns
  `seat_of(player_id)` rather than `seats.size() - 1` (the same answer, and
  true even though the seating is now idempotent). `_seat_human` calls
  `_reassign_admin_if_needed`.
- `server.gd`: `_seat_ai` calls `add_ai_player`. Nothing else changed.
- **An all-AI server now has `admin_player == 0`.** `just ai-ladder`
  (`--players=0 --ai=N`) is unaffected: `require_admin_start` is false
  there, so `_start_if_ready` never consults the admin. Verified live —
  `ai-ladder 1 90` ran a real match and the log reads
  `match started — AI 1000=legion, AI 1001=northmen`, against
  `Player 1000=legion (admin), Player 1001=northmen` before.
- **The seat summary in the server log now names AI seats as AI.** That
  line is the cheapest live check that this is right, and it is the line
  the issue was filed from.
- Nothing per-tick, nothing on the wire, nothing in the simulation. The
  wire format already carried `kind` as a bool (`net_protocol.gd`); it now
  carries a true one.
- **Seven tests, each observed red against the pre-fix behaviour** before
  the fix was restored (the perturbation kept `add_ai_player`'s signature
  and pointed it back at `_seat_human`, so the reds are the behaviour and
  not a missing symbol). Five in `test_lobby.gd` — seat kind, the admin
  claim, repairing a lobby an AI already holds, the brain's civ surviving
  the seat, and the source scan on `_seat_ai`; two in
  `test_return_to_lobby.gd` for the reported symptom itself: a human can
  start the second match of a `--players=1 --ai=3` session, and the AI
  seats are still AI when it does. `just test-unit` green at 804 tests
  across 51 scripts.

## Revisit trigger

A third way to seat a participant appearing — a reconnecting player
repossessing an AI-held seat is exactly this shape and is already designed
(D-090, M8), where the seat's kind must flip from `ai` back to `human` and
the admin question is asked again. Also: the moment a lobby can be held by
somebody who is not currently connected, `_reassign_admin_if_needed`'s
"lowest human seat" needs a liveness term it does not have today.
