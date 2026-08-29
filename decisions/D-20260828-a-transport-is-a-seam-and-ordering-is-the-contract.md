### D-20260828 · Accepted — a transport is a seam, ordering is the contract, and the boundary could not be called by its own name

**Decision (M8, issue #184, discharging the buildable half of D-094
criterion 5):** the server and the client reach the network through
**`net_transport.gd`**, a seam both ENet and Steam sit behind.
`enet_transport.gd` is the incumbent, unchanged in behaviour. The Steam
side's **lane mapping and its one dangerous choice** are decided and
written down in `platform.gd`; the wrapper itself needs a Steam runtime
and an account, and is named as the human remainder rather than stubbed
into something that looks finished.

---

## 1. The seam keeps ENet's vocabulary, on purpose

`NetTransport`'s five event constants **are** `ENetConnection`'s, value
for value, and `poll()` returns `[type, peer]` exactly as `service()`
does. A seam that invented its own vocabulary would have made this a
rewrite of the netcode rather than an addition beside it — and the
netcode is the part that is proven. `tests/test_transport_ordering.gd`
asserts the constants match rather than trusting it: if Godot ever
renumbered them, every event would be misrouted **silently**, a connect
handled as a disconnect.

Peers stay duck-typed to `ENetPacketPeer.send`'s shape. Three
implementations now agree on it — `LoopbackPeer` (D-051), `HostLink`
(#182) and ENet's own — which is what makes "an AI seat, the host and a
remote player take one code path" a structural fact rather than an
aspiration.

**ENet telemetry stays ENet-specific and does not go through the seam.**
`_sample_transport_stats` reads per-peer RTT, packet loss and throttle,
and those are statistics of *one* transport: Steam's equivalents are
different quantities with different meanings, and averaging them into one
peak would produce a table whose columns do not compare. A Steam run
reports its own numbers **beside** D-042's, never into them. The null
cast is the filter, and it is deliberate.

## 2. Ordering is the contract, and it is falsifiable now

D-042 measured that curve packets carry **no sequence number**, so the
client installs whichever curve arrived most recently — and chose to hold
the transport to reliable-ordered delivery rather than add sequencing the
protocol was measured not to need. `test_client_state.gd` proves the
*protocol's* half: feed two curves backwards by hand and the client keeps
the stale one forever, because curves are sent only on change (D-003) and
no later message corrects it.

What was missing is the half that matters once a transport can be
**swapped**. Nothing anywhere said "a transport that reorders breaks this
game" in a form a new transport could be held against.
`tests/test_transport_ordering.gd` drives the same scenario through the
seam with two fakes — one honest, one reordering — and asserts that the
honest one agrees with the server **and the reordering one does not**.
The second assertion is the point: a test that only checked the good case
would pass just as happily against a transport with no ordering guarantee
at all. It was observed to fail (delivery un-reordered; red).

**The mapping, decided here:** ENet channel N is Steam lane N — the
identity, because both guarantee ordering *per stream* rather than
globally, and it lives in `Platform.lane_for_channel()` so the day it
stops being the identity there is one place to change and one to read.
**The send flag is the dangerous half.** Steam offers unreliable sends on
the same connection, and reaching for them — for the perfectly
reasonable-sounding reason that position updates are usually fine to drop
— would produce exactly the desync class the state-hash machinery exists
to catch, rarely and unreproducibly. Reliable only.

## 3. The boundary could not be called by its own name

#181 built `steam_platform.gd`, class `SteamPlatform`, and a test that
fails if any other `.gd` names Steam (D-093's rule, verbatim). **The
first consumer discovered that no file can call it**: `SteamPlatform.foo()`
names Steam. It passed its own guard only because nothing called it —
the declared-and-unread shape this project keeps finding, arriving in the
guard rather than in the feature.

Renamed to **`Platform`** (`platform.gd`). D-093 said "`steam_platform.gd`
or equivalent"; the equivalent that actually works is a name that is not
the forbidden word. It is also the better abstraction: nothing outside
that file should care that the platform *is* Steam, and if GodotSteam is
ever replaced (D-093's own fallback ladder, and
`D-20260828-godotsteam-does-not-ship-a-gdextension` makes that live) the
callers do not move.

**And the rule's next collision was found the same way and solved rather
than deferred.** The guard reads code, not comments — but a *string
literal* is code, so an assertion message saying "Steam" tripped it, and
#187's lobby browser will have to put the word on a **button**. Rather
than weaken the guard for everybody, user-facing text comes from
`Platform.display_name()`. One place decides what the platform is called,
exactly as `player_colours.gd` is the one place that decides what a
player's colour is (D-052). The boundary's own test now asserts the
sharper thing: every `has_singleton` / `class_exists` / `get_singleton`
is called with the `SINGLETON` constant, never a literal — which is what
"one place decides what present means" actually means, and which a naive
count of the word forbade.

## 4. What is NOT here, and why it is not stubbed

`Platform.can_carry_a_socket()` returns **false even when Steam is
present**, and says so. Reporting true on the strength of Steam merely
being available would be the worst kind of wrong: a caller would choose a
transport that does not exist, and would do it **only on machines that
have Steam** — never on any machine that runs the tests. The reason is
returned as prose a caller can show a player.

The wrapper needs a Steam runtime, an app id and an account. So does
every remaining part of criterion 5: a real match over Steam sockets,
zero desyncs over a reported number of comparisons, and D-042's RTT and
loss re-taken on the relay path. Those are the human remainder, and the
PR says so rather than leaving a shape that looks finished.

## 5. ENet proven unchanged, and the one number that moved attributed

**`just test-load 4 120` on this branch is clean**: all four
`gate-check.sh` comparisons green, `VERDICT ok`, **0 desyncs over 476
state-hash checks**, 0 building desyncs, 0 dropped ticks. That is the
check this refactor had to survive — every byte the wire has ever carried
still goes through `ENetConnection`, so if the wrapper were wrong the
numbers would say so.

**One number moved on the first sample, and a second sample settled
it.** Two `4 120` runs on this branch, against the same run taken for
#179 on the same map:

| | #179 baseline | #184 run 1 | #184 run 2 |
|---|---|---|---|
| µs/squad | **150.79** at 33 squads | 174.61 at 32 | **151.00** at 32 |
| fields / curves / vision | 33.70 / 10.75 / 21.41 | 39.62 / 11.79 / 24.72 | 28.00 / 10.98 / 23.85 |
| combat / economy / separation | 57.36 / 7.63 / 8.74 | 67.35 / 9.18 / 9.42 | 58.30 / 9.27 / 8.66 |
| **other** (the residual) | **1.35** | **1.34** | **1.07** |
| desyncs / checks | 0 / 476 | 0 / 476 | clean |
| dropped ticks | 0 | 0 | 0 |

**Run 2 lands on the baseline**, so run 1 was the host and not this
change — and the phase breakdown said so before the second run existed.
Every phase in run 1 rose 14–17% *including* `combat`, `vision`,
`economy` and `separation`, which a transport seam cannot touch, while
`other` — the residual, where network servicing and anything
unattributed lands
(D-20260818-every-microsecond-of-a-tick-has-a-phase) — did not move at
all. A uniform rise with a flat residual is the signature of a slower
machine, on a laptop running four other agents' worktrees.

Recorded this way on purpose: this project has twice been unable to
attribute a per-squad rise after the fact, and the standing rules that
one green run is not a measurement and that a wall clock is a statement
about the host as much as the code are exactly what made the second run
worth taking rather than arguing from the first.

**Rejected alternatives:** *a transport interface with its own event
vocabulary* — see (1). *Putting the Steam socket in its own file* —
D-093 forbids it, and the inner-class alternative inside `platform.gd`
is where it will go. *Reporting Steam-available as socket-capable and
failing at connect time* — see (4); a failure that only happens on
machines the tests never run on is not a failure anybody will see in
time.

**Consequences:** `server.gd` and `client.gd` contain **no reference to
`ENetConnection`** at all — a test asserts it, because a seam with one
caller still reaching around it is a seam that will grow a second
implementation nobody can use. `EnetTransport.describe()` is printed
beside the endpoint by both binaries, because the transport is the first
thing to suspect when two machines disagree and "which one was it" must
not be a guess.

**Revisit trigger:** the Steam wrapper landing, which will find whatever
is wrong with a mapping nobody has run; or a measured case where
reliable-ordered on the relay path costs more than D-042's ENet numbers
in a way that reopens that decision — in which case the answer is a
sequence number on the curve, not an unordered lane, and D-042 already
says so.
