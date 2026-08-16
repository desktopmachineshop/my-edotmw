### D-106 · 2026-08-16 · Accepted — the ground has fog of war, in three states

*(Numbered 106 by assignment, not by counting. `main` tops out at D-098 and
several fix sessions were running off it in parallel, each independently
picking "the next free ID" — this entry was drafted as 101, renumbered to 102
on noticing another worktree's draft, and collided again. IDs for the open set
were then handed out centrally: 099, 100, 101, 102, 103, 104, 105 belong to
other PRs and 106 to this one. Third time this project has paid for an ID
collision — see D-081's editorial note — and the first time the fix was to stop
letting each author choose.)*

**Decision:** unscouted **terrain** is drawn black, terrain the player has seen
but cannot currently see is drawn dim, and terrain in sight is drawn fully.
Three states, per cell, client-side:

1. **`terrain_fog.gd`** holds the field — one byte per cell, UNEXPLORED /
   EXPLORED / VISIBLE — stamped from this player's own (and allied, D-050)
   squads and buildings through `TorusSpace.disk_offsets`, exactly as
   `vision.gd` stamps the server's. Explored is persistent: terrain does not
   move, so once seen it is never un-known (the same rule D-030 gives
   buildings).
2. **The field reaches the renderer as a texture**, one texel per cell, laid
   out like `TorusSpace.index`, sampled per ground fragment through a new UV2
   channel that `TerrainChunk.fog_uv` derives from the **cell** — never from
   world position, so all nine lattice copies (D-035) agree, the same
   constraint the atlas UVs already work under. `shaders/terrain.gdshader`
   multiplies ALBEDO (and SPECULAR) by it.
3. **The fog uniform defaults to white.** `bench-render`, `gen-terrain-shot`,
   `gen-model-preview` and `gen-cover-preview` share `make_material()` and have
   no player whose knowledge could be asked about; they keep rendering the
   whole map without knowing this feature exists.
4. **The client's camera opens on the player's own ground** rather than on the
   middle of the map, because the middle of the map is now black.

**Why this was not already covered by D-004/D-025.** Those define fog as curve
gating — entity state withheld on the wire — and terrain is not entity state.
It is derived client-side from the map settings (D-049), identical for every
player, and there is nothing about it to withhold. So the ground fell outside
the fog mechanism entirely and nothing noticed: `client.gd`'s `_explored` set
was correct, was documented as "the map starts black and is revealed by line of
sight", and was read at exactly two sites, both inside `_update_minimap`. The
minimap was the only surface in the game that drew any fog at all, for six
milestones, while the 3D world drew the whole map lit from the first frame.
Found by the owner playing (#58, playtest P12), not by any check.

That makes this the fifth instance of the family CLAUDE.md already names —
`UnitDef.cost`, `BuildingDef.cost`, `BuildingSim.damage` (D-055), three
`CivDef` knobs — and specifically of D-065's harder variant: **a doc comment
that describes a behaviour is not evidence the behaviour exists.** The rule
that comes out of it is the one this entry's tests are built on: when a
mechanism is supposed to be VISIBLE, assert that something outside its own file
calls it.

**Why three states rather than two.** Two would either black out ground the
player has scouted — throwing away the map they earned, and making a base
invisible the moment the last unit leaves it — or leave it lit, which claims
knowledge the player does not have. The middle state IS the information: it is
what separates "I remember a town centre here" from "I can see it now", and the
entity layer has drawn that distinction since D-025's ghosts. The ground was
the only part of the picture that did not.

**Rejected alternatives:**

- **A fog volume / post-process over the whole scene** — dims units, trees,
  buildings and UI along with the ground, and the entity layer already has its
  own truthful answers (server gating, ghosts). Would have made a concealed
  squad's ghost and a lit squad differ by *two* mechanisms.
- **Per-vertex fog baked into the chunk meshes** — the fog changes several
  times a second and remeshing the standard map costs 600–1,100 ms.
- **Deriving the cell from world position in the shader** — cheaper (no vertex
  channel) and wrong: D-035 draws the same meshes at nine offsets, so each copy
  would fog differently. It would also be a second definition of
  world-to-cell, which `torus_space.gd` exists to be the only one of.
- **Recovering the cell from the existing atlas UV** — nearly free, and it
  breaks on the cliff skirts (D-097), whose UV.y is derived from world HEIGHT.
  Rock faces would have read the fog of a row they are not in.
- **Gating terrain on the wire to match the entity layer** — nothing to gate;
  the client generates it from the seed. Fog on terrain is presentation, and
  saying so plainly is what keeps it out of the desync surface.
- **A hard per-cell edge (no blur)** — measured against D-096's finding: a
  one-cell transition at high contrast puts the 50% contour on the hex edges
  and reads as scalloped, and black-against-lit is the strongest contrast the
  map can produce. The field is blurred over the hex neighbourhood before
  upload, which with the texture's own bilinear filtering spreads the edge over
  about three cells.

**Consequences:**

- **Ground fog is presentational and carries no authority.** A client that
  computed it wrongly would draw its own map wrongly and gain nothing: squads,
  buildings and node depletion are all gated server-side. That is what makes
  local derivation legal here, exactly as it already was for the minimap.
- **`client.gd`'s explored set is gone**, replaced by the field above; the
  minimap now reads `TerrainFog.is_explored` and is otherwise untouched. The
  minimap's own missing third state is a separate issue and deliberately not
  changed here.
- **The client's fog radius uses the same world-units-to-cells conversion
  `Vision` does** (`TerrainFog.radius_in_cells`), pinned by a test. A client
  that rounded differently would draw a lit disk one ring wider or narrower
  than the one the server actually gates on, and enemies would step out of
  ground the player is being shown as dark.
- **The camera now opens on the player's spawn.** Not cosmetic: the previous
  default (map centre) is unexplored black on a 128×64 map, so a match would
  have opened on an empty screen.
- **`client.gd` reports `textured=` and `fogged=` when it builds terrain.**
  Both of those fail silently and identically — ground that is drawn and wrong
  — and the second one is this entry's whole subject.
- Cost, measured rather than assumed: **5.76 ms per refresh on the shipped
  8,064-cell map** (12 seeing things at radius 7), in the test container on a
  host running four other agents — so four refreshes a second is ~2% of wall
  time, and the figure is an upper bound rather than a typical one. Plus an
  8 KB texture upload, one extra `vec2` per terrain vertex, and one texture tap
  per ground fragment against the three the atlas already takes. A loose
  regression bound sits on it in `test_terrain_fog.gd` — loose because a tight
  timing gate on a shared host gets muted rather than fixed; what it is really
  guarding is the shape, since the two ways this could have been written
  (`distance()` per cell, `neighbor_index` per query) are orders of magnitude
  away rather than a little.
- `test-unit` green at 692 tests across 46 scripts; `test-client` clean, with
  `fogged=true` and a frame in which only scouted ground is lit; `test-load`
  unaffected (it renders nothing) — figure and squad count in the PR.

**Revisit trigger:** terrain-occluded line of sight (still open since D-025).
The moment elevation decides what a unit can SEE, the field this draws stops
being a disk stamp and the two halves — what the server gates and what the
client shades — have to be derived from one definition rather than from the
same radius twice. Also revisit if ground cover (D-100) is ever wired into the
client: props are client-derived and NOT fog-gated by that decision, so a fern
would stand fully lit on black ground.
