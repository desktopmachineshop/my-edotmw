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
##
## In a lobby this is DERIVED, not chosen: `MatchState._seats_changed()`
## sets it to the seat count on every join and leave
## (D-20260817-starting-positions-follow-the-seats). This default is what
## the seedless headless flows start from before anybody is seated, and
## what a `.tres` MapConfig contributes; it is not a preference the lobby
## can express, and there is no setter for it on the wire.
var player_slots: int = 8

## The seed used when nobody has rolled or pinned one.
const DEFAULT_SEED := 1337

## The largest seed a roll may produce — six digits, so a seed stays a
## number a person can read out of a log or type after `--seed`.
##
## This used to double as the lobby spinner's ceiling, on the reasoning
## that a roll the UI could not represent would be unpinnable. There is no
## spinner any more (D-20260817-starting-positions-follow-the-seats): the
## number is a dev handle rather than a lobby control, and what the lobby
## offers instead is Reroll. The ceiling stays for the readability half of
## that argument, which did not depend on the UI.
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
var mountain_level: float = 0.74
var elevation_frequency: float = 2.5
var moisture_frequency: float = 4.0
var height_scale: float = 15.0

## How far above the waterline sand gives way to grass (#125).
##
## The BAND, not the level. A beach is a strip along the shore, and
## storing where its far edge happened to fall made it a free parameter
## that no control exposed and every other control had to work around:
## `validate` demanded `sea_level <= beach_level <= mountain_level`, so a
## preset's hidden beach line was the real ceiling of the sea-level
## slider — 0.27 on `plains`, against a slider drawn to 0.90, which put
## three quarters of that slider's travel outside the settings the server
## accepts. Nothing said so, because the value pinning it was one a player
## could not see.
##
## Storing the WIDTH leaves every shipped preset's beach exactly where it
## was (`apply_preset` takes the difference) and makes it FOLLOW the water
## when the slider moves, which is the one behaviour the word predicts.
var beach_band: float = 0.06

## Where sand gives way to grass. Derived, and clamped into the range the
## ordering above used to have to police.
##
## Biome only: passability is decided by sea and mountain alone
## (`TerrainGen.passability`), so this moves COLOURS and never moves where
## a squad may walk. That is what makes deriving it safe — the same split
## D-084 drew between the picture and the simulation.
var beach_level: float:
	get: return clampf(sea_level + beach_band, sea_level, mountain_level)


## The map-generation sliders, and how far each is drawn (#125).
##
## ONE definition, because there were three: a literal table of ranges in
## `client.gd`, a matching set of `clampf` calls in
## `MatchState.set_map_option`, and the coupled thresholds `validate`
## enforces below. Each was right on its own and the set of them was
## meaningless — the lobby offered travel the server refused, and nothing
## could fail until somebody moved a handle. The same shape as
## `UnitDef.damage` against `BuildingDef.damage` (D-066): two correct
## numbers, an incoherent pair.
const SLIDER_LIMITS := {
	"sea_level": Vector2(0.05, 0.9),
	"mountain_level": Vector2(0.1, 0.98),
	"elevation_frequency": Vector2(0.5, 8.0),
	# Ceiling raised from 6.0 to 20.0 alongside the 15.0 default (was
	# 2.0) — a slider that cannot reach the default clamps it back down on
	# the first nudge.
	"height_scale": Vector2(0.5, 20.0),
}

## The step every map slider moves in, and so the smallest gap the bounds
## below can leave between two handles on the same ordering.
const SLIDER_STEP := 0.01

## Cells sampled per axis by `walkable_fraction`. A fixed COUNT rather
## than a stride, so the estimate costs the same on an 8,064-cell map and
## a 130,368-cell one — D-106's rule, that a check which must not scale
## with the map is written so that it cannot.
const GROUND_SAMPLES_PER_AXIS := 32


## How far `key` may ACTUALLY travel, given what its neighbours are set to.
##
## Sea level and mountain line are two handles on one ordering, so each
## bounds the other and the ends MOVE — the coupling is visible in the
## control instead of being discovered when the server refuses. `validate`
## still checks the ordering, because a slider is a suggestion from an
## untrusted client (D-002); with these bounds applied on both sides, an
## honest one has no way to violate it.
func slider_bounds(key: String) -> Vector2:
	var limits: Vector2 = SLIDER_LIMITS.get(key, Vector2.ZERO)
	match key:
		"sea_level":
			return Vector2(limits.x, minf(limits.y, mountain_level - SLIDER_STEP))
		"mountain_level":
			return Vector2(maxf(limits.x, sea_level + SLIDER_STEP), limits.y)
	return limits


