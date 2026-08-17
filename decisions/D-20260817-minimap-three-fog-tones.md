# D-20260817 · 2026-08-17 · Accepted — the minimap draws three fog tones, from `TerrainFog`'s levels

**Decision:** the minimap paints **three** tones, one per `TerrainFog`
level, and `MinimapPaint.fogged` is the one definition of them:

| level | minimap |
|---|---|
| `TerrainFog.UNEXPLORED` | `HudTheme.BG_VOID.darkened(0.5)`, **independent of the biome underneath** |
| `TerrainFog.EXPLORED` | the biome colour lerped `EXPLORED_DIM` (0.55) toward `HudTheme.BG_VOID` |
| `TerrainFog.VISIBLE` | `TerrainGen.biome_color` **exactly, untouched** |

Four clauses:

1. **The minimap reads `TerrainFog`; it does not keep a fog set of its
   own.** `_fog.level_at()`, the same field `_update_fog` stamps and
   `_push_fog_to_terrain` uploads to the ground shader. One derivation of
   one player's sight, for both views.
2. **Fog only ever subtracts.** `VISIBLE` is the untouched one. A minimap
   that BRIGHTENED live cells would draw a colour no other view of this
   map has, and D-083 kept one colour table (`biome_color`) precisely so
   the minimap, the terrain preview PNG and the 3D ground cannot disagree.
3. **The three tones are one line** — `UNEXPLORED` < `EXPLORED` <
   `VISIBLE` in brightness, with a real gap at each step, measured at
   every biome on the shipped palette rather than on a fixture.
4. **Buildings are the deliberate exception and are painted unfogged.**
   D-101 draws a building from KNOWLEDGE; fading one because nobody is
   currently watching it would re-gate it on vision through the back door.
   Ground and resource nodes do shade, so a node a scout walked past three
   minutes ago is exactly as faded as the ground it stands on.

## Rationale

The minimap drew **two** states where the game has three. `_explored` was
grow-only and nothing computed a currently-visible set for it, so
`_update_minimap` asked one question per pixel — explored or not — and
remembered ground rendered **pixel-identical** to live vision. What read
on screen as "grey versus visible" was unexplored-black versus everything
else.

Reported by the owner during playtest P12 (#40, issue #59) as minimap fog
"works but isn't distinct enough between visible and grey". That framing
is worth recording: **a report about how something looks can be a report
that a rule is absent.** The natural response to "not distinct enough" is
to reach for the palette, and no amount of contrast tuning separates two
things drawn from one value.

**Why the dim is a lerp toward `BG_VOID` and not a `darkened()` multiply:**
a multiply keeps hue and scales brightness, which sounds right and puts
the darkest biome in danger. `DEEP_WATER` is (0.08, 0.20, 0.42); multiplied
down 55% it lands near enough the unexplored tone (10, 9, 7) that deep
ocean a player *has* scouted would read as ocean they have not. The lerp
makes "remembered" literally partway back to "never seen" and leaves the
darkest biome at roughly (20, 33, 56).

**Why `EXPLORED_DIM` is its own number and not `TerrainFog.SHADES[EXPLORED]`
(0.45):** that one multiplies ALBEDO on lit 3D ground under D-086's sky and
tonemap; this one blends a flat pixel toward a UI colour. Tying them
together would make either view's tuning silently retune the other. They
are deliberately near each other and deliberately not the same constant.

## The history is the interesting part, and it is a near-miss

This decision was **written before `TerrainFog` existed** and originally
carried its own explored/visible sets, its own `minimap_fog.gd`, and its
own stamping walk over squads' and buildings' vision disks. It was
correct, tested, and — by the time it came to merge — **a second
derivation of exactly what D-106 had just built for the ground.**

Both were developed in parallel off the same main, and both independently
concluded that fog needs three states rather than two. D-106's
`TerrainFog` even chose the same method name (`_update_fog`) and the same
4 Hz cadence. Had the two been merged mechanically, the client would have
carried two fog fields for one player, stamped from the same disks a few
milliseconds apart, with nothing failing — and they would have drifted the
first time either was touched. The symptom would have been a minimap
disagreeing with the ground beside it about what the player can see.

**So the resolution deleted more than it added.** `minimap_fog.gd` and its
whole state machinery are gone; what survives is the ~15 lines that were
genuinely missing, which is the *shading*. This is D-095's lesson in a
different costume — two derivations of one identity is the failure, not
the duplication of code — and it is also this decision's own revisit
trigger firing during the merge that created it: the entry already said
"when world fog lands it should read these same three states rather than
inventing its own."

Recorded because the near-miss is the reusable part: **when two parallel
branches solve the same problem for different surfaces, the merge is a
design step, not a text operation.**

## Rejected alternatives

- **Keep both fog fields and merge them mechanically.** Compiles, passes
  every test on both sides, and ships the drift described above.
- **Brighten `VISIBLE` instead of dimming `EXPLORED`.** Cheaper (leave
  both existing branches alone, add a highlight) and wrong: it puts a
  colour on the minimap that `biome_color` never produced.
- **Reuse `TerrainFog.SHADES` as a multiplier on the minimap.** One
  constant instead of two, and it bottoms out at pure black — right under
  a sky, wrong for a widget that has always drawn unexplored as `BG_VOID`,
  and it would couple two unrelated tuning surfaces.
- **Dim building marks along with everything else.** Consistent-looking
  and contradicts D-101 clause 1: a known building is knowledge, not
  sight.
- **Fade `EXPLORED` with age.** A lie about what the client knows —
  memory is memory, there is no "half-remembered" — and it needs per-cell
  timestamps, which is per-cell state in a cosmetic disguise.
- **Replicate the visible set from the server.** Rejected on D-006's
  derivation argument, and moot once `TerrainFog` derives it locally.

## Consequences

- `MinimapPaint` gains `fogged`, `EXPLORED_DIM` and `UNEXPLORED_DIM`.
  `minimap_fog.gd` and `tests/test_minimap_fog.gd` do not exist; their
  surviving checks live in `tests/test_minimap_paint.gd`.
- The minimap pixel loop gains one `level_at` and one `get_pixel` per
  fogged pixel, at `MINIMAP_INTERVAL` (0.25 s). Nothing per-tick, nothing
  per-soldier, nothing on the server, nothing on the wire.
- **#40's criterion 5 is now satisfied on both sides.** The ground has fog
  (D-106) and the minimap matches it, reading the same field. Neither view
  is more informative than the other.
- Two guards in `tests/test_minimap_paint.gd` are source scans over
  `client.gd`, which cannot be instantiated headless (D-014): that the
  minimap reads `_fog.level_at`, and that the building pass does **not**
  run its colour through `fogged`. The second exists because that is the
  precise line where these two features could have silently eaten each
  other.

## Revisit trigger

Elevation or anything else acquiring the power to occlude vision, which
would give both fog surfaces a fourth thing to say; `TerrainFog` gaining a
level, which `fogged`'s `match` must then answer for; or the owner
reporting the step still does not read, in which case `EXPLORED_DIM` is
the one number to move and the guarding test's minimum gap moves with it.
