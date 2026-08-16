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
var width: int = 84
var height: int = 96

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
## matches on the same settings are still different places (D-099) — the
## rolling is `roll_seed`, and the server does it when a LOBBY opens.
##
## The default is what every seedless headless flow runs on: bots, GUT
## tests, scenarios and `run-server` without `--seed`. Those want one
## reproducible world, not a surprise, so nothing rolls for them.
var seed: int = DEFAULT_SEED

## Whether somebody CHOSE this seed — `--seed` on the command line, or the
## admin typing one into the lobby. A pinned seed survives the re-roll a
## new lobby would otherwise do, which is what makes "copy the number
## down, play that map again" work (D-099).
##
## Deliberately not on the wire: it is lobby bookkeeping, and a client has
## no use for it. `MapSettings.to_dict` is the packet payload, so anything
## added there would have to be encoded or silently dropped.
var seed_pinned: bool = false

## Which preset was last applied. Carried for DISPLAY only — the numbers
## below are the authority, and a slider nudge leaves this pointing at
## the preset it started from.
var preset: StringName = &"continents"

var sea_level: float = 0.38
var beach_level: float = 0.44
var mountain_level: float = 0.74
var elevation_frequency: float = 2.5
var moisture_frequency: float = 4.0
var height_scale: float = 15.0


## The map sizes the lobby offers. Every height is even (D-008), and the
## cell counts span the range M4 measured: 2,048 through 32,768, where
## the worst tick stayed flat once field building was amortised (D-040).
## Every size is roughly SQUARE IN WORLD UNITS, which is not the same as
## square in cells.
##
## A hex column is `SQRT_3` (~1.732) wide and a hex row is 1.5 deep, so a
## W x H cell grid measures `W * 1.732` by `H * 1.5`. These were all 2:1
## in cells, which is 2.31:1 on the ground — and the shallow axis is what
## bounds how far the camera may zoom before a second terrain copy enters
## view (RenderCull.max_camera_height). On the old Standard map that
## capped zoom at 31 against a possible 47.
##
## So `height ~ width * 1.155`. Heights stay EVEN for D-008's row parity,
## and cell counts are close to what they replaced so spawn density,
## match pacing and the D-038/D-043 performance figures stay comparable.
##
##   Skirmish  42 x 48  =  2,016 cells   (was 64 x 32  =  2,048)
##   Standard  84 x 96  =  8,064 cells   (was 128 x 64 =  8,192)
##   Large    126 x 146 = 18,396 cells   (was 192 x 96 = 18,432)
##   Huge     168 x 194 = 32,592 cells   (was 256 x 128 = 32,768)
static func sizes() -> Array:
	return [
		{"width": 42, "height": 48, "name": "Skirmish"},
		{"width": 84, "height": 96, "name": "Standard"},
		{"width": 126, "height": 146, "name": "Large"},
		{"width": 168, "height": 194, "name": "Huge"},
	]


## Roll a new world, and stop calling it pinned. Returns the new seed.
##
## The ONE non-deterministic line in this project's map pipeline, and it
## is deliberately here rather than anywhere a match reads from: a seed is
## drawn once, before the world exists, and everything downstream — the
## terrain, the spawn points, the combat RNG, the civ draw — is a pure
## function of it (D-099). A replay reproduces the match because the
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


func to_dict() -> Dictionary:
	return {
		"width": width, "height": height, "player_slots": player_slots,
		"seed": seed, "preset": String(preset),
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
