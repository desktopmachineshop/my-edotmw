extends RefCounted
class_name MapSettings

## The world the lobby is about to generate (D-049).
##
## Everything here is chosen BEFORE the map exists. That is the whole
## point and the reason terrain generation moved to match start: the
## client used to build terrain when it connected, which was before
## anybody had picked a size, a seed or a shape. There was nothing wrong
## with the terrain it drew except that it was answering a question
## nobody had asked yet.
##
## ## Concrete numbers travel, not preset names
##
## A preset FILLS these values in the lobby; only the values are sent.
## The client therefore never has to know what "islands" means — it is
## handed a sea level. `server.gd` predicted this exact requirement back
## in M3: "the moment terrain parameters become tunable they have to
## become map data and travel on the wire, or the two sides will quietly
## disagree about which cells a squad may enter". Sending the preset id
## instead would leave two implementations of that meaning, one per side,
## free to drift.

## Torus dimensions. Height must stay even (D-008's row parity), which
## `sizes()` guarantees and `validate()` rechecks.
var width: int = 168
var height: int = 194

## How many starting positions the map offers (D-039).
var player_slots: int = 8

## The seed used when nobody has rolled or pinned one.
const DEFAULT_SEED := 1337

## The largest seed a roll may produce. Also the lobby spinner's ceiling
## (`client.gd`'s MAP_OPTIONS reads it from here), so a rolled seed is
## always a number the admin can read off the screen and type back in —
## a roll the UI could not represent would be unpinnable.
const SEED_MAX := 999_999

## Terrain noise seed. Rolled per match unless someone pins it, so two
## matches on the same settings are still different places (D-100) — the
## rolling is `roll_seed`, and the server does it when a LOBBY opens.
##
## The default is what every seedless headless flow runs on: bots, GUT
## tests, scenarios and `run-server` without `--seed`. Those want one
## reproducible world, not a surprise, so nothing rolls for them.
var seed: int = DEFAULT_SEED

## Whether somebody CHOSE this seed — `--seed` on the command line, or the
## admin typing one into the lobby. A pinned seed survives the re-roll a
## new lobby would otherwise do, which is what makes "copy the number
## down, play that map again" work (D-100).
##
## Deliberately not on the wire: it is lobby bookkeeping, and a client has
## no use for it. `MapSettings.to_dict` is the packet payload, so anything
## added there would have to be encoded or silently dropped.
var seed_pinned: bool = false

## Which preset was last applied. Carried for DISPLAY only — the numbers
## below are the authority, and a slider nudge leaves this pointing at
## the preset it started from.
var preset: StringName = &"continents"

## What the spawn sampler needs that terrain does not give it (D-104).
##
## These start life in the map file (`MapConfig`) and travel with the rest
## of the settings for the reason at the top of this file: the lobby's map
## preview draws where players will start, and it can only draw the
## SERVER's answer if it is handed the server's inputs. It was not, and
## every marker on the preview was fiction — the preview seeded the
## sampler with the match seed alone while the server seeded it with the
## map's base plus the match seed, so the two agreed about the algorithm
## and disagreed about every point it produced.
var spawn_seed: int = 20260801
var min_spawn_spacing: int = 12
var min_spawn_landmass: int = 96

var sea_level: float = 0.38
var beach_level: float = 0.44
var mountain_level: float = 0.74
var elevation_frequency: float = 2.5
var moisture_frequency: float = 4.0
var height_scale: float = 15.0


