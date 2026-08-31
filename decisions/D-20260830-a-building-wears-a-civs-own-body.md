# D-20260830 · A building wears a civ's own body

**ID:** D-20260830-a-building-wears-a-civs-own-body
**Date:** 2026-08-30
**Status:** Accepted

## Decision

`BuildingDef` gains a per-civ model override, and emberdeep's town
centre and storehouse are its first two entries — the owner supplied
both models ("Add this building as the dwarf town hall", 2026-08-30)
and asked for them by name, which is what unfreezes this one item of
the ratified-but-deferred #413 direction.

1. **The schema is #191's ratified answer, applied to a building.** The
   model keys by the DEF by default, and a civ with an authored body
   names it in `model_overrides` (civ id → model id, data naming a civ
   as `.tres` data may, D-046 criterion 3). A civ without an entry
   resolves to `model_id` exactly as it always did, so the shipped
   fallback stays the rule rather than the exception (D-064): five civs
   keep the neutral hall bit for bit, and a clone that has never run
   `build-assets` still plays.

2. **Resolution is one applied function, `BuildingDef.model_for(civ)`**
   — the civ-knobs rule (D-20260823): a knob is read through an applied
   function on the schema, never as a raw field, because two callers
   each implementing "override wins" is the D-058/D-065 pair that comes
   to disagree. `client.gd`'s one building-mesh site resolves through
   it, keyed by the OWNER's civ — public identity (D-102), so every
   client can answer it for every building it knows, and nothing new
   crosses the wire. Purely presentational: no simulation reads a model
   (D-064), so a wrong answer costs a picture, never a desync.

3. **The bodies are imported like the ships** (D-20260830-a-ship-takes-
   up-its-own-water) and ship **UNDECIMATED** — 19,211 and 19,019
   triangles — under an owner-set ceiling of 20,000: *"buildings can
   run at 10k or maybe even 20k tris because they don't move and there
   is a lot less of them"* (2026-08-30). Both halves of that reasoning
   are structural: a building bakes no VAT, so the 16,384-column limit
   that binds every unit does not apply, and a match holds a handful of
   buildings where a squad fields dozens of men. Textures transfer into
   `COLOR_0`; scale is the NEUTRAL originals' authored heights (3.6 and
   2.1) so footprints, `no_build_radius` and the minimap stay tuned. A
   named budget set (`IMPORTED_BUILDINGS`, ceiling 20,000) rather than
   a raised `BUILDING_TRIANGLE_BUDGET`, the `PLACEHOLDER_ARCHETYPES`
   pattern.

   **Decimation was tried twice first, and only a picture could judge
   either.** The ships' 2,500 SHREDS these models — a Tripo building is
   dozens of separate thin timber parts, and collapse at 13% tears them
   into holes while every count stays healthy; 6,000 leaves them whole
   but nibbles the trim. The render is
   `docs/playtest/p42-emberdeep-buildings.png`; the same check per the
   standing "the check that catches this class is a picture" rule
   (M7's inside-out boxes, D-097's cliffs, D-108's forests).

## Rejected: a second, per-civ def

`buildings/emberdeep_town_centre.tres` (civ = emberdeep, archetype =
town_centre) looks like the forge/stables mechanism and is not. Those
work because NO neutral forge exists — `defs_for_civ` returns neutral
defs AND the civ's own, shadowing nothing, so a per-civ town centre
would be OFFERED beside the neutral one in the build menu. It would
also be a second def with `consumes_builder = true`, which
`tests/test_opening.gd` pins at exactly one by design; and
`opening_brief.gd` finds the founding building by that RULE, so two
matches would make the opening panel's promise ambiguous. The guard
saying "a second is a design decision" is the guard working — the
design decision taken is that a civ's town centre is the SAME building
in a different body, which is a model fact, not a def fact.

## Known and accepted

- **The imported bodies carry no owner-colour mask** (imported at
  `--owner-mask 0`), so an emberdeep hall shows its texture, not its
  owner's colour — the same trade the ships took. D-052's "a town hall
  tells you whose ground you are standing on" is carried by the minimap
  mark, the selection ring and the scoreboard until someone paints a
  mask into the `.blend` (vertex alpha, roof and banner — the same
  contract the neutral models use).
- ~~**The placement ghost stays a translucent box** — it never resolved a
  model for any building, so there is nothing for the override to
  change there.~~ **Superseded the next day**
  (`D-20260831-a-placement-ghost-is-the-building-it-will-build`, owner's
  call): the preview wears the model now, resolved through the same
  `model_for` against the viewing player's civ, so an emberdeep player
  previewing a town centre sees the dwarf hall. The sentence was true
  when written and is kept struck through rather than deleted, because
  "there is nothing for the override to change there" is exactly the
  kind of claim this project keeps finding stale in its own entries.
- **`_bastion_model_for` (wall-tower posts) still reads its own model
  derivation.** No wall-family override ships; the day one does, that
  site joins `model_for` or the new test's data guard catches the gap
  the hard way.
- **The storehouse model's texture names it a windmill.** It reads as a
  timber outbuilding at game scale, and it is what the owner supplied
  for the slot.

## Consequences

- A third civ body is one `import_glb_source.py` run, one ROSTER
  fallback entry, one line of `.tres` data, and a `build-assets` run —
  no script change.
- `tests/test_building_model_override.gd` guards the rule, the caller
  (D-106's caller-exists scan) and the data (every override names a
  baked model — a typo'd override falls to the PRIMITIVE, on one civ's
  screen only, which is this project's quietest failure shape).
- The units half of #413 (per-civ override on `UnitDef.model_id`, and
  the four-civ art queue) is untouched and stays cycle 2's.
