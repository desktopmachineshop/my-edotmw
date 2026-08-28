**A player can host from inside the game**
(`D-20260828-the-host-runs-the-server-inside-its-own-client`, #182, D-088,
2026-08-28). #180's Host button was drawn disabled pointing at this
ticket; it works now. The client starts the authoritative server in its
**own process** and joins it through the loopback peer D-051's AI seats
already use; remote players arrive over the ordinary socket. The
dedicated `server.gd` path is untouched — docker, the bots and the whole
test estate never see any of it.

```
just test-host 2 60 1     # a real hosting client, real bots joining it
```

**It cost very little, and D-051 is the reason.** `loopback_peer.gd`
exists because a peer is duck-typed to `ENetPacketPeer.send`'s shape, so
the server→client direction was already built and tested; `host_link.gd`
is its mirror image for orders. **The ~30 sites in `client.gd` that order
a squad, produce a unit or set a formation are the same code either way**
— which is the point rather than an economy: a host cannot be handed a
rule a guest does not have, because there is no branch in which to give
it one.

Seven things to know:

- **One simulation, not two.** The embedded server IS `server.gd`,
  reached by composition and ticking on its own D-023 accumulator beside
  the client's. #182 named the alternative and its cost: a host-only
  variant would be `just profile`'s blind spot with a new name.
- **The host lands in the ORDINARY LOBBY as admin**, so a remote player
  can join before the match starts — which is the difference between
  hosting and a hotseat.
- **An embedded server reads `boot`, never the command line.** Those
  arguments belong to the CLIENT, and `--port` means "connect to" there
  and "bind" on a server: a host launched to join port N would silently
  have bound N.
- **`_local_clients` is a THIRD dictionary.** Not `_clients`, where
  several places legitimately treat a key as a real socket and an
  impostor is a null cast waiting to happen; not `_ai_clients`, because
  the host is a human and calling it an AI is a lie the next reader has
  to un-learn.
- **D-075 is gated on `_embedded`.** "No humans, no server" fires when
  `_clients` empties, and the host is not in `_clients` — so without the
  guard the last REMOTE player leaving would quit the host's own game
  underneath them. Gated on `_embedded` rather than "is there a local
  client", so a dedicated server still ends exactly as before.
- **`_peer_of` stopped being typed `ENetPacketPeer`.** Left as it was,
  the host was the one player `_on_match_started` could not admit — and
  it would have failed by returning **null**, so the symptom would have
  been a host who starts a match and is not in it.
- **`_process`'s connection test is `_host == null and _hosted_server ==
  null`.** Read as "is there a socket", a hosting client ticks its server
  and renders nothing.

**A defect found on the way, and it is the third of its kind (#253).**
`_handle_chat` relayed to `_clients` alone, so **AI seats have never
received chat** — free, because an AI does not read it, which is exactly
why it survived two milestones. It stops being free when a non-socket
peer is a HUMAN: a hosting player saw no chat at all, including their
own. `_recipients()`'s own doc comment already records the previous two
instances of this drift.

**Measured, `just test-host 2 60 1`** — real hosting client, two real
bots over a real socket: **0 desyncs in 80 host-side comparisons and 88
bot-side**, 0 building desyncs, **0 dropped ticks of 800**, worst tick
**46.7 ms** against D-020's 100 ms with client and server in one process,
**302.99 µs/squad at 25 squads**.

**Read that with its condition attached: the client half was HEADLESS.**
It did no GPU work, so the number says the two accumulators coexist
without starving each other and says **nothing** about what a host pays
with a real frame on screen. That measurement wants `bench-render`-class
hardware and a human; it is owed, and named here rather than implied.

**Accepted with eyes open, both straight from D-088:** host-quit kills
the match for everyone, and the host is trusted. Dedicated-later is the
real fix for both, and neither is engineered around here.