## Move one slider, clamped to the travel it actually has. Returns false
## for a key that is not a slider at all, so a caller can tell an unknown
## option from a refused one.
func set_slider(key: String, value: float) -> bool:
	if not SLIDER_LIMITS.has(key):
		return false
	var bounds := slider_bounds(key)
	var clamped := clampf(value, bounds.x, bounds.y)
	match key:
		"sea_level":
			sea_level = clamped
		"mountain_level":
			mountain_level = clamped
		"elevation_frequency":
			elevation_frequency = clamped
		"height_scale":
			height_scale = clamped
	return true


## Roughly what share of this world comes out walkable.
##
## Sampled on a sparse lattice rather than generated: `TerrainGen.
## passability` is O(cells) and this runs on every slider tick — ~130 ms
## on the shipped map against ~4 ms for the sample. Measured against the
## full generation on 16 worlds (4 presets x 4 sizes) it agrees to within
## 0.012, and to within 0.001 in the thin cases this exists to catch;
## `test_map_slider_ranges.gd` pins that against the real `passability`
## so the two cannot drift.
##
## An ESTIMATE, and only of QUANTITY: ground scattered as a thousand
## one-cell islets counts the same as one continent. That is enough for
## what `validate` asks of it — is there anywhere to stand at all — and
## deliberately not enough to answer whether this is a GOOD map, which is
## the player's call rather than the server's.
func walkable_fraction() -> float:
	var space := to_space()
	var terrain := to_terrain()
	var step_x := maxi(1, space.width / GROUND_SAMPLES_PER_AXIS)
	var step_y := maxi(1, space.height / GROUND_SAMPLES_PER_AXIS)
	var sampled := 0
	var walkable := 0
	var x := 0
	while x < space.width:
		var y := 0
		while y < space.height:
			# The same test `TerrainGen.passability` applies, which is why
			# the test named above compares this against it on a real map
			# rather than trusting two copies of a threshold to stay equal.
			var e := terrain.elevation_at(space, Vector2i(x, y))
			sampled += 1
			if e >= sea_level and e < mountain_level:
				walkable += 1
			y += step_y
		x += step_x
	return float(walkable) / float(maxi(sampled, 1))


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
	# The WIDTH of the preset's beach, so applying one leaves the beach
	# exactly where the preset put it and moving the water afterwards
	# takes it along (#125).
	beach_band = maxf(preset_def.beach_level - preset_def.sea_level, 0.0)
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
	out.mountain_level = float(data.get("mountain_level", out.mountain_level))
	# The wire still carries the absolute level, because concrete numbers
	# travel (see this file's header) and `to_terrain` wants one. The BAND
	# is what this side stores, so it is recovered here rather than
	# assigned — and a beach below the waterline, off a malformed packet,
	# comes back as no beach rather than as an invalid world.
	out.beach_band = maxf(
		float(data.get("beach_level", out.beach_level)) - out.sea_level, 0.0)
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
	# No beach check any more: `beach_level` is derived from the waterline
	# (#125) and clamped as it is read, so the ordering this used to police
	# cannot be violated. What it policed was a value only a preset could
	# set, and policing it pinned the sea-level slider to a hidden number.
	if elevation_frequency <= 0.0 or moisture_frequency <= 0.0:
		return "noise frequency must be positive"
	# Whether the world has any GROUND on it (#125). Everything above is
	# an ORDERING, and ordering three thresholds correctly is not the same
	# as leaving anywhere to stand: at sea level 0.85 every check above
	# passes and the shipped Standard map comes out 0.0% walkable with 0
	# of 8 starting positions. That combination is inside the sliders'
	# travel, so nothing but this refuses it.
	#
	# Two starts' worth of land, because two starting positions is what
	# this function already demands above — necessary rather than
	# sufficient (the land could be scattered as islets), and deliberately
	# not a judgement about whether the map is a GOOD one. A shortfall of
	# starts on a map that has ground is already tolerated: the server
	# warns and the players who are seated share what there is.
	#
	# Last, because it is the only check here that samples the world — the
	# same order D-104's three spawn tests run in, and for the same
	# reason: let the cheap answers be the answer whenever they can be.
	if walkable_fraction() * float(width * height) < 2.0 * float(min_spawn_landmass):
		return "most of the map falls outside the band between sea level and the mountain line, leaving almost nowhere to walk"
	return ""


func is_valid() -> bool:
	return validate() == ""
