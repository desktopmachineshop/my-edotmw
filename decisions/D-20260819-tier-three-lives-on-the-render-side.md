# D-20260819 · Tier 3 lives on the render side

**Status:** ACCEPTED — workstream 10 of
D-20260818-battle-quality-outranks-player-count: the D-006 amendment
Tier 3 was always going to need, made explicitly, and the two behaviours
it legalises. **Amends:** D-006 (the amendment text lives in D-006's own
file, per decisions/README rule 1 — this entry is the design that
justifies it). **Relates to:** the three-tier decision (whose corrected
revisit trigger this fires ON PURPOSE, in the open), D-024 (untouched),
the programme's fairness rule (the amendment's third clause).

## The amendment, in one paragraph

D-006 clause 1 remains binding for the AUTHORITATIVE derivation:
`Formation` stays pure, the wire carries squads, every outcome reads
derived-from-replicated-state positions. What changes is clause 2's
scope: the RENDER layer may now hold **per-soldier integration state** —
persistent slot assignments, eased positions, relaxation offsets —
under three conditions that are each a test, not a promise:

1. **One-way.** Never read by simulation, never on any wire, never in
   any hash. (The boundary scans that already police CosmeticDuel and
   the corpse classes extend to the new state.)
2. **Bounded.** A drawn man stays within `MAX_RENDER_DRIFT` (1.5 world
   units) of his authoritative slot, so selection, culling and every
   screen-space read built on authoritative data stays approximately
   right — the same bound Tier 1's duel step already honours.
3. **Outcome-blind.** Nothing outcome-affecting may consume a rendered
   position. Two clients may legitimately draw one melee differently by
   centimetres; they may never RESOLVE it differently. This is the
   programme's fairness rule wearing clause form.

The NEW revisit trigger (replacing the fired one): any mechanic that
wants an OUTCOME to depend on a drawn position — per-man hit tests,
render-driven collision — reopens the original choice (network ~40,000
entities or accept divergence) as a decision, never as a patch.

## What Tier 3 actually ships

- **Men walk into vacated slots.** On a casualty restamp the render
  layer no longer teleport-shuffles everyone: `SoldierMotion` keeps a
  per-squad assignment and re-deals survivors to the new slots by
  nearest-match, so the line visibly closes ranks — the exact behaviour
  D-006's corrected trigger named first.
- **Men jostle.** A bounded relaxation pass separates overlapping drawn
  men of the same squad — the melee scrum breathes instead of
  interpenetrating. One iteration per frame, clamped by
  `MAX_RENDER_DRIFT`.
- **Chasing routers is already delivered by composition** — sim-level
  pursuit (ws4) closes the distance and Tier 1's memoryless pairing
  re-aims each man at the nearest fleeing enemy. No new mechanism, and
  the entry says so rather than building one to have built one.

The assignment and the relaxation are PURE STATIC functions
(`SoldierMotion.assign`, `SoldierMotion.jostle`) with the instance
holding only their memo — so the interesting halves are tested headless
while the boundary conditions above are tested as scans.

## Rejected alternatives

- **Refusing Tier 3 (the three-tier document's own recommendation).**
  Overridden by the owner in the programme decision; the fairness
  argument survives as condition 3 rather than as a veto.
- **Per-soldier wire state.** Still rejected on D-006's original
  arithmetic: ~40× the netcode for behaviours the render layer can
  carry alone.
- **Simulation-side slot-filling** (authoritative men walking to
  vacated slots). It would make `alive` stop being the only formation
  input a death changes, unravelling D-024's decisive detail for a
  visual effect the client can produce by itself.

## Revisit trigger

The amendment's own, above. Additionally: if `MAX_RENDER_DRIFT` ever
needs raising past selection's click tolerance, selection must start
reading drawn positions first (it already reads drawn lattice copies —
the same discipline extends), and that ordering is the trigger's test.
