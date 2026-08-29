**A game is FOUND, not typed (D-20260828-a-game-is-found-not-typed, #187,
2026-08-28).** The pre-lobby menu (#180/#239) lists the games running on
the local network, with the host's name, the map, how full it is and
whether this build can join. Click one and you are in. Nobody types an
address, which is D-094 criterion 4's whole flow.

```
just browser-check          # native, no GPU: a server announces, a client FINDS it
just browser-shot           # docker: the menu WITH a real game in it — LOOK AT IT
```

`docs/playtest/p41-game-browser.png` is the picture.

Six things to know before touching it:

- **It is PROVIDERS, not "the Steam browser with a LAN case".** The menu
  holds an array of provider objects and knows five methods (`id`,
  `label`, `poll`, `take_seen`, `status` — `lan_discovery.gd` is the
  reference implementation). The LAN one works today; the platform's is
  stubbed at D-093's boundary and, being absent in every context this
  repo automates, simply is not in the array. There is no platform branch
  to be broken by. The boundary is reached **by path**, not by class
  name, because exactly one script may name the platform — and this gave
  that boundary its first caller, which it did not have.
- **Discovery ASKS; it does not announce.** A server shouting on a
  well-known port would need every browser to bind that port, and a UDP
  port cannot be bound twice on one machine — so the browser would work
  for one player per computer, which is the configuration every test of
  it runs in. The fixed port is the SERVER's, derived as `game_port + 1`
  so D-095's per-instance ports keep two agents' dev servers out of each
  other's lists for free.
- **What running it found is not what any unit test could.** One server
  was listed **three times** — a machine answers a broadcast on every
  interface it has, and each reply is a valid way to reach the same game.
  The reply carries a host token now and the endpoint kept is the one
  that answered first. Separately, the first photograph showed
  **"0/0 players"**, which reads as a broken row: a server with no lobby
  has no seats until somebody joins, so it says "0 players" instead.
- **Nothing off that socket is trusted except what it is FOR.** The
  address is the sender's, taken from the datagram — a reply that could
  name the endpoint could point every browser on the network at a third
  party (observed red before it was trusted). A beacon answers questions
  only, or two servers would answer each other for ever. And the body is
  parsed by a `JSON` instance rather than `JSON.parse_string`, because
  the static helper pushes an engine error per malformed document and one
  hostile sender could fill a server's log at line rate.
- **An incompatible build is greyed out BEFORE the join**, with which way
  round it is: "theirs is newer than yours" means update, the other means
  wait. #179's handshake is still the authority; the browser only saves
  the trip. And `joinable` is the HOST's answer rather than a sum of the
  counts, because a running match with room is genuinely joinable here
  and only the host knows whether a seat can be taken.
- **`just browser-check` is the gate and was observed to fail.** With
  `_beacon.poll()` commented out it reports "the client never listed this
  game" — a beacon nobody polls answers nothing, this project's
  most-repeated defect. It also fails if the server opened no discovery
  socket, and if one game is listed more than once.

**Not here, deliberately:** invites in either direction (the platform's
half, and the case D-094 criterion 4 names by itself); a refresh button
(the list already asks every second); filters (a LAN holds a handful of
games, and the moment a list needs filters it needs a service, which
D-089 rejected); and any cross-subnet directory — the broadcast is the
limited one no router forwards, and `--browser-probe=` is how a named
machine on another subnet, or a docker service, is asked directly.
