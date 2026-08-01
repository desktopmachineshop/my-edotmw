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
## Testing only the nearest copy — rather than all nine — is sound
## because the client caps zoom so that less than one full copy of the map
## is ever on screen (`client.gd`'s `_camera_max_height`, D-035). If that
## cap is ever lifted far enough to show a whole copy plus part of
## another, this becomes wrong in a way that looks like squads popping at
## the far seam, and the fix is to test every offset rather than the
## nearest.
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
