**The ground has fog of war now, and did not for six milestones (D-106,
2026-08-16).** The 3D world drew the whole map lit from the first frame:
unscouted ground looked exactly like ground you were standing on, and the
minimap was the only surface in the game that drew any fog at all. Found by
the owner playing (#58), not by any check.

The cause is the exact shape CLAUDE.md already warns about, one level worse.
`client.gd`'s `_explored` set was correct, was documented as "the map starts
black and is revealed by line of sight", and was read at exactly two sites,
both inside `_update_minimap`. Nothing failed. Every entity-level fog
mechanism (D-004 gating, D-025 conceal, D-030 explored buildings, D-087 node
depletion) was real and tested. **Terrain was simply never part of it, and
because terrain is derived client-side from the seed there is no wire evidence
of the gap either.** So: fifth instance of the declared-and-unread family, and
D-065's harder variant of it — *a doc comment describing a behaviour is not
evidence the behaviour exists.*

Three things to carry forward:

- **Fog on the ground is three states, not two** — unexplored black, explored
  dim, visible full. Two would either black out the map a player earned or
  claim knowledge they do not have. `terrain_fog.gd` is vision.gd's sibling:
  same disk stamp, but presentational, so nothing it computes reaches the wire
  and a wrong answer cannot gain an advantage.
- **The test that catches this class asserts the CALLER exists.** Every other
  check can pass while nothing draws the thing. `test_terrain_fog.gd` scans for
  a `TerrainChunk.set_fog` call outside `terrain_chunk.gd` — the "grep for
  uncalled public members" rule, written down as a test.
- **The client now prints `textured=` and `fogged=` when it builds terrain**,
  because both fail silently and identically: ground that is drawn and wrong.

Also: the camera opens on the player's spawn rather than the map's centre,
which was harmless while the whole map was lit and is an empty black screen
now.
