extends RefCounted
class_name RenderCull

## Wrap-aware render culling (D-045).
##
## The client derives every soldier of every squad it knows about, every
## frame, from the squad's curve (D-006). At D-018's full scale that
## measured 66 ms a frame with 96% of it in derivation — while Godot's own
## culling was discarding most of those squads before they ever reached
## the GPU. The engine was throwing away work the client had just paid
## for. This decides what NOT to derive.
##
## ## The torus makes this harder than a frustum test
##
## The world tiles (D-035): the client draws terrain nine times so it does
## not visibly end. A squad standing just past the seam is therefore
## on screen at a WRAPPED position while its canonical coordinates are a
## whole map away. Culling on canonical coordinates alone would make
## armies vanish as they crossed the seam — the recurring torus tax D-008
## warns about, and the reason criterion 5 of D-044 asks for a test
## specifically about a squad across the seam.
##
## ## Why the split between this file and the caller
##
## `nearest_offset` is pure and static, so the wrap-aware half — the half
## with the interesting failure mode — is testable headless without a
## Camera3D or a rendering server (D-014 keeps the real client
## untestable). Whether a point is on screen is thin engine glue by
## comparison, and lives with the caller.


## Which of the torus's lattice copies of `centre` sits closest to
## `reference` (in practice, what the camera is looking at).
##
## Returns the offset to ADD to a canonical world position, so the caller
## can place the squad's node there.
##
## Correct only while ONE lattice copy is on screen, which is what
## `max_camera_height` now enforces. See `visible_offset` for the
## belt-and-braces version.
##
## Worth recording how this was diagnosed, because the first answer was
## wrong. "Half the screen will not render units" was reported from a real
## game and read as a culling bug. Scanning every cell against both
## strategies said otherwise:
##
##     target (64,32): wrongly_culled=0  misplaced=529
##     target (2,32):  wrongly_culled=0  misplaced=1218
##
## Nearest-only almost never culls something visible — it picks a
## DIFFERENT visible copy. And the real fault was upstream of both: terrain
## is drawn nine times and each entity once, so a view spanning two terrain
## copies leaves one of them bare. No choice of offset fixes that; only
## keeping the second copy off screen does.
static func nearest_offset(offsets: Array[Vector3], centre: Vector3,
		reference: Vector3) -> Vector3:
	var best := Vector3.ZERO
	var best_distance := INF
	for offset in offsets:
		var d := (centre + offset).distance_squared_to(reference)
		if d < best_distance:
			best_distance = d
			best = offset
	return best


## The offset at which `centre` is actually ON SCREEN, or `null` if no
## copy of it is — which is the real culling question.
##
## Tests every lattice copy rather than only the nearest, because "nearest
## to what the camera looks at" and "the one you can see" are different
## questions whenever more than one copy is in view, and on a torus that
## is shallower than it is wide they routinely are (see nearest_offset).
##
## `offsets` puts the centre copy first (TorusSpace.lattice_offsets), and
## this returns on the first hit, so an unwrapped squad — the common case
## — costs one test. A squad that is genuinely off screen pays for all
## nine, and that is the right trade: nine projections is far less than
## deriving forty soldiers, which is exactly the work culling exists to
## avoid (D-045).
static func visible_offset(camera: Camera3D, offsets: Array[Vector3],
		centre: Vector3, margin: float, size: Vector2):
	for offset in offsets:
		if is_on_screen(camera, centre + offset, margin, size):
			return offset
	return null


## `visible_offset` for something with real EXTENT, where a miss means
## DRAW NOWHERE.
##
## Two things separate it from the point version, and both were bought by
## the same playtest report three times over (squads vanishing before they
## finished leaving the viewport; a click missing a forty-man line;
## whole blocks of forest snapping in and out):
##
## 1. **The margin grows by the thing's own projected radius.** A flat
##    pixel margin is a statement about a POINT, and everything this is
##    asked about — a formation, a 16x16-cell forest chunk — is metres
##    across. Tested at its centre alone, the whole thing disappears the
##    instant that one point crosses the margin, while the half of it the
##    player can plainly still see goes with it.
## 2. **`null` means hidden, not "put it somewhere else".** The caller
##    must hide it. Falling through to `nearest_offset` answers a
##    DIFFERENT question — nearest to the look-at point, not on screen —
##    and when the two rules disagree the thing jumps a whole map period
##    in one frame. That reads as snapping, which is worse than the
##    honest disappearance it was standing in for.
##
## The margin is worked out PER COPY, not once from the nearest one: it
## falls off as 1/depth, so a margin borrowed from a copy near the camera
## is enormous by the time it is applied to one near the horizon, and on
## a shallow torus that pulls in a copy the player cannot see. The
## projection lookup is hoisted out of the loop instead — the same
## treatment `is_on_screen`'s viewport size already gets, for the same
## reason.
static func visible_offset_of_extent(camera: Camera3D, offsets: Array[Vector3],
		centre: Vector3, world_radius: float, margin: float, size: Vector2):
	var scale := extent_scale(camera, world_radius, size)
	# Every camera read the loop needs, taken once. `global_transform` is
	# a property fetch per access, and the loop runs nine times per
	# entity per frame — the same hoist `get_camera_projection()` gets
	# just above and `is_on_screen`'s `size` gets from its caller.
	var eye := Vector3.ZERO
	var forward := Vector3.ZERO
	var near := 0.0
	if camera != null:
		var view := camera.global_transform
		eye = view.origin
		forward = -view.basis.z
		near = camera.near
	for offset in offsets:
		var at := centre + offset
		if is_on_screen(camera, at,
				margin_at_depth(at, scale, margin, eye, forward, near), size):
			return offset
	return null


