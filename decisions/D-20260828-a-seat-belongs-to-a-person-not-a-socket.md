# D-20260828 · A seat belongs to a person, not a socket

**Status:** ACCEPTED — the ENGINEERING half of #186. The Steam-runtime
half is stubbed at a named boundary and is the owner's call; see the last
section. **Implements:** D-090 (reconnection is repossession), the seat
half of D-094 criterion 3. **Supersedes:** D-033's wipe-on-disconnect,
for HUMANS only. **Constrained by:** D-038 (the ownership-cache lesson),
D-051 (an AI is a client without a socket), D-002 (the client is not
trusted), D-093 (Steam lives behind one boundary),
D-20260817-an-ai-never-holds-the-lobby.

## Decision

A seat is bound to an opaque **identity token**, never to a connection.
Three things follow, and all three are exercisable with bots today.

**Drop-out.** A human's disconnect no longer wipes their army. The seat
passes to an AI, keeping the army, the civ and the team. There is no
grace period and no timeout: **the AI holding the seat IS the grace
mechanism**, indefinitely.

**Rejoin.** The same identity reclaims the seat, on a new socket, mid
match. The AI stands down; the client is re-admitted as a fresh join.

**Refusal.** An identity that names an OCCUPIED seat is refused. An
identity is not a password — it arrives from an untrusted client
(D-002) — so handing over a seat somebody is sitting in would be an
impersonation bug rather than a reconnection feature.

## Why identity and not connection: this project has already paid

D-038's amendment is the precedent and it is exact. Ownership was read
from a list cached per connection and written once at join, so every
squad a player *produced* was refused as one they did not own — 2,700
refusals in a 20-player run, surfacing as the interesting-looking "zero
movement". The lesson recorded there was narrower than the comment
above it: *it was not a copy of the check that drifted, it was a copy of
the data.*

Seats are the same shape of state, so they get the same treatment: one
binding, in `MatchState`, outliving both the socket and the AI that
holds the chair.

## The token is opaque, and nothing may parse it

`player_identity.gd` is all-static and pure and **does not name Steam**.
It takes a token that has already been resolved, so D-093's
one-boundary rule holds and the platform half drops in without this
file, `MatchState` or the server learning that Steam exists.

- **Bounded and filtered** on arrival: it is untrusted input, and it is
  echoed into logs and compared against every seat.
- **Hashed** in the local path, so a token carries nothing about the
  machine that produced it. A token that embedded a username would leak
  one; a token that could be read would eventually be read, and then the
  seat table would depend on which platform somebody joined from.
- **`same()` is a function, not `==`** — one definition of "same
  player", for the reason D-038 gives about copies of a check.

**Two anonymous tokens never match.** That is the dangerous default and
it is refused explicitly: treating un-identified clients as one player
would hand a stranger somebody's army the moment a bot reconnected.

## Anonymity is a supported state, deliberately

A client that never sends `C2S_IDENTIFY` plays exactly as it did before
identity existed and simply cannot be repossessed. **Every load-test bot
is in that case**, and that is the property that let this land without
changing what the existing estate does — the alternative was a wire
change every harness had to learn at once.

## What the AI inherits, and what it must not

The seat's **civ and team are untouched**. #186 names this as the
mislabel one wrong writer away, and it is the
D-20260817-an-ai-never-holds-the-lobby family: `kind` is read
everywhere, one writer set it wrong, and an AI reported one civilisation
while fielding another's troops for a whole match with nothing failing.

`kind` DOES move to `"ai"`, because every existing reader — the lobby,
the scoreboard, match-start re-seating — must see an AI seat. And the
**admin badge leaves**: an admin seat held by a computer is a lobby no
human can start a second match from, which is that same decision's
finding.

