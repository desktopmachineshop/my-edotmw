extends Node
class_name AudioDirector

## The only part of the audio system that needs a device (#344).
##
## Everything interesting — whether a sound may be heard, how loud, and
## whether it has been heard too recently — lives in `audio_cue.gd`,
## which is pure and tested headless. This file owns the buses, the voice
## pool and the ledger, and nothing else. Same split `client.gd` makes
## against `render_cull.gd`, and for the same reason: a rule that needs
## hardware to exercise is a rule nobody exercises.
##
## ## It is a one-way cosmetic (D-006 clause 2)
##
## Nothing here is read back by anything. No curve, no order, no hash and
## no packet depends on a sound having played, and the simulation has no
## audio concept at all — `tests/test_audio.gd` scans the sim files to
## keep that true. A sound that changed an outcome would be a per-client
## divergence with no wire evidence.
##
## ## Non-positional players, deliberately
##
## `AudioCue` already computes wrap-aware distance attenuation, because
## the fog gate and the audible-range cull are one decision and splitting
## them across two systems would put the torus tax in two places. So
## these are plain `AudioStreamPlayer`s carrying a resolved `volume_db`,
## not `AudioStreamPlayer3D`s with their own falloff — two attenuation
## curves multiplying each other is a thing nobody can tune.
##
## Stereo placement is a later pass and wants the camera basis; the
## foundations do not need it and inventing it now would bind this file
## to the camera.

const BUS_SFX := "SFX"
const BUS_UI := "UI"

## Enough voices for a busy engagement without letting audio become a
## frame-time question. Per-event caps in `SoundDef.max_voices` do the
## real limiting; this is the backstop across all events at once.
const VOICE_POOL := 24

const SETTINGS_PATH := "user://audio.cfg"

var _players: Array[AudioStreamPlayer] = []
## Which event each pool slot is currently voicing, so the ledger can be
## decremented when it finishes. -1/&"" means free.
var _voicing: Array[StringName] = []

## The throttle ledger `AudioCue` reads and never writes. Held HERE
## because it is state, and the resolver must have none.
var _heard := {}

var _streams := {}
var _enabled := true


func _ready() -> void:
	_ensure_buses()
	_build_pool()
	load_settings()


## Master -> SFX and UI, created at runtime rather than committed in
## `default_bus_layout.tres`, so a clone with no audio assets still boots
## and so the layout cannot drift from the names this file uses.
func _ensure_buses() -> void:
	for name in [BUS_SFX, BUS_UI]:
		if AudioServer.get_bus_index(name) != -1:
			continue
		var at := AudioServer.bus_count
		AudioServer.add_bus(at)
		AudioServer.set_bus_name(at, name)
		AudioServer.set_bus_send(at, "Master")


func _build_pool() -> void:
	for i in range(VOICE_POOL):
		var player := AudioStreamPlayer.new()
		player.bus = BUS_SFX
		add_child(player)
		_players.append(player)
		_voicing.append(&"")


## Play what the resolver decided, if it decided anything.
##
## Takes a CUE rather than an event, so the decision and the playback
## cannot come apart: this function has no opinion about fog, distance or
## throttling and cannot acquire one.
func play(cue: Dictionary, now: float, ui := false) -> bool:
	if not _enabled or cue.is_empty():
		return false
	var slot := _free_slot()
	if slot < 0:
		# The pool is full. Silence rather than stealing a voice: cutting
		# a volley short to start another one sounds worse than missing
		# the second, and the per-event caps mean this is already rare.
		return false
	var stream := _stream(String(cue["stream_path"]))
	if stream == null:
		return false

	var player := _players[slot]
	player.stream = stream
	player.bus = BUS_UI if ui else BUS_SFX
	player.volume_db = float(cue["volume_db"])
	# Cosmetic jitter, and legal for exactly the reason
	# `cosmetic_offset.gd` is: one-way, bounded, and nothing reads it back
	# (D-006 clause 2). Placeholder audio repeated hundreds of times a
	# minute is what makes a game sound cheap.
	var jitter := float(cue.get("pitch_jitter", 0.0))
	player.pitch_scale = 1.0 + randf_range(-jitter, jitter) if jitter > 0.0 else 1.0
	player.play()

	var event := StringName(cue["event"])
	_voicing[slot] = event
	_heard = AudioCue.note_played(_heard, event, now)
	return true


## Free the slots whose players have stopped, releasing their voices back
## to the per-event caps. Called once a frame by the client — cheaper and
## more predictable than a `finished` signal per player, and it keeps the
## ledger's only writer in one place.
func reap() -> void:
	for i in range(_players.size()):
		if _voicing[i] == &"":
			continue
		if _players[i].playing:
			continue
		_heard = AudioCue.note_finished(_heard, _voicing[i])
		_voicing[i] = &""


## The ledger, for `AudioCue.resolve`. Handed out rather than hidden so
## the resolver stays pure — it reads this and writes nothing.
func ledger() -> Dictionary:
	return _heard


func _free_slot() -> int:
	for i in range(_players.size()):
		if _voicing[i] == &"" and not _players[i].playing:
			return i
	return -1


## Cached, for `UnitMesh`'s reason: loading a stream per event is the M4
## `by_id` defect with a smaller constant, and a volley fires often.
func _stream(path: String) -> AudioStream:
	if _streams.has(path):
		return _streams[path]
	var stream: AudioStream = load(path) as AudioStream if ResourceLoader.exists(path) else null
	_streams[path] = stream
	if stream == null:
		# Missing audio costs SOUND, never the game — the same designed
		# degradation an empty `model_id` gets (D-064). A clone that has
		# not run `just build-audio` plays silently and says so once.
		push_warning("audio: no stream at %s — run `just build-audio`" % path)
	return stream


# --- settings ----------------------------------------------------------

func set_bus_volume(bus: String, linear: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_volume_db(index, linear_to_db(clamped) if clamped > 0.0 else -80.0)
	AudioServer.set_bus_mute(index, clamped <= 0.0)


func bus_volume(bus: String) -> float:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		return 0.0
	if AudioServer.is_bus_mute(index):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(index))


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master", bus_volume("Master"))
	cfg.set_value("audio", "sfx", bus_volume(BUS_SFX))
	cfg.set_value("audio", "ui", bus_volume(BUS_UI))
	cfg.set_value("audio", "enabled", _enabled)
	cfg.save(SETTINGS_PATH)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return
	set_bus_volume("Master", float(cfg.get_value("audio", "master", 1.0)))
	set_bus_volume(BUS_SFX, float(cfg.get_value("audio", "sfx", 1.0)))
	set_bus_volume(BUS_UI, float(cfg.get_value("audio", "ui", 1.0)))
	_enabled = bool(cfg.get_value("audio", "enabled", true))


func set_enabled(on: bool) -> void:
	_enabled = on
	if not on:
		for player in _players:
			player.stop()
		for i in range(_voicing.size()):
			_voicing[i] = &""
		_heard.clear()
