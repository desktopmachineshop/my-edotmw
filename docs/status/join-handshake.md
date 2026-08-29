**The join flow carries a protocol version, and did not for seven
milestones** (`D-20260827-the-join-flow-carries-a-protocol-version`,
#179, D-094 criterion 3, 2026-08-27). A client's first packet after
connecting is now a HELLO carrying `NetProtocol.PROTOCOL_VERSION` and
its build string; the server admits nobody until it arrives, and a
mismatch is refused with a message naming both builds and what to do.

Before this the protocol had **no version field at all**, so a stale
build meeting a new server produced confusing desyncs instead of a
refusal. Steam's rolling updates make mixed versions routine (D-094's
own rationale) — and alpha testers self-updating from zips are worse at
staying current than Steam is, which is why this landed before the first
tester build rather than with the Steam work.

Six things to know before touching the join path:

- **The protocol version is its OWN number.** Not the build version:
  two builds can differ in art, balance or a bug fix and speak the same
  wire, and refusing those makes every hotfix a flag day. The build
  strings ride along for the MESSAGE, because "protocol 1 vs 2" is not
  something a player can act on.
- **Nobody is admitted before the handshake.** `_on_connect` records a
  *pending* peer and nothing else; `_handle_hello` is the one door into
  `_admit_connection`. Admitting first would spend a player id, a seat
  and a lobby broadcast on somebody about to be thrown out. A pending
  peer's other packets are dropped in **silence** — a wall of "unknown
  opcode" is the confusing symptom this replaces.
- **The refusal is a wire event, not a bare disconnect** — D-025's
  conceal rule applied to joining. A client cannot otherwise tell
  "refused" from "the server is down" from "merely late", and those want
  three different things from a player. The sentence is composed at the
  RECEIVING end from the server's numbers and the reader's own, so it
  cannot be half a build old, and no prose from the network reaches a
  label.
- **`gate-check.sh handshake` is the fourth comparison, and both
  `test-load` and `test-scenario` make it.** It reads **accepted**,
  against the bots' own count of who connected — never `refused == 0`,
  because zero refusals is what a working run, a run nobody joined, and
  a handshake that is not wired up at all *all* report.
- **`just test-handshake` is where the REFUSAL is proved.** Every binary
  here is built from the same `net_protocol.gd` and agrees with itself
  by construction, so nothing else in the estate can reach that path.
  The recipe drives `just run-bots-protocol` (bots claiming a version
  derived from the real one, never typed) at a real server over a real
  socket, and fails unless it is refused with an actionable message
  **and** a matched build is admitted in the same run — a server that
  refused everybody would pass the first half perfectly.
- **`--protocol=N` makes the bot LIE, and the refusal still quotes its
  real constant.** The message a `test-handshake` run prints says *"Your
  build: 0.1.0-alpha (protocol 1)"* while the bot claimed 2, because the
  client composes the sentence from its own `PROTOCOL_VERSION` — which
  is right for every real mismatch (a genuinely stale build's constant IS
  its version) and only looks odd for the synthetic one. Read it as the
  harness lying, not the message.
- **A refused peer can no longer shut the server down.** Found while
  writing that recipe: D-075 ends a server when the last human client
  leaves, and `_on_disconnect` was reaching that rule for a peer that
  had never been admitted — so one connection from the wrong build would
  have ended a match anybody could have been in. **A server anybody
  could stop by double-clicking the wrong zip.** The guard is `record ==
  null`.

**Known and accepted: nothing enforces that `PROTOCOL_VERSION` is
bumped.** A wire change with the number left alone is indistinguishable
from no wire change at all. The decision entry names the alternative (a
derived protocol hash) and why it is not here yet; the tests do assert
that no two opcodes share a number, which is the one collision a wire
protocol cannot recover from.

**Deliberately not here:** the SteamID seat identity half of D-094
criterion 3 — it lands with reconnection (D-090), where a seat becomes
rebindable and an identity starts to mean something. And the refusal
currently ends the session at a screen with a Quit button, because there
is nowhere else for it to go; #180 gives the client a pre-connection main
menu, and a refusal belongs *there*, with the address still in the field.