"Defeated" keeps exactly one definition (D-033's no-living-squads rule).
An AI-held seat is simply a seat that is still playing.

## Rejoin is a fresh join, which is why it is cheap

D-025's reveal semantics already define how ANY client learns current
state — horizon-clipped curves, sent fresh, no synthetic catch-up. So
repossession re-admits through the ordinary path rather than inventing a
catch-up protocol.

The one non-obvious obligation, which D-090 names and this
implementation honours: the per-connection `visible` and
`known_buildings` baselines are cleared, so **persistent-explored
building fog is replayed as the ever-revealed set** (D-030) rather than
diffed against what the AI could see. That set is what the server
HASHES, and getting it wrong is exactly the 106-building-desync incident
`docs/status/sandbox.md` records for `_return_to_lobby`.

## The handover happens WITHIN A TICK, and that is not a detail

D-090's own wording is "within a tick", and it turned out to be the only
safe timing rather than a loose one.

Seating the AI inline from `_on_disconnect` re-admits it, which
broadcasts through `_recipients()` — and `_on_disconnect` runs from
INSIDE the network service loop, where other peers may already be dead
at the socket level with their own DISCONNECT events still unserviced.
Broadcasting into that storm produced a wall of `Unable to send packet
on channel 0, max channels: 0`.

**`just test-load` caught it and the unit tests structurally could not**,
because they have no sockets to race. The handover is queued and drained
once per frame after the service loop, so every departure is processed
before anything is sent — and a player who reconnects between dropping
and the drain keeps their seat rather than having it handed away behind
them.

Verified on the wire: a clean `4 120` run reports **4 seat handovers, 0
engine errors, 0 desyncs**.

## One production signature relaxed, and why it is not a test-driven weakening

`_on_disconnect(peer: ENetPacketPeer)` is now `_on_disconnect(peer)`.
Every peer-taking function beside it — `_record_for`, `_dispatch`,
`_admit_player`, `_handle_identify` — is already untyped, because since
D-051 a peer is polymorphic: an AI seat is a `LoopbackPeer`. Nothing in
the function touches anything ENet-specific, so the annotation bought no
safety and made the seat-handover path untestable without a socket.

## Observed red

Each rule perturbed and watched to fail, then restored:

| perturbation | caught by |
|---|---|
| disconnect wipes the army again | the drop-out and rejoin tests |
| reclaim keyed on connection, not identity | `test_the_same_identity_reclaims_its_seat` |
| an occupied seat can be taken | `test_a_different_identity_cannot_take_an_occupied_seat` |
| two anonymous clients treated as one | `test_two_anonymous_clients_are_not_the_same_player` |
| the AI keeps the admin badge | `test_an_ai_never_keeps_the_admin_badge` |

## The Steam half, stubbed at a named boundary — the owner's call

Everything above works with **no Steam and no platform SDK**. What is
not done, and what it would take:

- **Resolving a real platform id.** `PlayerIdentity` takes a token that
  is already resolved, so the boundary is one call site in the client:
  today it would pass `PlayerIdentity.local_token(<a persisted seed>)`,
  and the Steam path passes the SteamID instead. That call site is the
  ONLY thing the platform work touches here — D-093's rule is intact and
  no file in this change names Steam.
- **Persisting the local seed.** The client does not yet store one
  across runs, so a Steam-less player's identity is stable only within a
  session. That is a `user://` write beside the audio settings and is
  deliberately not bundled in with a seat-ownership change.
- **#181's boundary script** is not in this branch, so nothing here can
  call it; when it lands, the one call site above is where it plugs in.

## Deliberately not in this slice

- **Drop-in (D-089)** — a NEW human taking a *different* AI's seat mid
  match. The refusal rule above is deliberately strict (only a
  reclaimable seat, only by matching identity), and drop-in needs a
  policy for which AI seats are offered and to whom. That is a lobby/UX
  decision, not this one.
- **Desync recovery through the same door** (D-090 clause 4). The path
  now exists; nothing yet triggers it on a hash mismatch.
- **The alpha-tester doc's "disconnecting loses your army" caveat.** It
  is no longer true for a human, but that doc is #179's and is not in
  this branch.
- **A measured mid-match rejoin cost.** #186 asks for it and it wants a
  real client against a real server; the unit tests prove the seat
  machinery, not the wall clock.

## Revisit trigger

If an identity ever needs to be *verified* rather than merely presented
— which it will, the moment ranked play exists (D-091 gates that on
dedicated servers) — this is not enough on its own: a token is a claim,
and the refusal rule above only protects seats somebody is currently
sitting in.