## The map sizes the lobby offers. Every height is even (D-008), and every
## size is roughly SQUARE IN WORLD UNITS, which is not the same as square
## in cells.
##
## A hex column is `SQRT_3` (~1.732) wide and a hex row is 1.5 deep, so a
## W x H cell grid measures `W * 1.732` by `H * 1.5`. The sizes were once
## all 2:1 in cells, which is 2.31:1 on the ground — and the shallow axis
## bounds how far the camera may zoom before the same ground appears
## twice (`RenderCull.max_camera_height`). Hence `height ~ width * 1.155`.
##
## ## Why the whole ladder moved up a rung (2026-08-17)
##
## The zoom cap is `period / 5.90` — you may zoom out until you can see
## exactly ONE whole world, and no further, because terrain is drawn nine
## times and every entity once. That is a fixed FRACTION of the map, so a
## small map is one you can take in at a glance: at 42 x 48 the cap is
## 12.3 and the entire world is on screen at it. Fog and scouting are
## most of this game's information model (D-004/D-025), and a world you
## can see all of at once has neither. D-056 wants matches an order of
## magnitude longer than today's ~200 s, and marching distance is the
## cheapest honest lever on that.
##
## So the floor rose to what was Standard, and the default to what was
## Huge. Cell counts now run 8,064 to 130,368; M4 measured worst tick flat
## in map size from 2,048 to 32,768 once field building was amortised
## (D-040), so the top two entries are extrapolation, not measurement —
## `field_cells_per_tick` is budgeted per TICK, so a bigger map costs
## pathing LATENCY rather than a spike (D-040), which is the trade that
## makes them tolerable at all.
##
##   Skirmish  84 x 96  =   8,064 cells   (was 42 x 48   =  2,016)
##   Standard 168 x 194 =  32,592 cells   (was 84 x 96   =  8,064)
##   Large    252 x 290 =  73,080 cells   (was 126 x 146 = 18,396)
##   Huge     336 x 388 = 130,368 cells   (was 168 x 194 = 32,592)
##
## `maps/ladder.tres` deliberately stays at 42 x 48 and is NOT in this
## list: `just ai-ladder` picks it precisely because four spawns close
## together let AI meet inside a match, and first contact there is already
## ~326 s against a 600 s cap.
static func sizes() -> Array:
	return [
		{"width": 84, "height": 96, "name": "Skirmish"},
		{"width": 168, "height": 194, "name": "Standard"},
		{"width": 252, "height": 290, "name": "Large"},
		{"width": 336, "height": 388, "name": "Huge"},
	]


## Roll a new world, and stop calling it pinned. Returns the new seed.
##
## The ONE non-deterministic line in this project's map pipeline, and it
## is deliberately here rather than anywhere a match reads from: a seed is
## drawn once, before the world exists, and everything downstream — the
## terrain, the spawn points, the combat RNG, the civ draw — is a pure
## function of it (D-100). A replay reproduces the match because the
## rolled number travelled on the wire and was written down, not because
## the roll itself was reproducible.
##
## Its own RandomNumberGenerator rather than the global `randi()`, because
## the global one is shared state a test could have seeded for something
## else, and "the map is the same every time" is exactly the bug this
## exists to fix.
func roll_seed() -> int:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	seed = rng.randi_range(0, SEED_MAX)
	seed_pinned = false
	return seed


## Choose a seed on purpose — `--seed`, or the lobby's spinner.
##
## Brought into the range a roll can produce and the spinner can show, for
## the reason SEED_MAX gives: a value the lobby cannot display is one
## nobody can copy down and play again. Normalised HERE rather than in the
## UI because a spinner is a suggestion from an untrusted client (D-002).
##
## WRAPPED rather than clamped, unlike every other setting here. A sea
## level is a magnitude and clamps sensibly; a seed is an IDENTIFIER, and
## clamping identifiers collapses every out-of-range value onto one map —
## `--seed=2000000` and `--seed=3000000` would silently be the same place
## instead of two that merely share a remainder.
func pin_seed(value: int) -> void:
	seed = posmod(value, SEED_MAX + 1)
	seed_pinned = true


func apply_preset(preset_def: TerrainPreset) -> void:
	if preset_def == null:
		return
	preset = preset_def.id
	sea_level = preset_def.sea_level
	beach_level = preset_def.beach_level
	mountain_level = preset_def.mountain_level
	elevation_frequency = preset_def.elevation_frequency
	moisture_frequency = preset_def.moisture_frequency
	height_scale = preset_def.height_scale


## Build the generator these settings describe.
##
## The ONE place a MapSettings becomes a TerrainGen, used by both sides.
## Two conversions would be two chances to forget a field, and forgetting
## one means the server routes squads around water the client never drew.
func to_terrain() -> TerrainGen:
	var terrain := TerrainGen.new()
	terrain.noise_seed = seed
	terrain.sea_level = sea_level
	terrain.beach_level = beach_level
	terrain.mountain_level = mountain_level
	terrain.elevation_frequency = elevation_frequency
	terrain.moisture_frequency = moisture_frequency
	terrain.height_scale = height_scale
	return terrain


