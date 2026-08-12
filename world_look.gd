extends RefCounted
class_name WorldLook

## The one definition of the client's lighting rig (D-080).
##
## Before this file, `client.gd`, `bench_render.gd` and `model_preview.gd`
## each built their own `DirectionalLight3D` and `Environment` inline —
## `bench_render.gd` an exact copy of `client.gd`'s, `model_preview.gd` a
## deliberate near-copy (a neutral studio backdrop rather than a
## battlefield). Three copies is how they drift: the one place a shadow or
## a sky gets turned on is easy to forget the other two exist.
##
## `bench_render.gd` already carries the reason this had to be one
## definition rather than three kept in sync by hand — "a benchmark camera
## that is merely similar measures a similar game." The same is true of
## the light: adding shadows to the shipping rig without also changing
## what the benchmark renders would make `bench-render` measure a game
## that does not exist.
##
## All-static, no instance state — the same convention as
## `render_cull.gd`, `formation.gd` and `hud_layout.gd`, and for the same
## reason: there is nowhere here for a second copy of the rig to hide.
##
## `preview` selects `model_preview.gd`'s neutral studio look instead of
## the battlefield rig. It is the only caller-visible variation; every
## other caller gets byte-identical values.

const SUN_ROTATION_DEGREES := Vector3(-55.0, -35.0, 0.0)
const SUN_ENERGY := 1.1

const PREVIEW_SUN_ROTATION_DEGREES := Vector3(-52.0, -38.0, 0.0)
const PREVIEW_SUN_ENERGY := 1.15

## `model_preview.gd`'s neutral studio backdrop — unchanged since before
## D-080. A battlefield sky, fog and ACES response would shift every
## colour in the contact sheet and defeat the one thing that view is for:
## comparing archetypes' geometry and animation against each other.
const PREVIEW_BACKGROUND_COLOR := Color(0.16, 0.17, 0.20)
const PREVIEW_AMBIENT_COLOR := Color(0.45, 0.48, 0.55)
const PREVIEW_AMBIENT_ENERGY := 0.55

## Battlefield sky (D-080). Before this, `background_mode` was a flat
## `BG_COLOR` navy void — the horizon never existed. `ProceduralSkyMaterial`
## also supplies the sun disc automatically: `DirectionalLight3D` defaults
## to `sky_mode = LIGHT_AND_SKY`, so the sun this file already builds is
## what lights the sky without any extra wiring.
const SKY_TOP_COLOR := Color(0.25, 0.45, 0.72)
const SKY_HORIZON_COLOR := Color(0.66, 0.72, 0.78)
const SKY_GROUND_BOTTOM_COLOR := Color(0.16, 0.17, 0.20)
const SKY_GROUND_HORIZON_COLOR := Color(0.40, 0.42, 0.44)

## Ambient now samples the sky instead of a constant colour — this is the
## change that does most of the work, because flat-shaded low-poly
## geometry lit only by a single hard directional light plus a flat
## ambient term reads as cardboard. A sky-coloured ambient term gives the
## shadowed side of every soldier and hex a gradient instead of one flat
## fill, at no per-fragment cost.
const AMBIENT_ENERGY := 0.6

## No tonemap operator was set before D-080 (Godot's default is
## `TONE_MAPPER_LINEAR`, i.e. none), which is why the saturated biome
## colours read as plastic. ACES compresses highlights and desaturates
## slightly, which is exactly why the terrain and unit palettes get
## re-tuned in the step after this one, never before it — tuning colour
## against the old, tonemap-less response would have to be redone.
const TONEMAP_EXPOSURE := 1.1
const TONEMAP_WHITE := 1.0

## Depth fog. Aerial perspective is a strong depth cue at RTS zoom
## (camera height 8-31 on the shipped map, D-045's `max_camera_height`),
## and tying its colour to the sky horizon rather than a separate flat fog
## colour is what makes it read as haze rather than a grey wall.
##
## `fog_density` is tuned to stay unnoticeable across the play area and
## only assert itself near the render horizon: at 30 units (a common play
## distance) it blends in at ~16%; at 60 units (near `max_camera_height`'s
## forward reach) ~30%. `fog_height_density = 0.0` keeps this pure
## distance fog — the map has no elevation dramatic enough to key height
## fog off.
const FOG_COLOR := Color(0.62, 0.68, 0.74)
const FOG_DENSITY := 0.006
const FOG_AERIAL_PERSPECTIVE := 0.5
const FOG_SKY_AFFECT := 1.0


## A `DirectionalLight3D` ready to `add_child()`. Callers own the node —
## this only decides what it looks like.
static func make_sun(preview: bool = false) -> DirectionalLight3D:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = PREVIEW_SUN_ROTATION_DEGREES if preview else SUN_ROTATION_DEGREES
	sun.light_energy = PREVIEW_SUN_ENERGY if preview else SUN_ENERGY
	return sun


## An `Environment` resource ready to hang off a `WorldEnvironment` node.
## Callers own the node; this only decides what the environment looks
## like, so it stays testable without a scene tree.
##
## `preview` keeps `model_preview.gd`'s original flat, tonemap-less studio
## backdrop untouched; every other caller gets the sky/ambient/tonemap/fog
## battlefield rig.
static func make_environment(preview: bool = false) -> Environment:
	var env := Environment.new()

	if preview:
		env.background_mode = Environment.BG_COLOR
		env.background_color = PREVIEW_BACKGROUND_COLOR
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = PREVIEW_AMBIENT_COLOR
		env.ambient_light_energy = PREVIEW_AMBIENT_ENERGY
		return env

	env.background_mode = Environment.BG_SKY
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = SKY_TOP_COLOR
	sky_material.sky_horizon_color = SKY_HORIZON_COLOR
	sky_material.ground_bottom_color = SKY_GROUND_BOTTOM_COLOR
	sky_material.ground_horizon_color = SKY_GROUND_HORIZON_COLOR
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.sky = sky

	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = AMBIENT_ENERGY
	env.ambient_light_sky_contribution = 1.0

	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = TONEMAP_EXPOSURE
	env.tonemap_white = TONEMAP_WHITE

	env.fog_enabled = true
	env.fog_light_color = FOG_COLOR
	env.fog_density = FOG_DENSITY
	env.fog_aerial_perspective = FOG_AERIAL_PERSPECTIVE
	env.fog_sky_affect = FOG_SKY_AFFECT
	env.fog_height_density = 0.0

	return env
