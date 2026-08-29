### D-20260828 · 2026-08-28 · Accepted — inside the derive phase, and the two levers left in it

**Decision:** the derivation phase is attributed to its parts, the two
**bit-identical** hoists it turned up are taken, and the levers that
would actually close the remaining gap are **filed as design trades
rather than shipped**, because every one of them is visible to a player
or changes what the project builds.

Continuing the owner's standing performance directive after
`D-20260828-the-jostle-looks-where-the-men-are` took the quadratic out:
the frame is ~118 ms of CPU at 1,000 squads on integrated graphics, which
is still about seven times a 60 fps budget.

## What derivation is made of

Measured by **ablation on the shipped function** — nothing here is a
lookalike; only the INPUTS vary, and the four runs solve for the parts.
96 squads of 36 men drawn at LOD tier 2 (12 men), real generated terrain,
real fields, headless, two passes; the quieter pass is quoted and the
model reproduces the fourth configuration it was not fitted to (65.0 µs
predicted, 65.0 measured):

| part | cost | share of a 12-man squad |
|---|---|---|
| ground sample, per man | **7.2 µs** | **51%** |
| formation math + transform write, per man | 3.2 µs | 23% |
| per-SQUAD setup | 26 µs | 16% |
| passability clamp, per man | 1.4 µs | 10% |

Two things follow immediately.

**The ground is half the phase**, and it is not one expensive call: it is
`world_to_axial` + `round_axial` + `index` + `height_in_cell`, each a few
float operations wrapped in a GDScript call. The `atan2` in the sector
search — the obvious suspect — costs **0.02 µs**, a fortieth of the
`round_axial` beside it. There is no hot spot to remove.

**A GDScript call costs 0.174 µs on this hardware**, measured against an
empty loop, and that is the unit everything here is built from:

| | cost | of which |
|---|---|---|
| trivial method call | 0.174 µs | — |
| `normalize` | 0.214 µs | 0.174 call, 0.04 arithmetic |
| `index` | 0.410 µs | its own call **plus** `normalize`'s |
| the two `posmod`s written out | 0.095 µs | no call at all |
| `round_axial` | 0.621 µs | its own call **plus** `_axial_round`'s |

**The per-squad setup is 26 µs and only ~10 of it is nameable**
(`facing_angle` 6.5, `sample_world` 2.3, the roster lookup 1.4, the
`Basis` 0.09). The rest is the cost of entering a thirteen-argument
GDScript function and allocating a typed array — which is the shape of
the whole finding.

## What was taken: two hoists, both bit-identical

- **`_offset_for`'s squad invariants.** It recomputed the scaled spacing
  (a `maxf`) and the file count (a `clampi`, or a `sqrt` and a `ceili`
  through `_grid_files`) **for every man**, inside a loop whose own
  header explains that everything squad-invariant is hoisted out of it.
  `_offset_in` is the geometry with those two already worked out;
  `_offset_for` computes exactly what it always did and hands them over,
  so the single-soldier path is unchanged.
- **Two delegations collapsed.** `index` wrote its own two `posmod`s
  instead of calling `normalize`, and `round_axial` took its body back
  from `_axial_round`. Both are once per drawn man per frame, and once
  per cell in every disk scan in the project.

**D-008 is untouched and that is the point of doing it this way:** the
wrap rule still lives in exactly one FILE and every caller still comes
through `TorusSpace`. What is gone is a stack frame, not a definition,
and `test_torus_space.gd` now holds `index` and `normalize` to the same
answer — observed red by wrapping one axis one cell off.

**Worth, measured two ways**, both interleaved seconds or minutes apart
rather than across a session:

| instrument | before | after | |
|---|---|---|---|
| headless, 36,960 men, tightest pair | 5.592 µs/man | 4.714 µs/man | **-15.7%** |
| `bench-render`, 1,000 squads, 4,385 drawn, pair 1 | 54.31 ms | 44.57 ms | **-17.9%** |
| the same, pair 2 | 52.35 ms | 47.40 ms | -9.5% |

Call it **10-18% of the derivation phase**, 5-9 ms of the frame. The
looser pairs are the host: a `bench-check` taken during another agent's
`test-load` reported every phase — including ones this does not touch —
between 44% and 302% slower than the recorded baseline, with **no COUNT
lines**. That is the baseline mechanism behaving exactly as designed, and
it is why the numbers above come from interleaved pairs.

## What was NOT taken, and why each is a decision rather than a patch

Nothing left inside derivation is a hot spot; it is twelve microseconds
of many small GDScript operations per man. A 7x gap does not close by
tuning it. The three things that could:

1. **Derive at a lower cadence for distant squads** — hold a far squad's
   transforms for two or three frames instead of re-deriving them at
   frame rate. The simulation advances at 10 Hz (D-020), so a distant
   squad re-derived at 20 Hz is showing the same curve sampled at times
   nobody can tell apart. But it is per-soldier state that SURVIVES
   FRAMES, and the honest reading of D-006 is that clause 2 as amended
   permits exactly that for `SoldierMotion` already — so this is a real
   candidate and a real decision, not an obvious no. **Filed as #315.**
2. **The GDExtension hatch (D-021).** Its stated trigger is "a specific
   kernel measured to exceed budget", "on M4 profiling evidence, not on
   suspicion". That evidence now exists and this entry is it: the kernel
   is `Formation.soldier_transforms_sampled`, its cost is the
   per-operation cost of GDScript, and the same arithmetic in a compiled
   language is the only lever that does not cost fidelity. It changes
   what this project BUILDS, so it is the owner's call. **Filed as #316.**
3. **Drawing fewer men.** Already the lever (D-045's LOD), and going
   further is exactly the player-visible compromise the directive rules
   out: D-045's own rule is thinner, never smaller.

## Rejected outright

- **Inlining `TorusSpace`'s arithmetic into `Formation`.** It would save
  three calls per man and it duplicates the definition D-008 exists to
  keep singular. The wrap rule is not allowed to have two homes; the
  saving is 0.5 µs and the defect it invites is the whole reason that
  decision was written.
- **A cheaper sector search in `height_in_cell`.** The `atan2` measured
  at 0.02 µs. Replacing it would be optimising 0.3% of the ground sample
  while risking the bit-identity two machines derive from.
- **Caching the ground per cell per frame.** The height varies WITHIN a
  cell — that is what the barycentric interpolation is for — so a
  per-cell cache answers a different question and would flatten every
  slope a formation stands on.

## Revisit trigger

Either filed trade being taken, which moves the phase this entry
attributes; or a discrete GPU, since every number here is integrated
graphics and D-085's re-run trigger is still armed.
