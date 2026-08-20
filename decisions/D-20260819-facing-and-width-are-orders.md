# D-20260819 · Facing and width are the player's orders

**Status:** ACCEPTED — workstream 5 of
D-20260818-battle-quality-outranks-player-count (the first half of exit
criterion 5; the drag GESTURE is workstream 8's). **Extends:** D-058
(formation is a player's choice — this adds two more axes of that
choice) and D-006 (facing and files join the replicated inputs soldier
positions derive from). **Relates to:** D-024/D-20260819-morale-reads-
the-fight (facing is what rear shock reads, so bracing a line is now a
defence), D-20260819-only-men-in-contact-fight (files are what frontage
reads, so widening a line is now an attack).

## Why this exists

The three-tier decision's survey named them absent: facing has no
opcode (derived from the path only) and ranks/files are `.tres`
constants. Tier 2 and the morale terms made both TACTICAL: contact
count rewards frontage, rear shock punishes exposed backs — but the
player can control neither. The mechanics exist; the verbs do not.

## Decision

Two new per-squad, player-ordered, REPLICATED values, riding exactly
D-058's machinery (the `set_shape` path: validated server-side through
the shared helper, applied to the sim, marked dirty, rebroadcast in
SQUAD_INFO, hashed in `composition_hash`):

1. **Ordered facing** — which way a squad faces WHILE STANDING. A
   moving squad faces its path (wheeling, D-20260818, is untouched);
   the ordered facing takes over the moment the squad is at rest, and
   is cleared by nothing except a new facing order. Resolved in ONE
   place — `Formation.facing_angle` — read by soldier derivation on
   both machines AND by combat's aspect term, so the line you braced is
   the line the rear-shock arithmetic sees. **Quantised to 1/4096 of a
   turn on the wire and in the sim**: both sides reconstruct the angle
   from the same integer, so the hash never depends on float bit
   patterns (the `spacing` precedent, one comment up in
   `composition_hash`).
2. **Ordered files (width)** — how many files a grid formation forms,
   overriding the FormationDef's own ranks arithmetic. 0 means "the
   formation's default"; clamped server-side to [1, alive]. Applies to
   grid and scatter kinds; wedge and ring have no files to override and
   ignore it. Footprint, culling, separation and contact all read the
   overridden width, because they all read `Formation` — the footprint
   cache key gains the files term, or a widened squad would cull and
   separate at its old size.

## The interim UI, and what workstream 8 replaces

- **Face: Alt + right-click** — the selection faces the clicked point.
  One modifier on the order gesture that already exists, no new mode.
- **Width: Widen / Narrow buttons** in the command panel's orders
  column (+/- one file per press), under the same layout disciplines
  the panel already carries (D-20260817: a control that stops fitting
  is HIDDEN FUNCTIONALITY, not a spacing tweak).

Workstream 8's drag gesture (position + facing + width in one motion)
subsumes both on the input side; the opcodes and sim halves built here
are exactly what it will drive.

## Consequences

- SQUAD_INFO gains two trailing fields (facing u16, 0xFFFF = none;
  files u8, 0 = default); `composition_hash` hashes both on both
  sides. Old replays decode facing 0 rather than none — accepted, as
  the `fell` byte already was, until M8's version handshake.
- `Formation.slot_offset`, `soldier_transforms*` and `footprint` gain
  defaulted parameters; every existing caller is unchanged by
  construction.
- The economy's ring suggestion (D-058/D-065's suggest-vs-set) is
  unaffected: shape suggestion never touches facing or files, and a
  gathering ring ignores files anyway.
- AI seats and bots do not use the verbs yet; the AI learning to
  refuse a rear charge is behaviour work under the ai-opponent
  increments, not this entry.

## Rejected alternatives

- **Facing as free float on the wire.** The hash would then hash a
  float that crossed the wire at 32 bits against a sim value at 64 —
  the exact "float formatting" trap composition_hash's own comment
  warns about. Quantisation is not a compromise; 4096 directions is
  ~0.09°, an order finer than any drag gesture resolves.
- **Facing kept while marching** (strafe/backpedal). March-facing is
  what wheeling, pace and the whole D-20260818 turning model are built
  on; a squad that walks sideways re-opens all of it for a behaviour
  RTW itself does not have.
- **Width as a shape variant per width** ("line-6", "line-8", ...).
  Combinatorial data for one integer, and D-058's shape stays what it
  is: a KIND, not a parameterisation.

## Revisit trigger

If playtests want facing preserved through short repositioning steps
("shuffle left, stay braced"), that is a movement-model change against
the wheeling decision, not a bigger sentinel here. If any script other
than `Formation.facing_angle` starts interpreting the raw facing
value, stop — one resolver is the point, exactly as `round_axial` is
the one cell-rounding.