## Pixels of on-screen radius PER UNIT OF DEPTH for something of world
## radius `world_radius` — everything in the projected size that does not
## depend on where the thing is, so a caller testing nine lattice copies
## pays for it once.
##
## `proj.y.y` is `1 / tan(fov / 2)`, and the x column carries the same
## value divided by the aspect ratio that the viewport's width multiplies
## straight back in — so a radius, which is isotropic, needs only one of
## them.
static func extent_scale(camera: Camera3D, world_radius: float, size: Vector2) -> float:
	if camera == null or world_radius <= 0.0:
		return 0.0
	return world_radius * camera.get_camera_projection().y.y * size.y * 0.5


## `margin` grown by the on-screen radius `scale` implies at `centre`.
##
## From the projection and the DEPTH along the view axis, not by
## projecting an edge point and measuring the gap. Projecting an edge
## sounds more direct and is the version that was written first; it is
## wrong in two ways that only show up at the screen edge, which is the
## one place this number is ever consulted:
##
## - it depends on which axis the edge was taken along, and the camera
##   turns (D-063), so the same chunk was two different widths depending
##   on which way the player happened to be facing; and
## - an edge taken TOWARD the camera moves the point up the perspective
##   curve, so a chunk 24 units across sitting 23 units from the camera
##   projected a margin of 132 pixels on a 64-pixel viewport — two
##   screens of slack. A margin wider than the screen culls nothing at
##   all, which is D-045's whole saving quietly undone.
##
## Anything at or behind the near plane gets the ungrown margin. There is
## no meaningful on-screen size there, and `is_on_screen` is already the
## one deciding whether such a thing is drawn.
## Reads the camera and hands off to `margin_at_depth`, which is the one
## definition of the arithmetic — the nine-copy loop above calls that one
## directly with the camera read hoisted out of it.
static func extent_margin(camera: Camera3D, centre: Vector3, scale: float,
		margin: float) -> float:
	if camera == null:
		return margin
	var view := camera.global_transform
	return margin_at_depth(centre, scale, margin, view.origin, -view.basis.z,
		camera.near)


## The same margin from view parameters already in hand, so a caller
## testing every lattice copy does not re-read the camera nine times.
static func margin_at_depth(centre: Vector3, scale: float, margin: float,
		eye: Vector3, forward: Vector3, near: float) -> float:
	if scale <= 0.0:
		return margin
	var depth := forward.dot(centre - eye)
	if depth <= near:
		return margin
	return margin + scale / depth


## Where a block of cells actually SITS, as a world position: the middle
## of the cells the block owns.
##
## The obvious version — `space.to_world(key * cells_per_side +
## cells_per_side / 2)` — is what this replaces, and it is wrong twice on
## any map whose size is not a whole number of blocks:
##
## - **`to_world` normalizes its argument**, and that nominal centre can
##   be off the map. On the shipped 84-wide default with 16-cell blocks
##   the last column owns cells 80-83 and takes centre 88, which wraps to
##   q = 4 — measured, one whole x period, 145.49 world units from the
##   trees it is supposed to stand for. Anything culled on that centre is
##   then DRAWN a map away from its own contents, because the offset that
##   puts the centre on screen is applied to the contents. That is the
##   defect `visible_offset_of_extent` exists to fix, one level up, and it
##   is why this cannot stay in the caller: the centre became
##   load-bearing for visibility the moment culling started reading it.
## - **An edge block owns fewer cells than a full one** — four, not
##   sixteen, in that same column — so a centre taken from the nominal
##   block sits outside the cells it represents. There, 6.5 cells or
##   ~11.3 world units outside, which spends nearly half of
##   `block_radius` on the side away from every tree.
##
## Both go away by measuring the cells the block really has, in
## CONTINUOUS axial space. `axial_offset_to_world` is the linear map
## without the wrap, so this agrees with `to_world` exactly whenever the
## centre is in range and stays in the same lattice copy as its contents
## when it is not.
##
## `maps/ladder.tres` (42 x 48) happens to escape the wrap — 42/16 leaves
## its last block centred at 40, still on the map — so anything testing
## this has to use the default map.
static func block_centre(space: TorusSpace, key: Vector2i,
		cells_per_side: int) -> Vector3:
	var lo := Vector2(float(key.x * cells_per_side), float(key.y * cells_per_side))
	var hi := Vector2(
		float(mini((key.x + 1) * cells_per_side, space.width) - 1),
		float(mini((key.y + 1) * cells_per_side, space.height) - 1))
	return space.axial_offset_to_world((lo + hi) * 0.5)