func to_space() -> TorusSpace:
	return TorusSpace.new(width, height, 1.0)


## The settings a map file opens the lobby with (D-049).
##
## Here rather than in `server.gd` so that everything the spawn sampler
## reads makes ONE trip — map file to settings to sampler (D-104). A
## caller copying four of the six fields by hand is how the lobby preview
## came to sample by rules the server was not using.
static func from_map(config: MapConfig) -> MapSettings:
	var out := MapSettings.new()
	out.width = config.width
	out.height = config.height
	out.player_slots = config.player_slots
	out.spawn_seed = config.spawn_seed
	out.min_spawn_spacing = config.min_spawn_spacing
	out.min_spawn_landmass = config.min_spawn_landmass
	return out


## Build the spawn sampler these settings describe.
##
## The ONE place a MapSettings becomes a spawn-sampling MapConfig, for the
## same reason `to_terrain` is the one place it becomes a TerrainGen: two
## conversions are two chances to forget a field. Sharing
## `MapConfig.spawn_points` was never enough — the server and the lobby
## preview both called it and fed it different inputs, which is a shared
## implementation with unshared arguments and produces two different
## answers with a comment above each claiming they are the same one
## (D-104).
##
## The seed is the map's base PLUS the match seed, so re-rolling the seed
## in the lobby moves the starts as well as the ground. Deterministic, and
## replays depend on it (D-016).
func to_spawn_config() -> MapConfig:
	var out := MapConfig.new()
	out.width = width
	out.height = height
	out.player_slots = player_slots
	out.min_spawn_spacing = min_spawn_spacing
	out.min_spawn_landmass = min_spawn_landmass
	out.spawn_seed = spawn_seed + seed
	return out


func to_dict() -> Dictionary:
	return {
		"width": width, "height": height, "player_slots": player_slots,
		"seed": seed, "preset": String(preset),
		"spawn_seed": spawn_seed,
		"min_spawn_spacing": min_spawn_spacing,
		"min_spawn_landmass": min_spawn_landmass,
		"sea_level": sea_level, "beach_level": beach_level,
		"mountain_level": mountain_level,
		"elevation_frequency": elevation_frequency,
		"moisture_frequency": moisture_frequency,
		"height_scale": height_scale,
	}


static func from_dict(data: Dictionary) -> MapSettings:
	var out := MapSettings.new()
	out.width = int(data.get("width", out.width))
	out.height = int(data.get("height", out.height))
	out.player_slots = int(data.get("player_slots", out.player_slots))
	out.seed = int(data.get("seed", out.seed))
	out.preset = StringName(data.get("preset", out.preset))
	out.spawn_seed = int(data.get("spawn_seed", out.spawn_seed))
	out.min_spawn_spacing = int(data.get("min_spawn_spacing", out.min_spawn_spacing))
	out.min_spawn_landmass = int(data.get("min_spawn_landmass", out.min_spawn_landmass))
	out.sea_level = float(data.get("sea_level", out.sea_level))
	out.beach_level = float(data.get("beach_level", out.beach_level))
	out.mountain_level = float(data.get("mountain_level", out.mountain_level))
	out.elevation_frequency = float(data.get("elevation_frequency", out.elevation_frequency))
	out.moisture_frequency = float(data.get("moisture_frequency", out.moisture_frequency))
	out.height_scale = float(data.get("height_scale", out.height_scale))
	return out


## Returns "" if these settings describe a playable world.
##
## Checked on the SERVER when the admin starts, not only in the UI: a
## slider is a suggestion from an untrusted client (D-002), and a sea
## level above the mountain level would produce a map with no passable
## ground at all — every squad stranded, every flow field empty.
func validate() -> String:
	var space_error := to_space().validate()
	if space_error != "":
		return space_error
	if player_slots < 2:
		return "a match needs at least two starting positions"
	if sea_level >= mountain_level:
		return "sea level is at or above the mountain line, leaving nowhere to walk"
	if beach_level < sea_level or beach_level > mountain_level:
		return "the beach line must sit between sea and mountain"
	if elevation_frequency <= 0.0 or moisture_frequency <= 0.0:
		return "noise frequency must be positive"
	return ""


func is_valid() -> bool:
	return validate() == ""
