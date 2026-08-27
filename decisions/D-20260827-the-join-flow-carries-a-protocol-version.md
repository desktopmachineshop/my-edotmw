### D-20260827 · Accepted — the join flow carries a protocol version, and a mismatched build is refused before it is seated

**Decision (M8, issue #179, discharging the first half of D-094
criterion 3):** a client's **first packet after connecting is a HELLO**
carrying `NetProtocol.PROTOCOL_VERSION` and its build version, and the
server **admits nobody until it arrives**. A mismatch is answered with an
explicit `S2C_REFUSED` naming both builds and what to do about it, then
the peer is dropped. Before this the protocol had **no version field at
all**, so a stale build meeting a new server produced a scatter of
confusing desyncs rather than one sentence — a symptom that costs a
debugging session and ends in "you were on last week's build".

Six calls, each of which had an obvious alternative:

**1. The protocol version is its OWN number, not the build version.**
Two builds can differ in art, balance or a bug fix and still speak the
same wire; comparing build strings would make every hotfix a flag day
and would stop a playtester joining over a typo in a changelog. So the
comparison is on `PROTOCOL_VERSION` (bumped whenever a change would make
an older build misread this one's packets) and the **build strings ride
along for the MESSAGE** — because "protocol 1 vs protocol 2" is not
something a player can act on and "your build is 0.1.0, the server is
0.2.0 — update" is.

**2. Client-first, and the server admits nobody before it.** The
alternative — admit, then check — spends a player id, a seat, a lobby
broadcast and possibly an opening on somebody about to be thrown out,
and D-033's seat lifecycle is not something to run backwards. So
`_on_connect` now records a *pending* peer and nothing else;
`_handle_hello` is the one door into the old admission body
(`_admit_connection`). A pending peer's other packets are dropped **in
silence** rather than `push_error`'d: a build on the wrong protocol may
be sending perfectly well-formed packets of a shape this one does not
have, and a wall of "unknown opcode" is the confusing symptom this
ticket exists to replace.

**3. The refusal is a WIRE EVENT, not a bare disconnect** — D-025's own
rule about conceal, applied to joining. A client cannot otherwise tell
"refused" from "the server is down" from "the packet is late", and those
want three different things from a player. `peer_disconnect_later`, not
`_now`, because `_now` discards what is still queued and the refusal is
the whole point of the exchange.

**4. The sentence is composed at the RECEIVING end.** The wire carries
only the server's reason, protocol and build; `NetProtocol.refusal_text`
assembles the message from those plus the reader's own constants. One
definition of the wording, read by the client that shows it and by the
server that logs it — and no untrusted prose from the network reaching a
label. An unknown reason code still produces words, because a newer
server refusing for a reason this build has never heard of is exactly
the situation a version handshake creates, and a blank dialog is worse
than a vague one.

**5. A peer that never says hello is refused after five seconds.** It
exists for exactly one client: one built before this handshake did,
which will never send HELLO and would otherwise sit connected forever,
admitted to nothing, with nothing anywhere saying why — which is #162's
reported symptom arriving through a second door.

**6. `--protocol=N` on the bots, and `just test-handshake`.** Every
binary in this repo is built from the same `net_protocol.gd` and
therefore agrees with itself by construction, so nothing the existing
estate does can reach the refusal. The bots can be told to claim another
version; one recipe presents that to a real server over a real socket
and fails unless it is refused with an actionable message **and** a
matched build is admitted in the same run. The second half is not
decoration: a server that refused everybody would satisfy the first half
perfectly. That is the observed-to-fail rule made *permanent* rather than
performed once by hand and written up.

**The ACCEPT path is gated on every ordinary run.** `gate-check.sh`
gains a fourth comparison and both `test-load` and `test-scenario` make
it (the fast loop carries the gate — D-20260818). It reads **accepted**,
compared against the bots' own count of who connected, rather than
`refused == 0`: zero refusals is what a working run, a run nobody joined,
and a handshake that is not wired up at all *all* report, which is the
vacuous-pass shape `gate-check.sh` exists to refuse.

**A defect found while writing the recipe, and fixed here.** D-075 ends a
server when the last human client leaves, and `_on_disconnect` reached
that rule for a peer that had never been admitted. So one connection
from a build on the wrong protocol would have been refused, dropped, and
then taken the whole server down on its way out — **a server anybody
could stop by double-clicking the wrong zip.** The guard is `record ==
null`, and `tests/test_handshake.gd` holds it.

**Rejected alternatives:** *the version in the WELCOME* — that is the
server telling the client, which is the wrong direction: the server is
the one that must decide, and a client that has already been seated has
already cost the things above. *Refusing on the build STRING* — see (1).
*A version byte on every packet* — D-003's whole claim is bytes per
second, and a per-packet field pays forever for a fact that is fixed for
the life of a connection. *No timeout on a silent peer* — leaves the one
client this ticket is actually about (an old one) with the exact
behaviour it is meant to fix.

**Consequences:** `PROTOCOL_VERSION` is now a thing to bump, and nothing
enforces that it is bumped — a wire change with the number left alone is
indistinguishable from no wire change at all. That is knowingly accepted:
the alternative (hashing the protocol's own shape) is a real option and
is named in the revisit trigger, but a hash that changes on a comment
would refuse builds that agree perfectly, and a hash that does not would
need to be told what counts. `tests/test_handshake.gd` at least asserts
that no two opcodes share a number, which is the one collision a wire
protocol cannot recover from.

**Deliberately not here:** the **SteamID seat identity** half of D-094
criterion 3. It lands with reconnection/repossession (D-090), where a
seat becomes rebindable and an identity starts to mean something; #179
says so itself. And the refusal currently ends the session at a screen
with a Quit button, because there is nowhere else for it to go — #180
gives this client a pre-connection main menu, and a refusal belongs
*there*, with the address still in the field and a "join again" button.

**Revisit trigger:** the first time a wire change ships with
`PROTOCOL_VERSION` left alone (the manual-bump risk becoming real, at
which point a derived protocol hash is the answer); or Steam's peer
wrapper (D-088/D-093) arriving, since the handshake must ride that
transport identically and its ordering guarantee is what makes
"first packet" meaningful at all (D-042).
