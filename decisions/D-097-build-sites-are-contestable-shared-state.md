### D-097 · 2026-08-15 · Accepted — build sites are contestable shared state

**Decision:** A pending foundation stops being a private note the server
keeps for one squad and becomes a **build site**: authoritative, replicated
to its owner, and contestable by everyone else.

1. **Shared.** Any squad of the owner's that may build that def can work an
   existing site. Progress **pools** — two gatherers on one foundation build
   it in half the time, three in a third.
2. **Persistent and owner-visible.** A site is replicated to its owner (only)
   and drawn on the ground until it is built or destroyed. No timeout.
3. **Contestable.** A site does **not** reserve ground against enemies. If an
   enemy completes a building overlapping it, the site is destroyed, and
   whatever was spent on it is gone.
4. **Demolishable.** An owner may destroy their own completed building
   outright. **No refund**, matching D-055's razing — a building is a sunk
   cost whichever way it comes down.

**Rationale:** The immediate cause was a smaller thing — a build order was
silent until the builder arrived, so a distant site was indistinguishable
from a misclick for many seconds. The first fix was a client-side marker
that faded after nine seconds. Playing with it made the real shape obvious:
a mark that only YOU can see, that no other builder can act on, and that
vanishes on a timer is a *notification*, when what the player wants is a
**plan** — something they lay down, come back to, and reinforce.

Pooling rather than merely surviving one builder's death (the alternative
considered) is what makes helping a real decision: sending a second crew has
a visible payoff, so "finish this wall NOW" becomes a thing you can spend
squads on.

Not reserving ground is the deliberately harsh half, and it is what stops
sites being free territory. A site costs nothing to place and would
otherwise be a way to claim a map by spamming foundations nobody can build
over. Making it losable turns forward-building into a genuine race, which is
the interesting version.

**This crosses a boundary on purpose, and the boundary is worth naming.**
The marker as originally built was cosmetic and one-way in the spirit of
D-006 — the simulation could never read it. A build site is the opposite:
authoritative state that happens to be drawn on the ground. The mark is now
the *rendering of* the site, not the thing itself, and the D-006 discipline
continues to apply to the rendering only. Anything the player can contest,
lose, or spend squads on is simulation state and lives server-side.

**Rejected alternatives:**

- *Keep it a client-only marker* (rejected — cannot be worked by another
  squad, cannot be contested, and cannot survive a reconnect. Every property
  asked for here requires the server to own it.)
- *Sites reserve ground against enemies* (rejected — a free, instant,
  uncontestable land claim. `_footprint_conflict` already counts pending
  intents this way, which is fine among your OWN builds and has to be
  relaxed for enemies.)
- *Redundancy without pooling* (rejected — a second builder that changes
  nothing visible is not a decision the player can feel.)
- *Partial refund on demolish* (rejected — D-055 gives nothing back for
  razing, and two different answers for "this building came down" is the
  kind of inconsistency that gets discovered as a exploit rather than as a
  rule.)

**Consequences:**

- `_pending_builds` moves from a per-squad dictionary to a site list with its
  own ids, and gains a wire message gated to the owner (fog rules apply —
  D-004 — but a site is only ever sent to its owner anyway).
- Construction rate becomes "sum of the crews present", not a fixed rate.
- A new order opcode for demolition, validated for ownership server-side
  (D-002) like every other order.
- `_footprint_conflict` distinguishes own-pending (blocks) from
  enemy-pending (does not).
- **Careful with the completion path:** destroying a site when an enemy
  building lands on it has to go through the same dirty-flag and passability
  refresh a real destruction does, rather than a second implementation built
  to match it by hand — the trap D-076's upgrade path already documents.

**Revisit trigger:** If sites become the dominant way players deny ground
(the opposite failure to the one clause 3 prevents), or if pooled
construction makes early rushes decide matches faster than D-056's 1-2 hour
target allows.

---
