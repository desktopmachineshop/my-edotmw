extends Resource
class_name SoundDef

## One row of the event -> sound table (#344).
##
## Audio is DATA, in D-047's spirit: `/audio/*.tres` says what a match
## sounds like, and **no script may name a sound file**. A civ can
## override an entry later by shipping its own resource with the same
## `event`; nothing in code has to learn about it, exactly as no script
## names a civ today (D-046 criterion 3, enforced by a test).
##
## Every field here answers a question the PURE resolver
## (`audio_cue.gd`) asks. Nothing here is about playback — the director
## owns the players and the buses, and this resource never mentions one.

## The event this cue answers, e.g. &"combat_volley". THE key: the
## roster is indexed by it, and `art/audio/sfx.py` names its generated
## files the same, so a reader can match a cue to its trigger without
## opening either.
@export var event: StringName = &""

## What to play. Written here rather than derived from `event`, because
## two events may legitimately share a sound (a placeholder pass does
## this constantly) and because a civ override should be able to point
## somewhere else entirely.
@export var stream_path: String = ""

## Base loudness, before distance. Decibels because that is what
## `AudioStreamPlayer` takes, and converting in the resource would put
## the same arithmetic in two places.
@export var gain_db: float = 0.0

## How far away, in CELLS, this is still worth hearing. Beyond it the
## resolver returns silence rather than a very quiet sound — a voice
## spent on something inaudible is a voice not spent on something the
## player can hear.
##
## Measured with `TorusSpace.distance`, so it is wrap-aware like
## everything else: a battle just across the seam is as loud as one the
## same distance away on the same side (D-008).
@export var audible_cells: int = 40

## The shortest gap between two of THIS event being heard, in seconds.
##
## The throttle that makes a volley one sound rather than thirty-six.
## D-024 resolves combat as aggregate arithmetic over a whole squad, so a
## single exchange can produce a burst of casualty events in one tick;
## without this the client would try to play all of them, and the result
## is a click rather than a clash.
@export var min_interval: float = 0.08

## How many of this event may sound at once. A cap on VOICES, distinct
## from `min_interval`'s cap on RATE: twenty simultaneous engagements
## across a map is not thirty-six casualties in one tick, and the two
## want different limits.
@export var max_voices: int = 4

## Random pitch spread, as a fraction. 0.1 means +/-10%. Placeholder
## audio repeated hundreds of times a minute is what makes a game sound
## cheap; a little jitter is the cheapest fix there is.
##
## The jitter is a RENDER-side cosmetic, so it may be random — nothing
## downstream reads it back, which is the same one-way rule
## `cosmetic_offset.gd` lives under (D-006 clause 2).
@export var pitch_jitter: float = 0.0

## Whether this cue is gated on the player being able to SEE its cause.
##
## True for anything happening in the world; FALSE for the player's own
## interface — a click, an order acknowledgement, a victory stinger. A
## UI sound has no cell and no cause on the map, and gating it on fog
## would silence the one category of sound that is unambiguously the
## player's own.
##
## This is the flag that keeps "fog gating extends to ears" honest
## without making it absurd.
@export var fog_gated: bool = true
