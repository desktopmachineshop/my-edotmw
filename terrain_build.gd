class_name TerrainBuild
extends RefCounted

## The ground, built a SLICE AT A TIME
## (D-20260818-terrain-builds-a-slice-at-a-time).
##
## Building the shipped 168x194 map costs several seconds of one core, and
## `client.gd` spent all of it inside a single `_build_terrain()` call before
## the first frame of a match — a frozen, unresponsive window, found by a human
## closing it and asking whether the server was down (#106). The server was
## fine; nothing about this is a simulation cost.
##
## So this is D-040's fix applied to the other side of the wire: the work is
## budgeted in CELLS across frames and partial progress is KEPT, which is
## exactly what made budgeting the flow field work where budgeting whole field
## BUILDS had failed.
##
## ## What the slices are FOR, which is not what #106 first assumed
##
## The issue asked for a world playable within 1.5 s with the ground streaming
## in around the player. The owner's call is a **loading bar and up to 30
## seconds** instead, so the slices exist to keep the window alive and the bar
## honest rather than to make a half-built world playable — and the player
## enters a match whose ground is entirely there, which is the older and safer
## contract (nothing is ever drawn standing on fields that do not exist yet).
##
## A slice is therefore sized so the bar moves smoothly and the window pumps
## its events, NOT so a match stays playable underneath it. The totals are the
## same either way: measured on the default map, streaming the whole build costs
## the same wall clock as doing it in one pass, to within the run-to-run noise
## of a loaded host.
##
## ## The two phases are not the same kind of thing
##
## The FIELDS (heights, colours, biomes, passability) are the map: a soldier
## stands on them and the minimap is painted from them. A half-built fields
## array is not a smaller map, it is a map with a sea-level hole in it, so
## nothing may read them until `fields_ready()`. The CHUNK MESHES are only a
## picture of the fields. Both are counted into `progress()`, weighted by what
## they actually cost, because a bar that ran to 100% and then sat there for
## twenty seconds would be worse than no bar at all.
##
## Pure, and no scene tree: `take_meshes()` hands over `ArrayMesh` resources and
## the client parents them. Same split as `render_cull.gd` and
## `selection_pick.gd` — the half with the interesting failure mode is testable
## without a GPU.

## Cells of field work one slice may do. Measured on the default map: a
## corner-pass cell costs tens of microseconds, so this is a slice of roughly
## 30-100 ms depending on how loaded the host is — short enough that the window
## keeps redrawing, long enough that per-slice overhead stays invisible against
## the work itself.
const FIELD_CELLS_PER_SLICE := 512

## Cells of MESHING one slice may do. A chunk is atomic, so this is really "one
## 16x16 chunk". Two chunks a slice would double the worst slice for no gain a
## player watching a bar can see.
const MESH_CELLS_PER_SLICE := 256

## What a cell of pass-one field work counts for against a cell of the corner
## pass, and what a cell of MESHING counts for. Measured on the default map
## (2026-08-18): pass one is ~4 us a cell, the corner pass ~55-110, meshing
## ~150-200. The bar is only as truthful as these are roughly right — equal
## weights put it at 50% when a third of the wall clock had passed.
##
## The class pass (D-20260826-passable-means-flat-enough-to-cross) is six
## array reads and a compare per cell — no noise — so it is weighted below
## even pass one rather than left out: a pass the bar cannot see is a
## stretch where the bar stands still, which is the "must make progress"
## failure with a paint job.
const PASS_ONE_WEIGHT := 0.05
const CLASS_PASS_WEIGHT := 0.01
const MESH_WEIGHT := 2.5

var space: TorusSpace
var terrain: TerrainGen
var chunk_size: int

## The finished fields, or null while they are still being built. The one thing
## a caller must not do is read this before `fields_ready()` — see
## `TerrainGen.fields_step`.
var fields: TerrainFields = null

