**The transport is a seam now, and ordering is a contract something can
fail** (`D-20260828-a-transport-is-a-seam-and-ordering-is-the-contract`,
#184, D-094 criterion 5, 2026-08-28). `server.gd` and `client.gd` reach
the network through `net_transport.gd`; `enet_transport.gd` is the
incumbent, unchanged in behaviour. Neither file contains the string
`ENetConnection` any more, and a test asserts that — a seam with one
caller still reaching around it is a seam that will grow a second
implementation nobody can use.

Six things to know:

- **The seam keeps ENet's vocabulary, value for value.** The five event
  constants ARE `ENetConnection`'s, and `poll()` returns `[type, peer]`
  exactly as `service()` does, so adding a second transport was an
  addition beside the netcode rather than a rewrite of it. A test asserts
  the constants match: if Godot renumbered them every event would be
  misrouted **silently**, a connect handled as a disconnect.
- **Peers stay duck-typed to `ENetPacketPeer.send`.** Three
  implementations agree on that shape now — `LoopbackPeer` (D-051),
  `HostLink` (#182) and ENet's — which is what makes "an AI seat, the
  host and a remote player take one code path" structural.
- **ENet telemetry deliberately does NOT go through the seam.** RTT,
  packet loss and throttle are statistics of ONE transport; Steam's
  equivalents are different quantities, and averaging them into one peak
  would produce a table whose columns do not compare. A relay run reports
  its numbers BESIDE D-042's, never into them.
- **Ordering is falsifiable for the first time.**
  `tests/test_transport_ordering.gd` drives D-042's scenario through the
  seam with two fakes — one honest, one reordering — and asserts the
  honest one agrees with the server **and the reordering one does not**.
  A test that only checked the good case would pass against a transport
  with no ordering guarantee at all. Observed to fail.
- **The mapping is decided: ENet channel N is Steam lane N**, the
  identity, because both guarantee ordering per stream rather than
  globally. **The send flag is the dangerous half** — Steam offers
  unreliable sends on the same connection, and reaching for them (for the
  reasonable-sounding reason that position updates are usually fine to
  drop) produces exactly the desync class the state-hash machinery exists
  to catch. Reliable only.
- **`Platform.can_carry_a_socket()` returns false even WITH Steam
  present**, and says why. Reporting true on the strength of Steam merely
  being available would pick a transport that does not exist — and only
  on machines that have Steam, never on any machine that runs the tests.

**The boundary had to be renamed, and the reason is worth keeping.**
#181 built `SteamPlatform` plus a test forbidding any other `.gd` from
naming Steam. **The first consumer found that no file can call it** —
`SteamPlatform.foo()` names Steam — so it passed its own guard only
because nothing called it. That is the declared-and-unread shape arriving
in the *guard* rather than in the feature. It is `Platform` now, which is
also the better abstraction: nothing outside that file should care that
the platform is Steam, and D-093's fallback ladder is live
(`D-20260828-godotsteam-does-not-ship-a-gdextension`).

**The rule's next collision was found the same way and solved rather than
deferred.** The guard reads code, and a string literal is code — so an
assertion message tripped it, and #187's lobby browser will have to put
the word on a button. User-facing text comes from
`Platform.display_name()` now: one place decides what the platform is
called, exactly as `player_colours.gd` decides a player's colour (D-052).
The boundary's test asserts the sharper thing instead of counting the
word: every `has_singleton` / `class_exists` / `get_singleton` is called
with the `SINGLETON` constant, never a literal.

**ENet is proven unchanged.** `just test-load 4 120` twice on this
branch: clean both times, all four gate checks green, **0 desyncs over
476 state-hash checks**, 0 dropped ticks, and **151.00 µs/squad at 32
squads** on the second — against #179's **150.79 at 33** on the same map.
The first sample read 174.61, and the phase breakdown identified it as
the host before the second run existed: every phase rose 14–17%
*including* combat, vision, economy and separation, which a transport
seam cannot touch, while the residual `other` did not move. One green run
is not a measurement; two are why this is a sentence rather than a
worry.

**Human remainder, named rather than stubbed:** the Steam wrapper itself,
a real match over Steam sockets with zero desyncs over a reported number
of comparisons, and D-042's RTT and loss re-taken on the relay path. All
three need a Steam runtime, an app id and an account.
