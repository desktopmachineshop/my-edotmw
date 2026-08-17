# D-20260817 · 2026-08-17 · Accepted — a minimap squad dot is its OWNER's colour, from the one per-player source

**Decision:** the minimap paints a squad in `ClientState.colour_of(owner)`
— the same per-player colour (D-052) the 3D world and the minimap's own
building pass (D-101) already use. `MinimapPaint.squad_marks` is the pure
half, reporting `{squad, owner}` per live squad in squad-id order, exactly
as `building_marks` reports `{cell, owner, size}`.

Three clauses:

1. **Owner in, colour out.** The mark carries an owner id and nothing
   about allegiance. A drawing function may not have its own idea of what
   colour a player is; there is one source and every view resolves through
   it. That is what makes the world, the minimap, the HUD and the
   scoreboard (D-102) agree without any of them being told to.
2. **A viewer-relative colour scheme is not a colour scheme.** "Mine or
   not" is one bit; a match has up to 20 players and D-050 gives some of
   them shared vision. Ownership is not alliance, and neither is identity.
3. **The pass reads `composition`, not `curves`.** That is where the owner
   lives at all — a curve carries position and says nothing about whose
   army it is — and it is what makes D-099 (a concealed squad is drawn
   nowhere) structural rather than a remembered check: conceal moves an
   entry out of `composition` into `_ghosts` (D-025), so there is no mark
   to paint for a ghost.

## Rationale

`_update_minimap` painted squad dots from two hardcoded colours:

```gdscript
var colour := Color(0.35, 0.95, 1.0) if _state.owns(squad) else Color(1.0, 0.35, 0.28)
```

Cyan if the viewer owns it, red otherwise. Reported by the owner from the
#29 lobby playtest (issue #82): an army that is red in the world and red in
the lobby seat list draws **cyan** on the minimap, and an ally who is
**blue** in the lobby draws **red** — identical to an enemy.

**The interesting part is the age.** `git log -S` puts that line in
fb7e140, 2026-07-30, "Add a wrap-aware minimap" — M3, where it was
correct: there were no per-player colours to read. Per-player colours are
D-052, from M6. When colours became per player, the minimap's squad pass
was never revisited, and **nothing failed** — a minimap with two colours on
it looks exactly like a working minimap. So this is the
declared-and-unread family (CLAUDE.md's standing warning) inverted: not a
member nobody reads, but a **rule nobody re-read after the thing it
depends on changed underneath it**. The grep that finds an uncalled
public member finds none of these; only playing does.

By the time it was found, the same 70-line function was painting buildings
correctly through `colour_of` and squads through the M3 scheme, with a test
one file away asserting a building is drawn *"in its owner's colour, not
the viewer's"*. The inconsistency was internal to one function.

**It is worse than cosmetic.** D-050 gives teammates shared vision, so an
ally's army is precisely the kind of thing a player sees on the minimap and
nowhere else — and it was painted in the enemy tone. A player reading the
minimap to decide where to send troops was shown their ally as a threat.
It also half-undid the feature that had just landed: D-102's scoreboard
exists so a player can learn which colour is whose, and the minimap
immediately contradicted it.

**Why `squad_marks` exists rather than a one-line colour swap.** The fix
itself is one expression. But squad dots did not go through `MinimapPaint`
at all — D-101 created that module as "the pure half of the minimap,
testable headless, because the client itself is not (D-014)" and left
squads behind in the untestable half, which is why the defect had no test
that could see it while the building pass beside it did. Routing squads
through the same door puts both passes under the same assertion.

**The transparent-dot detail:** `_owner_colour_of` (the 3D view's helper)
returns `Color(0, 0, 0, 0)` when a squad has no composition entry yet.
Reading `composition` directly sidesteps that — a squad with no entry
produces no mark rather than a black dot — and the pass skips any mark
whose curve has not arrived, where `squad_cell`'s `Vector2i.ZERO` fallback
would otherwise plant an army in the map's corner.

## Rejected alternatives

- **`var colour := _owner_colour_of(squad)`, keeping the `curves` walk.**
  The one-liner the issue proposed, and it does fix the reported symptom.
  Rejected because it leaves squad dots outside `MinimapPaint`, so the only
  test that could ever guard the colour stays a source scan with no pure
  half — and it inherits the transparent-dot case the issue itself flagged.
- **Colour by allegiance — own / ally / enemy, three tones.** Legible, and
  it throws away the identity D-052 and D-102 were built to give. Which
  ally is a question a player asks constantly, and a shared ally tone
  cannot answer it.
- **Tint or outline the viewer's own squads on top of the owner colour.**
  A real ergonomic question ("where am I") and a separate one; the minimap
  answers it today with the camera ring (`_build_nav_ring`). Adding a
  second visual channel here before anyone reports needing it would be
  inventing a scheme beside D-052 again, in a subtler form.
- **Draw ghosts in a faded owner colour.** Contradicts D-099 outright: a
  concealed squad is drawn nowhere, minimap included.

## Consequences

- `MinimapPaint` gains `squad_marks`. `_update_minimap`'s squad pass loses
  its `_state.owns` call and both hardcoded colours; a test scans
  `client.gd` and fails if either literal reappears anywhere in the file.
- **`is_ghost` leaves the minimap pass, and the D-099 guard changed with
  it.** `tests/test_ghost_squads_are_not_drawn.gd` demanded the literal
  string `is_ghost(` inside `_update_minimap`; it now asserts the pass is
  driven by `composition` and does **not** walk `_state.curves`, plus a
  behavioural check through the real wire (SQUAD_INFO for two owners, then
  SQUAD_CONCEAL for one, then exactly one mark). The property got stronger
  — a check that can be forgotten became one that cannot be written wrong —
  so the guard was rewritten rather than dropped.
- Cost: one dictionary walk over live squads at `MINIMAP_INTERVAL`
  (0.25 s), replacing a walk over `curves`. Nothing per-tick, nothing on
  the wire, nothing on the server.
- **#29's remaining pass criterion** ("each player has a distinct colour,
  consistent between world, minimap and HUD") is now satisfiable; it was
  failing on the minimap alone.

## Revisit trigger

Any view acquiring a colour rule of its own — the scan in
`tests/test_minimap_paint.gd` is per-literal, so a *new* hardcoded pair
would pass it and is the gap to watch. Also: a match size where 20 distinct
`PlayerColours` stop being distinguishable at one pixel per cell, which is
a `PlayerColours` question rather than a minimap one.
