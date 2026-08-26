extends Resource
class_name TerrainPreset

## A named starting point for terrain generation, as data (D-049).
##
## New map flavours are added as .tres files under /terrain/, never as a
## branch in the generator — the same rule civs follow (D-047), and for
## the same reason: "islands" and "highlands" are settings, not code.
##
## A preset FILLS the lobby's parameter set; it is not consulted again
## afterwards. Once the admin has picked one and nudged the sliders, what
## travels to the client is the concrete numbers, so the client never has
## to know what "islands" means — only what sea level to use. That keeps
## the two sides incapable of disagreeing about the world for any reason
## other than a number being wrong, which is the failure mode server.gd
## warned about when it noted that tunable terrain has to travel on the
## wire.

@export var id: StringName
@export var display_name: String = ""
@export_multiline var summary: String = ""

## How much of the map is under water. The single biggest lever on what a
## map FEELS like: raise it and the continents break into islands.
@export var sea_level: float = 0.38
@export var beach_level: float = 0.44

## Where rock starts. Lower it and the map turns mountainous, because
## more of the elevation range lands above the threshold.
@export var mountain_level: float = 0.74

## Feature size. Higher means smaller landmasses; lower means broader
## ones. A DENSITY, not a count (D-105): it is calibrated against
## `TerrainGen.REFERENCE_WIDTH` and scaled by the map's own width, so a
## preset means the same kind of country at every map size and a bigger
## map holds proportionally more of it.
@export var elevation_frequency: float = 2.5
@export var moisture_frequency: float = 4.0

## Vertical exaggeration — and since
## D-20260826-passable-means-flat-enough-to-cross, a SIMULATION input:
## passability blocks ground drawn steeper than `TerrainGen.max_slope`
## world units per hex, and this is the number that decides how steep the
## ground is drawn. A preset near 1.0 is open country wall to wall,
## because that is what it looks like.
@export var height_scale: float = 2.0


func validate() -> String:
	if id == &"":
		return "terrain preset has no id"
	if sea_level >= mountain_level:
		return "preset %s has sea_level >= mountain_level, which breaks the biome ladder" % id
	if beach_level < sea_level or beach_level > mountain_level:
		return "preset %s has beach_level outside the range between sea and mountain" % id
	if elevation_frequency <= 0.0 or moisture_frequency <= 0.0:
		return "preset %s has a non-positive noise frequency" % id
	return ""


func is_valid() -> bool:
	return validate() == ""
