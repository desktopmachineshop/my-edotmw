### D-20260817 · 2026-08-17 · Accepted — the zoom cap was modelling the wrong axis, and the map ladder moves up a rung

**Decision:** `RenderCull.max_camera_height` is **derived** from the camera
rig and the window's aspect instead of a hand-measured `0.33`, and the
shipped map sizes all move up one rung so the honest cap is a generous
zoom rather than a cramped one.

    Skirmish  84 x 96  =   8,064 cells   (was  42 x 48  =  2,016)
    Standard 168 x 194 =  32,592 cells   (was  84 x 96  =  8,064)   <- default
    Large    252 x 290 =  73,080 cells   (was 126 x 146 = 18,396)
    Huge     336 x 388 = 130,368 cells   (was 168 x 194 = 32,592)

`maps/ladder.tres` stays at 42 x 48 and stays out of `MapSettings.sizes()`.

---

**Rationale.** Terrain is drawn nine times (D-035) and every squad,
building and resource node is drawn ONCE, so the whole scheme is correct
only while no cell is on screen at two lattice copies at the same time.
`max_camera_height` is the thing that is supposed to guarantee that. It
did not, and had not since the maps were reshaped.

The old cap was `min(x_period, z_period) * 0.33`, where 0.33 came from a
ruler held against a 128x64 map at 1280x720: forward ground reach ~1.9h,
camera 0.6h behind its target, on-screen z span ~2.6h. **The z span was
right. It was the wrong axis.** The frame is a truncated pyramid, so its
widest ground line is the far edge, and the width there comes from the
HORIZONTAL half-angle — on a `KEEP_HEIGHT` camera that is
`atan(tan(fov/2) * aspect)`, 53.75 degrees at 16:9 against the 37.5 the
vertical gives. Working it through the rig:

    k_z = cot(pitch - fov/2) - cot(pitch + fov/2)        = 2.6485
    k_x = 2 * sin(fov/2) * aspect / sin(pitch - fov/2)   = 5.8963

x is binding by a factor of 2.2, and the cap modelled only z. Measured
consequence on the 84x96 map at the default height of 40: a far band
236 world units wide against a 145.5-unit x period — **1.6 periods, the
same ground drawn twice**, one copy carrying the forests and its sibling
bare. That is what playtest reported as forests appearing and
disappearing while panning, and it is what survived the chunk-culling fix
in the D-045 amendment above.

**The old cap failed at every size, and bigger maps alone could never
have fixed it.** The cap was itself a fraction of the period, so the
ratio `k_x * cap / x_period` is scale-invariant at **1.93** — 42x48 and
168x194 alike. Only the 90-unit absolute ceiling breaks the invariance,
and not by enough: the old Huge sat at 1.82 periods. A test perturbed
back to `0.33` reports two copies on all four sizes.

**Why the sizes move.** With an honest cap you may zoom out until you see
exactly one whole world and no further, because that is what "no cell
twice" means. On a small map that is a glance: the cap on 84x96 falls
47.5 -> 24.7, and the entire map is on screen at 24.7. Nothing is lost
visually — the zoom removed only ever showed repeats — but a world you
can take in at once has no fog and no scouting, and fog is most of this
game's information model (D-004/D-025). D-056 also wants matches an order
of magnitude longer than today's ~200 s, and marching distance is the
cheapest honest lever on it. So the floor rises to the old Standard and
the default becomes the old Huge, where the cap is **49.4 — slightly more
absolute zoom than the 47.5 players have today**.

**Rejected alternatives:**

- **Draw entities at every visible copy** (named in `render_cull.gd`'s
  own doc since M5). This deletes the constraint outright, and with it
  the whole recurring bug class — squads vanishing at the seam, "half the
  screen renders no units", click-selects-nothing, forests snapping a map
  period sideways. It is genuinely the better architecture and it is
  rejected here only on scope: the immediate defect is a wrong constant,
  and the copies would touch entity picking (which reads `node.position`
  as *the* offset), LOD tier selection, and the missile and selection-disc
  paths. **This is the first thing to reach for if the cap ever becomes a
  design constraint somebody wants to break**, and cheap for static
  drawables — a second `MultiMeshInstance3D` sharing the same `MultiMesh`
  resource costs no extra derivation.
- **Camera-relative re-basing** (the Civ/freeciv approach). Does not
  remove the constraint — it still needs the view span under one period —
  and fails worse when violated, showing void rather than bare ground.
- **A real sphere** (Planetary Annihilation). D-008 considered and
  rejected it; nothing here reopens that.
- **Lowering `CAMERA_MAX_HEIGHT` alone.** Would fix duplication at the
  ceiling and leave the 0.33 wrong underneath it, ready to re-bite the
  next time a map smaller than the floor is added.
- **Keeping the small sizes.** They are correct and playable under the new
  cap; they are dropped for the fog/scouting and match-length reasons
  above, not because anything renders wrong on them.

**Consequences:**

