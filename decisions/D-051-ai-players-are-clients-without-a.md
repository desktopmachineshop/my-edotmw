### D-051 · 2026-08-02 · Accepted — AI players are clients without a socket
**Decision:** An AI player holds a real `ClientState` and is fed by the
server's ordinary `_replicate()` loop through a `LoopbackPeer` — an
object whose only job is to expose `send(channel, packet, flags)` and
hand the bytes to that ClientState. Its decisions become real
`NetProtocol` packets, handed to the server's own dispatcher.

**Rationale: fog has to be a property, not a promise.** D-046 criterion 9
requires an AI to see only what a human in its seat would. The obvious
implementation — let the AI read `SquadSim` and be careful — makes that a
convention one refactor can quietly break, and the failure mode is
invisible: **an AI that sees through fog does not look like a bug, it
looks like a good AI.** Nobody finds that by playing.

Feeding it the same packets makes the guarantee structural. There is no
code path by which an AI can learn about a squad the server did not send
it, because the only thing it has is a ClientState and the only thing
that writes to it is `handle_packet`. This is the same reasoning that
made `bot_client.gd` drive the real ClientState rather than an imitation
(D-018), applied where the stakes are higher.

**Orders take the same road.** An AI's decisions go through
`_dispatch()`, the same function a socket's packets go through, so
ownership read from the sim, the squad cap, affordability and "is the
match running" all apply unchanged. An AI calling into the simulation
directly could do things no human could, and nobody would notice until
they wondered why it never ran out of food.

**Consequences:** the replication loop needed a two-line change — merge
`_ai_clients` into the recipients — rather than a branch, which is the
whole point of the loopback shape. Several `peer` parameters became
untyped, and GDScript's type checker found every one of them
immediately, which is the right kind of failure. `LoopbackPeer` is
deliberately NOT a subclass of `ENetPacketPeer` and deliberately kept out
of `_clients`: real sockets are legitimately treated as sockets there
(ENet statistics, the lobby broadcast), and an impostor in that
dictionary would be a null cast waiting to happen.

`bot_client.gd`'s role is now distinct: it stays the LOAD-TEST harness,
driving N virtual clients over a real socket. The in-game AI is a
different job, and conflating them would give the load test a stake in AI
quality.

**What this AI is not:** good. It founds a town, gathers, trains, and
attacks the nearest enemy it can see. D-046 makes AI a shipped feature,
so this is the floor to build on rather than a scripted demo — and
because it plays through the client interface, improving it cannot
accidentally grant it privileges.

**Rejected alternatives:** Privileged access to SquadSim with a
"don't cheat" convention (rejected — see above). Running AI as separate
processes connecting over ENet (rejected — a real socket per AI seat
costs a connection and a scheduler slot to buy nothing; the loopback is
the same guarantee without the transport). Putting AI in `_clients`
(rejected — null casts, above).

**Revisit trigger:** If an AI seat's ClientState becomes a measurable
share of server memory or tick time at D-018's scale, the answer is a
narrower view object with the same gating, not privileged access.

---
