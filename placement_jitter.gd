extends RefCounted
class_name PlacementJitter

## Deterministic, client-only cosmetic placement variation for freestanding
## buildings and resource nodes.
##
## Before this existed, every building sat dead-centre on its hex cell and
## faced one of exactly 6 directions (or, for a resource node, dead-centre
## with no rotation at all) — visually locking the whole map to graph paper
## even though nothing in the simulation actually requires that precision.
## `BuildingSim` only ever stores a `cell` (an index) and, where it's
## mechanically meaningful, a `facing` (D-076); nothing about screen-space
## position or a continuous yaw is simulation state, so varying them here
## touches no wire format and no hash.
##
## Same one-way structure as `cosmetic_offset.gd` (D-006 clause 2): pure
## functions of a stable id, read by the render path, never fed back into
## anything authoritative. All-static for the same reason — there is
## nowhere for per-object jitter state to live, so nothing can accumulate.
##
## EXCLUDED BY THE CALLER, never here: wall-family buildings
## (`footprint_radius == 0`) and access towers. Their cell position and
## `facing` are mechanically load-bearing — `client.gd`'s wall-joint
## geometry and door-facing marker are built assuming a segment sits exactly
## at its cell centre and faces exactly one of the 6 hex directions. See
## `_refresh_wall_joints`'s own `footprint_radius != 0 or is_access_tower`
## guard, which this mirrors.

## A stable pseudo-random value in [0, 1) from an integer seed and a salt.
## Not cryptographic — just enough decorrelation that neighbouring ids
## (typically sequential wire ids or nearby cell indices) don't produce
## visibly similar offsets. `hash()` is Godot's own well-mixed integer
## hash; the salt is folded in additively so the same id produces
## independent-looking values for position vs. rotation.
static func _rand01(id: int, salt: int) -> float:
	var h := hash(id * 2654435761 + salt)
	return float(h & 0xFFFFFF) / float(0xFFFFFF)


## A horizontal offset, uniform within a disk of `max_radius`, deterministic
## per `id`. Callers pick `max_radius` well inside the gap between adjacent
## cells so a jittered object still reads as standing on its own cell.
static func position_offset(id: int, max_radius: float) -> Vector3:
	if max_radius <= 0.0:
		return Vector3.ZERO
	var angle := _rand01(id, 1) * TAU
	# sqrt so the distribution is uniform over AREA, not biased toward the
	# centre the way a bare linear radius would be.
	var radius := sqrt(_rand01(id, 2)) * max_radius
	return Vector3(cos(angle) * radius, 0.0, sin(angle) * radius)


## A free yaw in [0, TAU), deterministic per `id` — replaces the 6-way
## hex-facing angle for anything whose facing carries no mechanical meaning.
## Used for resource nodes, which are never player-placed and so have no
## wire-replicated facing to read instead.
static func yaw(id: int) -> float:
	return _rand01(id, 3) * TAU


## Same distribution as `yaw()`, quantised to a single byte (0-255) — the
## default a freestanding building's placement ghost offers before the
## player touches the scroll-to-rotate control (see client.gd), and what
## gets sent as `facing` if they never do. `BuildingSim.add_building`
## stores a freestanding def's `facing` un-wrapped-mod-6 (unlike a wall or
## the access tower, whose facing must stay one of the 6 hex directions),
## so once sent this byte becomes ordinary replicated state — every client
## renders the SAME angle via `radians_of_byte`, not each its own guess.
static func yaw_byte(id: int) -> int:
	return int(_rand01(id, 3) * 256.0) & 0xFF


## Decode a wire-encoded facing byte (0-255) back to radians. The inverse
## half of `yaw_byte`, but also the only thing that needs to understand the
## encoding once a building's facing is real replicated state rather than a
## purely local guess.
static func radians_of_byte(byte: int) -> float:
	return (float(posmod(byte, 256)) / 256.0) * TAU


## Radians -> the wire's facing byte. The other inverse: a dragged wall run
## (D-096) has a real angle and needs to say so in the one byte `facing`
## has always been. 256 steps is ~1.4 degrees, far finer than a player can
## aim and far coarser than anything that would make a wall look kinked.
static func byte_of_radians(angle: float) -> int:
	return int(round(angle / TAU * 256.0)) & 0xFF