- `max_camera_height` gains `aspect` and `fov` parameters and `client.gd`
  passes the real window's, so an ultrawide monitor earns a lower cap
  instead of silently showing the world twice. It is re-derived on
  `size_changed`, because a cap computed once at startup goes wrong the
  first time somebody drags a window edge.
- `RenderCull.PITCH_RUN` is now the one definition of the rig's 0.6, read
  by `_update_camera`. The cap is entirely a statement about that angle
  and the two were separate literals in separate files.
- **Timings that depend on marching distance roughly double.**
  `just test-load`'s duration, `bot_client.gd`'s phase comments (already
  stale — they cite 128x64), and `test-client`'s scripted phases. Recorded
  in `docs/status/load-testing.md`; this is the D-031 stale-timing trap
  again and it will catch somebody.
- **The top two sizes are extrapolation, not measurement.** M4 measured
  worst tick flat in map size from 2,048 to 32,768 cells (D-040);
  130,368 is 4x beyond that. A bigger map costs pathing LATENCY rather
  than a tick spike, because `field_cells_per_tick` is a per-tick budget
  — at 4,096 a full field on the new default takes ~8 ticks (0.8 s) and on
  the new Huge ~32 (3.2 s). Raising that budget is the obvious lever and
  it trades straight against worst tick.
- Client terrain meshing was 600-1,100 ms on 8,064 cells, so ~2.4-4.4 s on
  the new default and 10-18 s on the new Huge, once per match.
- `TerrainGen.REFERENCE_WIDTH` stays **84** and is no longer "the Standard
  width" — it is the width the shipped `/terrain` presets were tuned at.
  Re-pointing it at whatever is currently called Standard would halve
  every preset's effective frequency without anyone editing a preset,
  which is exactly the silent drift D-105 exists to stop. Bigger maps
  therefore hold MORE features, not bigger ones.
- `tests/test_render_cull.gd` now asserts `default width mod 16` lands in
  1..8, because PR #74's block-centre regression test is only meaningful
  on a width that is not a multiple of `NODE_CHUNK`. 84 gave 4; 168 gives
  8, the last value that still works. Observed red at 176.
- `world_look.gd`'s `DEFAULT_CAMERA_MAX_HEIGHT := 31.6` was documented as
  "the Standard map's `max_camera_height`" and never was — 31.6 is the
  old 128x64 figure, and the live number is 49.4. The value is left alone
  (it reproduces the original hand-tuned fog density for previews, which
  a test pins); the false claim is gone.

**Measured, `just test-load 4 300` on the new default map, 2026-08-17**
(instance `ao-my-edotmw-40-zoom-cap` per D-095). Clean verdict, 4/4 bots,
**0 desyncs, 0 dropped ticks, worst tick 44.9 ms** against D-020's 100 ms:

| | value | against |
|---|---|---|
| per-squad update | **167.7 µs at 48 squads** (vision 13.0, combat 32.7) | ~83 µs at 28 squads on 84x96 |
| `field_waits` | **2,968 of 3,005 ticks** | the cost predicted above |
| fog gating, nodes | 7,442 of 7,694 hidden | 1,700 of 1,958 before |
| fog gating, squads | 16 of 48 hidden | 13 of 28 before |
| `reveal_events` | **63** | 0-1, i.e. issue #69's flaky gate |

Three things to take from that, quoted with their squad counts as ever:

- **The tick budget is met with room** — 44.9 ms worst against 100 ms, no
  dropped ticks, on a map 4x the old area.
- **The per-squad figure doubled and that is real.** It is not the
  low-count inflation CLAUDE.md warns about: squad count went UP (28 ->
  48), which should dilute per-tick fixed overhead, and the number rose
  anyway. Vision and combat both FELL (they scale with disk radius, not
  map area); the rise is elsewhere, and `field_waits` on 99% of ticks
  says flow-field solving. `field_cells_per_tick` at 4,096 is an eighth
  of a field on this map, so a squad can wait ~0.8 s for a path. **That is
  the number to watch and raising the budget is the lever**, traded
  against worst tick — deliberately not tuned here, so the size change
  and the budget change do not get measured through each other.
- **Fog got its teeth back**, which is the point of the size increase
  stated as a measurement rather than an intention. `reveal_events` went
  from the 0-1 that has been failing intermittently on `main` (issue #69)
  to 63.

**Revisit trigger:** any change to the camera's pitch ratio
(`RenderCull.PITCH_RUN`), its fov, or the addition of a map size below the
floor — each of which changes what the cap must be. Also if the pathing
latency on the two largest sizes is measured and found intolerable, since
the honest response is fewer sizes rather than a dishonest cap.

---

**Not fixed here, found while inventorying:** per-soldier selection discs
are drawn at the canonical position with no lattice offset
(`client.gd`'s `_refresh_selection_discs`), so they detach from a wrapped
squad; and a missile's endpoints are baked from `centre + offset` at
launch, freezing it to the copy it was fired at. Both are the same
copy-choice family and both want the "draw at every copy" answer rather
than another per-site rule.
