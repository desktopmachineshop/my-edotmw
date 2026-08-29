extends RefCounted
class_name AudioCue

## Whether a thing that happened should be HEARD, and as what (#344).
##
## THE decision layer of the audio system, and the whole of the part with
## an interesting failure mode. All-static and pure, for the same
## structural reason `formation.gd`, `render_cull.gd` and
## `battle_line.gd` are: the client needs an audio device, and this does
## not — so the gating, throttling and loudness are testable headless
## while only the final `AudioStreamPlayer` needs hardware. Same split
## `render_cull.gd` makes against `client.gd`.
##
## ## It is COSMETIC, one-way, and the simulation does not know it exists
##
## D-006 clause 2: client-side cosmetics are one-way and never read back.
## Nothing here is sent anywhere, nothing here influences a curve, an
## order or a hash, and the server has no audio concept at all. A sound
## that changed an outcome would be a per-client divergence with no wire
## evidence — the worst shape of bug this project has a name for.
##
## ## Fog gating reuses the ONE vision query
##
## #344 is explicit: "a sound a player could not SEE the cause of must
## not play — reuse the vision query, do not invent a second". On the
## client that query is `TerrainFog.level_at()`, the same field the
## ground shader and the minimap read (D-106). This file takes the LEVEL
## as an argument rather than the fog object, which is what keeps it pure
## — and means a caller cannot accidentally hand it a different notion of
## visibility without saying so at the call site.
##
## EXPLORED is not enough. A player who once saw a hill does not hear the
## battle on it now; that is the difference between knowing and hearing,
## and it is the same distinction D-030 draws for buildings.
##
## Interface sounds are exempt by DATA (`SoundDef.fog_gated`), not by a
## branch here: a click has no cause on the map, and gating it on sight
## would silence the one category of sound that is unambiguously the
## player's own.

## Silence. Returned as an empty dictionary rather than null so callers
## can `if cue.is_empty()` without a null check on every path.
static func silence() -> Dictionary:
	return {}


## Resolve one event.
##
## `at_cell` is -1 for an event with no place — a UI click, a stinger.
## Such an event is never fog gated and never distance-attenuated, and
## passing it a cell it does not have would be inventing a location.
##
## `heard` is the caller's throttle ledger: `event -> {"last": float,
## "voices": int}`. Passed IN rather than remembered here, because this
## file holds no state — the director owns the ledger, and a test can
## hand in whatever history it wants to exercise.
static func resolve(def: SoundDef, at_cell: int, listener_cell: int,
		space: TorusSpace, fog_level: int, now: float,
		heard: Dictionary, magnitude: float = 1.0) -> Dictionary:
	if def == null or def.stream_path == "":
		return silence()

	# --- may the player hear it at all? ------------------------------
	if def.fog_gated:
		if at_cell < 0:
			# A world sound with no place cannot be checked against the
			# fog, so it is refused. Failing CLOSED is the only safe
			# direction: the alternative leaks that something happened
			# somewhere, which is precisely what fog exists to withhold.
			return silence()
		if fog_level != TerrainFog.VISIBLE:
			return silence()

	# --- is it near enough to be worth a voice? ----------------------
	var distance := 0
	if at_cell >= 0 and listener_cell >= 0 and space != null and def.audible_cells > 0:
		distance = space.distance(space.from_index(at_cell), space.from_index(listener_cell))
		if distance > def.audible_cells:
			return silence()

	# --- throttles ----------------------------------------------------
	var ledger: Dictionary = heard.get(def.event, {})
	var last := float(ledger.get("last", -1.0e9))
	if now - last < def.min_interval:
		# RATE. One exchange resolves as aggregate arithmetic over a
		# whole squad (D-024), so a single clash can produce a burst of
		# casualty events inside one tick. Unthrottled that is a click,
		# not a volley — and it is also thirty-six voices spent on one
		# event.
		return silence()
	if int(ledger.get("voices", 0)) >= def.max_voices:
		# VOICES. A different limit from the one above and needed
		# separately: twenty simultaneous engagements across a map are
		# not thirty-six casualties in one tick.
		return silence()

	# --- how loud ------------------------------------------------------
	#
	# Distance attenuation is computed HERE rather than left to the
	# engine's 3D falloff, because the fog gate above already means "you
	# can see it", and a sound that is audible-but-inaudibly-quiet is a
	# voice spent on nothing. One rule decides both.
	var falloff := 0.0
	if def.audible_cells > 0 and distance > 0:
		# Linear in distance, in DECIBELS — so it fades evenly to the
		# audible edge rather than dropping off a cliff near the
		# listener. -18 dB at the limit is quiet without being a cut.
		falloff = -18.0 * (float(distance) / float(def.audible_cells))

	# Magnitude is the event's own weight: a twenty-man volley is louder
	# than a three-man one. Clamped, because a single enormous event must
	# not be able to shout down everything else — and because `alive` can
	# be any number a roster invents.
	var weight := clampf(magnitude, 0.0, 1.0)
	var body := lerpf(-8.0, 0.0, weight)

	return {
		"event": def.event,
		"stream_path": def.stream_path,
		"volume_db": def.gain_db + falloff + body,
		"pitch_jitter": def.pitch_jitter,
		"cell": at_cell,
		"distance": distance,
	}


## Record that a cue was played, returning the updated ledger.
##
## Separate from `resolve` on purpose: resolving must not have side
## effects, or the same call could not be made twice with the same answer
## — which is the property the tests rest on. The caller decides when a
## voice actually started.
static func note_played(heard: Dictionary, event: StringName, now: float) -> Dictionary:
	var ledger: Dictionary = heard.get(event, {}).duplicate()
	ledger["last"] = now
	ledger["voices"] = int(ledger.get("voices", 0)) + 1
	heard[event] = ledger
	return heard


## Record that a voice finished. The director calls this when a player
## frees up; a test calls it to exercise the cap.
static func note_finished(heard: Dictionary, event: StringName) -> Dictionary:
	if not heard.has(event):
		return heard
	var ledger: Dictionary = heard[event].duplicate()
	ledger["voices"] = maxi(0, int(ledger.get("voices", 0)) - 1)
	heard[event] = ledger
	return heard


## How loud a volley of `fell` men out of a squad of `size` should be, in
## the 0..1 `magnitude` the resolver takes.
##
## Squad-level by construction (#344: "a volley is one sound, not 36"):
## the input is a COUNT, and there is nowhere in it for a per-soldier
## anything to live — the same reason `Formation` is all-static.
static func volley_magnitude(fell: int, size: int) -> float:
	if fell <= 0 or size <= 0:
		return 0.0
	# Square root rather than linear: loudness is perceptual, and a
	# six-man loss out of thirty should not be a fifth as loud as a wipe.
	return clampf(sqrt(float(fell) / float(size)), 0.0, 1.0)
