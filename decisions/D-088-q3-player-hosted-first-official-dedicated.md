### D-088 · 2026-08-14 · Accepted — Q3: player-hosted first, official dedicated later

**Decision (the owner's call, 2026-08-14):** at first ship, matches are
**player-hosted**: the host player's machine runs the authoritative
simulation, and remote players connect over **Steam's networking with
relay** (SteamNetworkingSockets / SDR via D-093's boundary), so NAT and
port-forwarding never reach a user. **Official dedicated servers are a
later rung**, not M8 — they are also the eventual fix for the two
limitations this decision knowingly accepts (host-quit and host-trust,
below).

**The measured basis that makes hosting-while-playing viable.** This
question was written when "who pays for servers" looked expensive.
M4/M6 made it small: bandwidth is ~1 KB/s per client (D-042's 933 B/s at
20 players) — 19 remote clients cost a host about **20 KB/s of upload**;
the server is roughly **half a core and ~42.5 MB** at full scale
(D-038/D-040). A machine that can run the client (the expensive half —
D-041) hosts the simulation without noticing.

**Process shape: in-process host, and `loopback_peer.gd` already built
the seam.** The host's game runs the server *in-process* — the same
`SquadSim`/`server.gd` machinery, ticked by D-023's accumulator — with
the host's own client connected through the loopback peer that D-051's
AI clients already use, and remote clients arriving through Steam
sockets. This is not a new architecture: `bot_client.gd` proves N
clients in one process, and `loopback_peer.gd` exists precisely because
a peer is duck-typed to `ENetPacketPeer.send`'s shape. A Steam peer
wrapper implements the same shape behind D-093's boundary. D-002's
authority split (clients send input, server decides) is a protocol
property, not a process property, and is unchanged.

**D-042's contract is a hard requirement on the new transport.** Curve
packets carry no sequence number; in-order reliable delivery is
load-bearing. Steam sockets must run reliable-ordered, and the ordering
test D-042 named
(`test_curve_application_is_last_write_wins_so_order_is_load_bearing`)
applies to the Steam path exactly as to ENet. **ENet stays** for
LAN/direct-IP, docker, bots and the whole test estate — containers have
no Steam and never will, so every existing recipe keeps running without
it (see D-093's fallback rule).

**Two consequences accepted with eyes open:**
- **Host-quit kills the match** for everyone in it. No host migration —
  authoritative-state handoff is a milestone of its own and a fresh
  cheating surface (whoever inherits the server inherits omniscience).
  Dedicated-later is the real fix; until then it is a documented
  property of unranked play.
- **The host is trusted** — they hold the whole truth and the authority.
  D-091 owns this consequence.

**Rejected alternatives:** *Official dedicated first* (recommended by
the analysis for keeping ENet untouched, declined by the owner — player-
hosted reaches playtesters without standing infrastructure or monthly
cost, and the Steamworks integration it forces is needed for D-089's
lobbies anyway). *Player-run headless server as a separate process* —
splits the Steam context across processes (the listen socket needs the
game's Steam session) and buys nothing the in-process shape doesn't.
*Host migration* — see above.

**Revisit trigger:** ranked/competitive play (requires dedicated — see
D-091); playtests showing the host's 0-RTT advantage is felt in play; or
a measured case of host upload/CPU being the binding constraint at real
player counts.

---
