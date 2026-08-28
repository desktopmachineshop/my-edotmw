# D-20260827 · 2026-08-27 · Accepted — a client record forgets the match it left

**Decision:** a per-client record on the server has ONE definition of its
birth shape, `server._fresh_record(player)`, and a return to the lobby
replaces every record with a fresh one rather than clearing a list of
named keys. Three clauses:

1. **A record is a player id plus per-MATCH baselines, and nothing
   else.** `visible` (D-025's reveal/conceal diff), `known_buildings`
   (D-030's ever-revealed set, which the server HASHES), `nodes_known`
   and `nodes_depleted_told` (D-061/D-087's persistent-explored resource
   sets). Every one of them is keyed by an entity id or a cell index,
   and both sims mint ids from an array length while cell indices are a
   property of the map SIZE — so the next match reuses exactly the
   identifiers the last one used.
2. **`_return_to_lobby` scrubs to the birth shape**, so a baseline added
   later is cleared for free. This is the clause the whole entry exists
   for: the reset was a hand-maintained list of keys twice, and was
   incomplete both times.
3. **`_fresh_record` is the only place a record is minted**, at both
   call sites — `_on_connect` for a socket and `_seat_ai` for a
   LoopbackPeer (D-051) — and `tests/test_client_record.gd` fails if
   anything writes a key onto a record that `_fresh_record` does not
   mint.

## Rationale

The failure is silent by construction, and that is what makes the list
form unacceptable rather than merely untidy. A surviving baseline does
not corrupt anything: it makes the server believe it has *already told*
this client about a building or a forest, so the thing now standing
there is simply never sent. Nothing errors, nothing is dropped, and the
client is missing information it has no way to know it is missing.

Two instances have been paid for, and they are the same bug:

- **`known_buildings`** survived for as long as leaving to the lobby has
  existed. The sandbox Regen button made it a one-click repro and it was
  fixed then (`D-20260821-the-sandbox-panel-runs-the-world`): 106
  building desyncs in 55,239 checks in one playtest.
- **#157 is the quieter half of the same defect**, reported before that
  fix landed: match two's town centre takes match one's id, the server
  finds it already known, sends no `BUILDING_INFO` — and then hashes it
  anyway, because D-030 requires the hash to be over the ever-revealed
  set. Client and server each hash a constant, the two differ, and it
  HEALS the moment anything marks that building dirty and the ordinary
  resend delivers it. Four desyncs, ticks 340-370, then silence. A
  transient self-correcting desync produces no visible artefact most of
  the time, which is exactly why it survived.
- **`nodes_known` and `nodes_depleted_told` were still live** when this
  entry was written, and are the third and fourth instances. They are
  invisible to the desync counter because nodes are not hashed at all,
  so their symptom is only ever "the second match's forests are missing
  from a patch of ground" or "that tree never falls" — which is what
  *"lots of strange bugs on restarting a game from lobby"* sounds like
  from the chair.

**The list is the defect.** Naming keys means the reset is correct only
while somebody remembers to extend it, and the evidence is that nobody
did, twice, in a codebase whose whole discipline is writing rules down.
A birth shape inverts the default: a new baseline is cleared unless
somebody goes out of their way to mint it somewhere else, and the test
below catches that too.

## Rejected alternatives

- **Clearing the record entirely (`_clients[peer] = {}`) and letting
  `record.get(k, {})` rebuild it.** It works today and hides a real
  hazard: `player` is NOT per-match — the server does not reissue player
  ids across a return to the lobby, and a record that lost it would
  refuse every subsequent order from that peer with "does not own". The
  birth shape carries the one field that must survive, which is the
  distinction worth making explicit.
- **Dropping the whole `_clients` entry and re-admitting on the next
  match start**, as `_ai_clients` does. AI records can be dropped
  wholesale because their brains go with the world; a socket's cannot —
  the peer is still connected, still in the lobby, and `_clients` is
  keyed by it.
- **Fixing only the two node sets and leaving the reset a list.** That
  is the fix that was applied twice already.
- **Making the reset a loop over the record's own keys, skipping
  `player`.** Nearly right, and it fails open in the wrong direction: a
  key a match never happened to write is never cleared, so the shape
  depends on what the last match did rather than on what a record IS.

## Consequences

- **The two node sets are fixed**, which is a behaviour change and not
  only a tidy-up: a second match's resource nodes now reach a client
  that played the first, and a felling in the second match is reported
  rather than swallowed.
- **A new per-client baseline goes red in `test_client_record.gd`**
  rather than in a playtest of somebody's second match, which is the
  only place the last two were ever going to show up. The scan is the
  same shape as `test_terrain_fog.gd`'s caller-exists scan and
  `test_multi_agent_isolation.gd`'s literal scan, and it answers D-106's
  own caveat about those: it enumerates the class from the source rather
  than from a list in the test.
- **`server.gd` is testable end to end for this**, without a socket or a
  scene tree. It is instantiated and never added to the tree, so
  `_ready()` does not run — the same distinction D-075's 2026-08-16
  amendment had to make for `client.gd`, and the same one
  `D-20260823-a-civs-knobs-are-read-by-the-simulation` relied on. A
  `LoopbackPeer` in `_clients` is safe for these paths because
  `_broadcast_lobby` and `_replicate` call `send()` and nothing else,
  and both say so.
- **`just test-load` still cannot reach any of this**, because it never
  returns to a lobby. That gap is unchanged and is why #157 was found by
  a human playing twice.

## Revisit trigger

Any per-client state that is NOT a per-match baseline and NOT a player
id — a preference, a protocol version, a SteamID seat identity (D-090
proposes exactly that) — reopens clause 1, because the birth shape would
then have to distinguish "survives a match" from "survives a session".
That is a real distinction and it should be made in a decision rather
than by adding a second exception beside `player`.