## How many slices this build has taken, and the worst and total wall clock it
## spent inside them. Reported, never gated: this project's own rule is that a
## budget test asserts WORK and a stopwatch only prints
## (`docs/status/ground-fog.md`). They exist because #106's exit criterion is a
## measurement, and a measurement nobody prints is an opinion.
var slices := 0
var worst_slice_usec := 0
var total_usec := 0
## Wall clock at the moment the fields finished, so the load can be reported as
## the two phases it actually is.
var fields_usec := 0

var _work := {}
var _chunks: Array[Vector2i] = []
var _next := 0
var _ready_meshes: Array[ArrayMesh] = []
var _cells := 0


func _init(p_space: TorusSpace, p_terrain: TerrainGen, p_chunk_size: int) -> void:
	space = p_space
	terrain = p_terrain
	chunk_size = maxi(1, p_chunk_size)
	_cells = space.cell_count()
	_work = terrain.fields_begin(space)
	var grid := TerrainChunk.chunk_grid(space, chunk_size)
	for cy in range(grid.y):
		for cx in range(grid.x):
			_chunks.append(Vector2i(cx, cy))


## Advance the build by one slice. Returns true when everything is done.
##
## Spends its budget on the fields first and returns the moment they are
## finished, so the frame that completes them does not also pay for a chunk —
## the two slices are sized separately for a reason.
func step() -> bool:
	if is_complete():
		return true
	var started := Time.get_ticks_usec()
	slices += 1

	if fields == null:
		if terrain.fields_step(_work, FIELD_CELLS_PER_SLICE):
			fields = _work["fields"] as TerrainFields
			# Dropped rather than kept: the intermediate buffers are about as
			# large as the fields themselves, and this runs once per match.
			_work = {}
		_charge(started)
		fields_usec = total_usec
		return false

	var spent := 0
	while _next < _chunks.size() and spent < MESH_CELLS_PER_SLICE:
		var mesh := TerrainChunk.build_mesh(space, terrain, _chunks[_next],
			chunk_size, fields)
		_next += 1
		spent += chunk_size * chunk_size
		# A chunk that meshes to nothing hands back null, and a caller counting
		# chunks should not be given one to filter.
		if mesh != null:
			_ready_meshes.append(mesh)
	_charge(started)
	return is_complete()


func _charge(started: int) -> void:
	var elapsed := Time.get_ticks_usec() - started
	total_usec += elapsed
	worst_slice_usec = maxi(worst_slice_usec, elapsed)


## Whether the fields are finished. Chunks are meshed after this, never before.
func fields_ready() -> bool:
	return fields != null


func is_complete() -> bool:
	return fields != null and _next >= _chunks.size()


## How far along the whole build is, in [0, 1] — what the loading bar draws.
##
## Weighted by measured cost rather than by cell counts, for the reason
## `MESH_WEIGHT` gives: the three passes are an order of magnitude apart, and a
## bar that spends nine tenths of its time in its last tenth is a bar nobody
## believes twice.
func progress() -> float:
	var pass_one := _cells * PASS_ONE_WEIGHT
	var classes := _cells * CLASS_PASS_WEIGHT
	var corners := float(_cells)
	var meshing := _cells * MESH_WEIGHT
	var total := pass_one + classes + corners + meshing
	if total <= 0.0:
		return 1.0
	var done := 0.0
	if fields == null:
		done = int(_work.get("cells_done", 0)) * PASS_ONE_WEIGHT \
			+ int(_work.get("classes_done", 0)) * CLASS_PASS_WEIGHT \
			+ float(int(_work.get("corners_done", 0)))
	else:
		done = pass_one + classes + corners \
			+ meshing * float(_next) / float(maxi(_chunks.size(), 1))
	return clampf(done / total, 0.0, 1.0)


## The meshes built since the last call, handed over rather than shared — the
## builder keeps no reference, so a caller that parents them owns them.
func take_meshes() -> Array[ArrayMesh]:
	var out := _ready_meshes
	_ready_meshes = []
	return out


## How many chunks have been meshed, of how many the map has.
func chunks_done() -> int:
	return _next


func chunk_total() -> int:
	return _chunks.size()
