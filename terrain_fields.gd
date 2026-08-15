extends RefCounted
class_name TerrainFields

## Everything the terrain mesher needs about a map, computed once (D-096).
##
## ## Why this exists at all
##
## Every field here is a pure function of the map and the `TerrainGen`
## settings, so any of them could be recomputed on demand — and that is exactly
## the defect this project has now paid for five times. `Vision` called
## `TorusSpace.distance()` per candidate cell; `SquadSim` called
## `UnitRoster.by_id` per produced squad; the client sampled terrain noise per
## soldier per frame; the siege pass scanned every building per squad. Each
## time the fix was the same shape: compute it once over the whole map, index
## it afterwards.
##
## The mesher makes that trap unusually easy to fall into, because a hex corner
## is shared by THREE cells: a colour or a height derived per vertex would
## evaluate the elevation and moisture noise eighteen times per hex.
##
## ## Why it is one object and not four arrays
##
## `surface` and `colors` are indexed identically, and both are built from the
## same corner-sharing rule. Passing them separately means every call site can
## get them out of step — pass this year's surface with last year's colours and
## nothing errors, the ground is simply painted wrong. One object built by one
## function cannot be mismatched.
##
## Nothing here is on the wire and nothing here is authoritative. The server
## derives `passability` straight from `TerrainGen`; this is the RENDERING
## side's copy of the same predicate, and `TerrainGen.build_fields` fills
## `passable` from the identical call so the two cannot disagree (D-097).

## One `TerrainGen.Biome` per cell, indexed by `TorusSpace.index`.
var biome := PackedByteArray()

## `TerrainGen.passability` verbatim — 1 where a squad may walk. Carried here
## so a caller that already has the fields does not evaluate the elevation
## noise a second time to ask the same question.
var passable := PackedByteArray()

## One `TerrainGen.CliffClass` per cell — `passable` split by WHICH of its two
## reasons applies (D-097). `passable[i] == 1` exactly when this is LAND, which
## is what keeps the drawn cliff and the pathed one the same boundary.
var cliff_class := PackedByteArray()

## `TerrainGen.SURFACE_STRIDE` rendered heights per cell: the centre first,
## then corners 0..5 in the order `TerrainChunk` emits them.
var surface := PackedFloat32Array()

## Three blend weights per CORNER — 18 floats per cell, in the sorted order
## `TerrainGen.corner_cells` returns and skipping the centre, which is always
## wholly its own cell's.
##
## Stored rather than recomputed because colour and the shader's atlas tiles
## must use the SAME weights: if the texture boundary and the colour boundary
## meandered differently they would cross each other, which reads worse than
## either following the lattice.
var corner_weights := PackedFloat32Array()


## The three owner weights at corner `corner` (0..5) of a cell.
func weights(cell_index: int, corner: int) -> Vector3:
	var base := (cell_index * 6 + corner) * 3
	return Vector3(corner_weights[base], corner_weights[base + 1],
		corner_weights[base + 2])


## `TerrainGen.SURFACE_STRIDE` vertex colours per cell, laid out exactly like
## `surface`. A corner takes the mean of the three cells meeting there; the
## centre keeps its own. `TerrainGen.biome_color` is still the single source of
## truth (D-083) — this is DERIVED from it, which is what keeps the minimap and
## the preview PNG from drifting away from the 3D view.
var colors := PackedColorArray()


## The height of one vertex. `vertex` is 0 for the centre, 1..6 for corners.
func height(cell_index: int, vertex: int) -> float:
	return surface[cell_index * TerrainGen.SURFACE_STRIDE + vertex]


## The colour of one vertex, indexed exactly like `height`.
func color(cell_index: int, vertex: int) -> Color:
	return colors[cell_index * TerrainGen.SURFACE_STRIDE + vertex]
