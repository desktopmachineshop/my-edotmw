extends Resource
class_name MapConfig

## Map parameters as data, not constants (CLAUDE.md: everything that can
## be data-driven should be). Lives in /maps/*.tres so a map can be added
## or resized without touching a script.
##
## Kept deliberately small for M1: this is map *dimensions*, not terrain
## generation, which is out of M1's scope (D-022). Terrain-gen parameters
## join this resource when they land rather than getting their own file.

@export var id: StringName = &"default"
@export var display_name: String = ""

# Torus dimensions in hex cells. `height` must be even — see D-008's row
# parity, enforced by validate() and by the map test suite so a bad value
# fails the build rather than misaligning the seam at runtime.
@export var width: int = 64
@export var height: int = 32
@export var hex_size: float = 1.0

# How many squads each connecting player is given at spawn. M3's cut line
# is ~12-15 per player (D-015); full scale is ~50 (D-018).
@export var squads_per_player: int = 12


func to_space() -> TorusSpace:
	return TorusSpace.new(width, height, hex_size)


## Returns "" if valid, else the reason. Delegates the geometry rules to
## TorusSpace so there is one definition of a legal torus, not two.
func validate() -> String:
	var space_error := to_space().validate()
	if space_error != "":
		return space_error
	if squads_per_player <= 0:
		return "squads_per_player must be positive (got %d)" % squads_per_player
	return ""


func is_valid() -> bool:
	return validate() == ""
