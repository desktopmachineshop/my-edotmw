### D-20260828 · Accepted — a game is FOUND, not typed

**Decision:** the pre-lobby menu (#180/#239) grows a **game browser** fed
by an array of **providers**. Two exist:

- **LAN**, built and working today — `lan_beacon.gd` answers on the
  server, `lan_discovery.gd` asks on the client, `lan_protocol.gd` is the
  wire between them. A player on the same network as a friend sees the
  game and clicks it, with no account, no service and nothing typed.
- **The platform's**, stubbed at D-093's boundary (#181) with the calls
  it will make written down. Absent — which is docker, CI, the bots,
  every test and any clone that has installed nothing — the array simply
  has one provider in it.

What a row SAYS and whether it can be pressed is `game_browser.gd`,
all-static and pure, exactly as #187 asks.

This is the ENGINEERING half of #187. The Steam half needs an app id, a
depot and an installed client — the owner's half — and this deliberately
does not pretend to it.

---

## Why a provider array rather than "the Steam browser, plus a LAN case"

D-089 scoped discovery to **lobbies, not matchmaking**, and #187 wrote it
as a Steam feature with the LAN case implied. Turned round, the LAN
provider is the one that can be finished, tested and played TODAY, and
the platform's is the one that cannot be run at all in any context this
repo automates.

So the shape is the one D-051 used for AI players and D-081 for a missing
`model_id`: **an absent integration costs fidelity, never function.**
`client.gd` holds providers and knows five methods; there is no platform
branch to be broken by, because there is no branch.

The platform provider is reached **by path** — `load("res://steam_platform.gd")`
— rather than by class name, because exactly one script in this project
may name the platform (D-093) and the menu is not it. That is not a
dodge: the boundary already existed and had **no caller at all**, which
is this project's declared-and-unread family waiting to happen. It has
one now, through the only door that keeps the grep test true.

## The wire is a QUESTION, not an announcement

The obvious design is a server shouting every few seconds and browsers
listening on a well-known port. It does not survive the dev loop, or an
ordinary household: **two clients on one machine both want to listen, and
a UDP port cannot be bound twice.** Godot exposes no `SO_REUSEPORT`, so
the browser would work for one player per computer — which is the
configuration every test of it runs in.

Asking instead puts the fixed port on the SERVER, where there is one per
machine per instance, and lets every browser bind an ephemeral port it
need not agree with anybody about. `tests/test_lan_discovery.gd` opens two
browsers on one machine and asserts both get a socket.

**The discovery port is DERIVED from the game port** (`game_port + 1`),
which is D-095 doing its job for free: every worktree already has its own
game port, so two agents' dev servers cannot answer each other's
browsers, with nothing to remember and no new literal in any recipe. A
shipped build plays on 4433 and is discovered on 4434.

**The metadata is JSON.** The sim wire is packed binary because it runs
at 10 Hz for hours (D-003); this runs while a human reads a menu, and
what it needs instead is to gain a field without a version bump. Unknown
keys are carried, not refused. The packet is capped at 1024 bytes because
a fragmented datagram is a game that appears on some networks and not
others.

## What running it found, twice, that no unit test could

- **One server was listed THREE times.** A machine answers a broadcast on
  every interface it has — loopback, the LAN address, a virtual adapter's
  — and every one of those replies is a valid way to reach the same game.
  Deduping on the endpoint is right for two servers that share a name and
  wrong for one server with three addresses. The reply carries a **host
  token** now (`GameBrowser.entry_id`), and the endpoint kept is the one
  that answered FIRST: all of them work from here, and unlike "the
  latest" it does not change under the cursor. Every unit test passed
  throughout, because each supplied its own listings.
- **"0/0 players" reads as a broken row**, which the first photograph of
  the list showed. A server with no lobby has no seat list until somebody
  joins; the row says "0 players" until there are seats to fill.

Both are the same lesson this project keeps buying: **the instrument that
sees it is the thing running, or a picture of it.**

## What the browser is not trusted about

This socket answers anybody on the network without a handshake, so:

- **The ADDRESS is the sender's**, taken from the datagram, never a field
  in the reply. A reply that could name the endpoint could point every
  browser on the network at a third party.
  `test_a_reply_cannot_send_a_browser_somewhere_else` was observed red
  before being trusted.
- **A beacon answers questions only.** If a reply looked like a question,
  two servers on one network would answer each other for ever at line
  rate.
- **Malformed JSON is parsed by an instance, not `JSON.parse_string`.**
  The static helper pushes an engine error per bad document, so one
  hostile sender could fill a server's log at line rate — a denial of
  service through a diagnostic. Found by the GUT suite counting the
  engine errors, which is the second time that check has earned itself.
- **Nothing from inside the match is announced.** Name, map, counts,
  phase, whether there is room, and the protocol version. That last one
  is #187's own requirement: grey an incompatible build out BEFORE a
  doomed join rather than have the handshake refuse after it (#179 stays
  the authority; this only saves the trip).
- **`joinable` is the HOST's answer**, not a sum of the counts. A running
  match with room is offered — this server genuinely seats and spawns a
  mid-match joiner — and when D-090's repossession lands, only the host
  will know whether a seat can be taken back.

## The instruments

```
just browser-check          # native, no GPU: a server announces, a client FINDS it
just browser-shot           # docker: the menu WITH a real game in it — look at it
just test-unit game_browser # the list's own decisions, headless
```

`browser-check` is the gate, and it was **observed to fail** with
`_beacon.poll()` commented out — a beacon nobody polls answers nothing,
which is exactly the defect its caller-exists test guards. It asserts
three things the feature could be broken in while looking fine: that the
server opened a discovery socket at all, that the client listed that game
by name at this instance's port, and that it listed it **once**.

`docs/playtest/p41-game-browser.png` is the picture.

## What is deliberately NOT here

- **Invites**, in either direction, including a cold launch carrying a
  lobby id. That is the platform's, and it is the case D-094 criterion 4
  names by itself.
- **A refresh button.** The list asks once a second on its own; a button
  that re-does what is already happening is a control that teaches
  players the screen is not working.
- **Any filtering or sorting a player can change.** A LAN holds a handful
  of games. Sorting joinable-first is the whole ordering argument
  (#187 is lobbies, not matchmaking); the moment a list needs filters, it
  needs a service, and D-089 rejected that.
- **A cross-subnet directory.** The broadcast address is deliberately the
  limited one every LAN carries and no router forwards: a discovery
  packet that left the building would be a privacy problem rather than a
  feature. `--browser-probe=` asks a named machine directly, which is
  what the recipes use across a docker bridge.

## Revisit trigger

The first time a provider needs to be asked something the five methods do
not cover — a join that is not an address and a port, which is exactly
what a platform lobby is. The stub's doc block already names it: a
platform row's press calls the provider rather than `_connect_to`, and
the browser already treats the endpoint as opaque for that reason.
