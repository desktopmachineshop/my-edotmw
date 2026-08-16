### D-025 · 2026-07-30 · Accepted — closes D-004's Provisional semantics
**Decision:** Three parts, all riding on D-003/D-004's curve gating.

1. **Vision is a per-player field over cells, not a per-pair test.** Each
   tick (or each vision-recompute interval, which may be lower), each
   player's vision coverage is stamped once from its own squads'
   positions and `vision_range`, and a squad's visibility is then a
   single O(1) lookup into the owning player's coverage. Vision is
   radius-only on the torus via `TorusSpace.distance` — elevation does
   not occlude in M2.
2. **Reveal is a truthful pop-in.** A squad entering vision has its
   current curve replicated clipped to `[now, now + horizon]` exactly as
   any other squad would be. The client therefore sees it at its true
   present position with no history and no future beyond the horizon. No
   synthetic curve is ever manufactured.
3. **Conceal leaves a stale ghost, announced explicitly.** When a squad
   leaves vision the server sends a conceal event; the client keeps its
   last-known curve and composition, marked stale, and stops treating it
   as live. It receives no further updates until revealed again, at which
   point the resend replaces the ghost wholesale.

**Rationale:** Part 1 is a cost decision. The obvious implementation —
for each player, for each squad, is any of my squads within range — is
~50,000 distance tests per player per tick at D-018's counts, so about a
million per tick across 20 players, against a 100 ms budget that has to
cover the simulation as well. Stamping coverage per player and looking up
per squad replaces that with tens of thousands of cheap operations, and it
is also the structure that terrain-occluded LOS would later extend rather
than replace.

Part 2 falls out of D-003 already being mandatory: clipping to the horizon
is what a reveal *is*, so pop-in requires no new machinery, and it cannot
leak — the keyframes describing where the squad has been were never in the
packet. A synthetic catch-up curve was tempting for smoothness and is
rejected below.

Part 3's explicit conceal event is not a convenience. Without it the
client cannot distinguish "this squad is out of vision" from "its update
is late", and D-006's composition hash then compares different sets on the
two sides: the server hashes what a client can see, while a client
carrying ghosts hashes more than that. The desync check would fire
constantly on a system working exactly as designed — and a check that
cries wolf gets muted, which is the failure mode `NetProtocol.
composition_hash` was written to avoid. Announcing conceal keeps the
hashed set agreed by construction and makes the ghost a deliberate,
inspectable state instead of an inference from silence.

**Rejected alternatives:** *Synthetic catch-up curve on reveal* (rejected
— it draws motion that never happened, and worse, it leaks: a unit
sliding in from its last-known position tells the player it moved while
unseen, which is exactly the class of information D-003's clipping
exists to withhold). *Hard removal on conceal* (rejected — simplest and
genuinely tempting for testability, but it discards the tactical memory
the genre is built on, and D-019's Total War half assumes the player
reasons about where an enemy was last seen). *Per-pair visibility tests*
(rejected on the cost math above). *Terrain-occluded LOS in M2* (deferred
— it needs a height field the sim does not yet carry, and radius-only
vision is enough to prove the gating).

**Consequences:** `SquadSim.visible_to()` becomes real and D-022's stub
note closes. The protocol gains a conceal event and must send squad
composition on reveal, not only at join — a client cannot derive soldiers
for a squad it was never described (D-006's protocol obligation). Client
state grows an explicit live/ghost distinction, and `composition_hash`
covers live squads only. Ghost curves are stale by design: anything that
samples them must know it is reading history, and the client's own
accounting must not count a ghost as a live squad.

**Revisit trigger:** Terrain-occluded or unit-blocking LOS, stealth
units, or shared vision between allied players. Any of those changes part
1's field computation; none of them change parts 2 or 3.

---