## How far a square block of `cells_per_side` cells reaches from its own
## centre, in world units — the radius `visible_offset_of_extent` wants
## for a chunked thing like the forest MultiMeshes.
##
## An upper bound, and deliberately so: a block at the map's edge owns
## fewer cells than a full one and reaches less far, but a radius too
## large only costs a chunk of forest derived slightly off screen, while
## one too small is the snapping this whole path exists to stop.
##
## Derived from the hex geometry rather than written down, and it is not
## the half-diagonal of a rectangle: axial rows shear (`to_world` adds
## half a column per row), so the two corners running WITH the shear reach
## `1.5 * cells_per_side` hex widths while the two running against it
## reach a third of that. A 16-cell chunk at `hex_size` 1.0 is 24 world
## units, against the ~18 a rectangle would suggest — and understating it
## is the whole defect this exists to stop.
##
## Lives here rather than in client.gd for the same reason the rest of
## this file does: the client needs a GPU (D-014), and a radius derived
## correctly twice eventually drifts.
static func block_radius(space: TorusSpace, cells_per_side: int) -> float:
	var half := float(cells_per_side) / 2.0
	var radius := 0.0
	for corner in [Vector2(-half, -half), Vector2(-half, half),
			Vector2(half, -half), Vector2(half, half)]:
		radius = maxf(radius, space.axial_offset_to_world(corner).length())
	return radius


## How far the camera may zoom out before a SECOND terrain copy enters
## the view — the actual fix for "half the screen will not render units".
##
## Terrain is drawn nine times (D-035) but every squad, building and
## resource node is drawn ONCE. So the moment the view spans a second
## copy, that copy is bare ground: real terrain, no units on it. It is not
## a culling bug and no choice of lattice offset addresses it.
##
## Derived from the SHALLOWER of the two lattice periods. The previous
## version used a quarter of the map's WIDTH, and the binding dimension is
## depth: a 128x64 map sounds like 2:1 and in world units is 221 x 96,
## because a hex row is 1.5 deep and a column SQRT_3 (~1.73) wide.
##
## The 0.33 is measured, not chosen. On 128x64 at 1280x720 the forward
## ground reach is ~1.9x camera height, and the camera sits 0.6h behind
## what it looks at, so the on-screen z span is ~2.6h. The old cap of 55
## showed 106 units of a 96-unit period.
##
## The cost is real and worth stating: max zoom-out on the shipped map
## drops from ~55 to ~31. Buying it back means drawing entities at every
## visible copy — up to nine times the per-entity work D-045 exists to
## cut — or making maps less oblong, since height * 1.5 = width * SQRT_3
## needs height ~ 1.155 * width and the shipped map is half that.
##
## Lives here rather than in client.gd so it can be tested at all: the
## client needs a GPU and cannot be (D-014).
static func max_camera_height(space: TorusSpace, floor_height: float,
		ceiling_height: float) -> float:
	var x_period := float(space.width) * space.hex_size * TorusSpace.SQRT_3
	var z_period := float(space.height) * 1.5 * space.hex_size
	return clampf(minf(x_period, z_period) * 0.33, floor_height, ceiling_height)


## Whether `point` is on screen, with `margin` extra pixels of slack.
##
## Screen space rather than frustum planes on purpose. `Camera3D.get_frustum()`
## returns planes whose normal orientation is easy to get backwards, and
## the two mistakes it produces — cull everything, or cull nothing — both
## look like "the culling does not work" while being opposite bugs.
## Projection is unambiguous.
##
## The margin exists because this tests a squad's CENTRE while a squad has
## real extent: a formation whose centre is just off screen may still have
## soldiers on it. Being generous here costs a little wasted derivation
## and avoids soldiers popping at the screen edge, which is the failure
## nobody would tolerate.
## `size` is the viewport's size, passed in rather than fetched here.
## This runs once per squad per frame, and `get_viewport().get_visible_rect()`
## is two engine round-trips that return the same answer every time — at
## D-018's full scale that measured as a significant share of the frame
## once LOD had cut the per-soldier work it was hiding behind. Hoisting a
## loop invariant, the same mistake and the same fix as
## `Formation.soldier_transforms`.
static func is_on_screen(camera: Camera3D, point: Vector3, margin: float,
		size: Vector2) -> bool:
	if camera == null:
		return true
	if camera.is_position_behind(point):
		return false
	var screen := camera.unproject_position(point)
	return (screen.x >= -margin and screen.y >= -margin
		and screen.x <= size.x + margin and screen.y <= size.y + margin)
