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
