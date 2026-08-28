### D-20260828 · Accepted — the host runs the server inside its own client, and the loopback was already there

**Decision (M8, issue #182, building D-088):** pressing **Host** starts
the authoritative server **in the client's own process** and joins it
through the loopback peer D-051's AI seats already use. Remote players
arrive over the ordinary socket. The dedicated `server.gd` path is
unchanged — docker, the bots and the whole test estate never see any of
this.

**It cost very little, and D-051 is why.** `loopback_peer.gd` exists
because a peer is duck-typed to `ENetPacketPeer.send`'s shape, and the
replication loop has never needed to know which it is talking to. So the
server→client direction was already built and tested. What was missing
was the other one, and `host_link.gd` is its mirror image: an object
whose `send()` hands the packet to `_dispatch`. **The ~30 sites in
`client.gd` that order a squad, produce a unit or set a formation are
byte-for-byte the same code whether the player is hosting or joined over
a socket** — which is the point, not an economy. A host cannot be given a
rule a guest does not have, because there is no branch in which to give
it one, and that difference would have been invisible (D-051's own
argument about an AI that quietly sees more).

Six things, each of which had an alternative:

**1. One simulation, not two.** The embedded server is the same
`server.gd` the dedicated build runs, reached through composition:
configured, added to the tree, ticking on its own D-023 accumulator
beside the client's. #182 named the alternative and its cost — a
host-only variant would be `just profile`'s blind spot with a new name, a
workload with its own bugs, green while the shipped one is broken.

**2. The host lands in the ORDINARY LOBBY, as admin.** That is what a
host wants — pick the map, add AI, wait for a friend, press start — and
it means a remote player can join *before* the match begins, which is the
difference between hosting and a hotseat. It also reuses every tested
path rather than inventing a start-a-match-now shortcut.

**3. An embedded server is configured by its client, never by the command
line.** `boot` is a dictionary in `CmdArgs.parse`'s shape, so everything
downstream of `_ready`'s first lines is untouched and there is no second
start-up path. The command line was not merely irrelevant, it was
*dangerous*: `--port` means "connect to" on a client and "bind" on a
server, so a host launched to join port N would have silently bound N.

**4. A THIRD client dictionary.** `_local_clients`, not an entry in
`_clients` or `_ai_clients`. Not `_clients` for the reason
`loopback_peer.gd`'s header already gives — several places there
legitimately treat a key as a real socket (`_sample_transport`'s ENet
statistics, `(peer as ENetPacketPeer).send`) and an impostor among them
is a null cast waiting to happen. Not `_ai_clients` because the host is a
**human**: it holds a human seat, it is the admin, and calling it an AI
is a lie the next reader has to un-learn.

**5. D-075 must not end a host's process.** "No humans, no server" fires
on a disconnect when `_clients` is empty — and the host is not in
`_clients`, so without a guard the rule would read "everybody left" the
moment the last *remote* player disconnected and quit the host's own game
underneath them. Gated on `_embedded` rather than on "is there a local
client", so a dedicated server still ends exactly as it did: D-075 exists
because an all-AI server held a port for six hours, and un-fixing it here
would have been a silent regression in the docker estate.

**6. `_peer_of` stops being typed `ENetPacketPeer`.** Left as it was, the
host would have been the one player `_on_match_started` could not admit —
and it would have failed by returning **null**, so the symptom would have
been a host who starts a match and is not in it.

**A defect found on the way, and it is the third of its kind.**
`_handle_chat` relayed to `_clients` alone, so **AI seats have never
received chat** — free, because an AI does not read it, which is exactly
why it survived. It stops being free when a non-socket peer is a HUMAN: a
hosting player saw no chat at all, including their own, and the
`as ENetPacketPeer` cast would have handed a null to `.send` the moment
anybody else spoke. `_recipients()`' own doc comment records the previous
two instances. Fixed here and filed as **#253**, with the suggestion that
the rule deserve a source-scanning test rather than a paragraph of prose.

**Measured, 2026-08-28, `just test-host 2 60 1`** — a real hosting client,
headless, with two real bot clients joining it over a real socket:

- **0 desyncs in 80 state-hash comparisons host-side, 0 desyncs over 88
  bot-side**, 0 building desyncs either way;
- **0 dropped ticks of 800**, worst tick **46.7 ms** against D-020's
  100 ms, with client and server in the SAME process;
- **302.99 µs/squad at 25 squads** (combat 146.61, separation 76.48,
  vision 34.47) — quoted with its count, as ever.

**Read that worst tick with its condition attached: the client half was
HEADLESS**, so it did no GPU work at all. #182 asks for a host-machine
number and this is the honest half of one — it says the two accumulators
coexist without either starving the other, and it does **not** say what a
host pays with a real frame on screen. That measurement needs
`bench-render`-class hardware and a human, and it is named here rather
than implied.

**Rejected alternatives:** *spawning the exported server as a child
process* — not D-088's in-process host, needs a built binary a checkout
does not have, and would have to be undone by the real thing. *Giving the
host privileged access to `SquadSim`* — D-051 refused exactly this for AI
and the argument is stronger for a human. *Starting the match immediately
rather than opening a lobby* — a host who cannot wait for a friend is not
hosting.

**Consequences:** `client.gd`'s `_peer` is untyped (it is an
`ENetPacketPeer` or a `HostLink`), and `_process`'s "is there a
connection" test is `_host == null and _hosted_server == null` — read as
"is there a socket", a hosting client would tick its server and render
nothing. `--host=1` / `--host-port` / `--host-ai` exist so hosting can be
driven headlessly by `just test-host`; the port is per-instance in the
recipe (D-095) and the shared default only for a player, who needs one
number to tell a friend.

**Accepted with eyes open, both from D-088 and neither engineered
around:** host-quit kills the match for everyone, and the host is
trusted. Dedicated-later is the real fix for both.

**Revisit trigger:** the Steam peer wrapper (#184), which must slot in
beside ENet without the host path learning about it — if it cannot, the
seam is in the wrong place; or a measured case of a host's machine
failing to carry both halves, which is the number named above as still
owed.
