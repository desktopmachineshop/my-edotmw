# D-20260828 · A sound is a cosmetic, and you must be able to SEE its cause

**Status:** ACCEPTED — first slice, foundations only. **Closes:** #344.
**Constrained by:** D-006 clause 2 (client cosmetics are one-way),
D-004/D-025 (fog is curve gating and there is ONE query), D-106 (the
client's own fog field), D-024 (combat is squad-level aggregate
arithmetic), D-047/D-046 criterion 3 (flavour is data; no script names
it), D-081 (committed generator, committed output, byte-identical runs),
D-064 (a missing asset costs fidelity, never the game).

## Decision

The game had no audio system anywhere. This is the architecture, not the
sound design — #344 says so and it is worth repeating, because the
placeholder cues are deliberately synthetic and will be replaced.

Five pieces, split along one line: **what may be heard** is pure and
tested headless; **what actually makes a noise** is the only part that
needs a device.

| file | needs a device | what it is |
|---|---|---|
| `audio/sfx.py` | no | the generator — THE source of every `generated/audio/*.wav` |
| `/audio/*.tres` + `sound_def.gd` | no | the event -> sound table |
| `sound_roster.gd` | no | loads it, cached, stable order |
| **`audio_cue.gd`** | **no** | **the decision: fog, distance, rate, voices, loudness** |
| `audio_director.gd` | **yes** | buses, a voice pool, the ledger |

That is the same split `render_cull.gd` makes against `client.gd`, and
for the same reason: the half with the interesting failure mode is the
GATING, and a gate that needs a speaker to exercise is a gate nobody
exercises.

## Fog gating reuses the one vision query

#344 is explicit — *"a sound a player could not SEE the cause of must not
play; reuse the vision query, do not invent a second"*. On the client
that query is `TerrainFog.level_at()`, the field the ground shader and
the minimap already read (D-106).

`AudioCue.resolve` takes the **level** rather than the fog object, which
is what keeps it pure and means a caller cannot quietly hand it a
different notion of visibility without saying so at the call site.

**EXPLORED is not enough, and that is the interesting half.** A player
who once saw a hill does not hear the battle on it now. That is the same
distinction D-030 draws for buildings — seeing once is *knowledge*, not
sight — and it is the difference between fog you can hear through and fog
you cannot.

A fog-gated cue with **no cell fails closed**: it cannot be checked, and
the alternative leaks that something happened somewhere, which is exactly
what fog withholds.

**Interface sounds are exempt by DATA, not by a branch.**
`SoundDef.fog_gated` is false for clicks, order acknowledgements and
stingers: a UI sound has no cause on the map, and gating it on sight
would silence the one category that is unambiguously the player's own. A
later pass can move a cue between the two categories without touching
code.

## A volley is one sound, not thirty-six

D-024 resolves combat as aggregate arithmetic over a whole squad, so a
single exchange can burst many casualty events inside one tick.
Unthrottled that is a click rather than a clash — and thirty-six voices
spent on one event.

Two limits, deliberately separate, because they answer different
questions:

- **`min_interval`** caps the RATE of one event (thirty-six casualties in
  one tick are one volley);
- **`max_voices`** caps CONCURRENCY (twenty simultaneous engagements
  across a map are not thirty-six casualties in one tick).

`volley_magnitude(fell, size)` takes a COUNT, so there is nowhere in it
for per-soldier state to live — the same structural reason `Formation` is
all-static. It is a square root rather than linear because loudness is
perceptual: losing six of thirty should not be a fifth as loud as a wipe.

## `resolve()` decides and never records

The ledger is passed IN and written by `note_played` / `note_finished`,
which the director calls. That is what makes the same call answer the
same way twice, which is what every test rests on — and it is why the
resolver can hold no state at all.

## It is one-way, and a test says so

D-006 clause 2. Nothing here is read back: no curve, no order, no hash
and no packet depends on a sound having played, and the server has no
audio concept. `tests/test_audio.gd` scans the simulation files for
`AudioCue`, `SoundRoster`, `AudioStreamPlayer` and `AudioServer` and
fails if any of them appears. A sound that changed an outcome would be a
per-client divergence with no wire evidence — the worst shape this
project has a name for.

The event queue on `ClientState` copies `_casualty_sites`' contract
exactly, including the flag: only something that DRAINS it sets
`record_audio`, so the load-test bots and the AI seats — which run this
same class — leave it off and the list stays empty for the length of a
run.

## Audio is data

`/audio/*.tres`, in D-047's spirit, and a test fails if any `.gd` names a
`.wav`. A civ may override an entry later by shipping a resource with the
same `event`; nothing in code has to learn about it, exactly as no script
names a civ today.

## The generator lives in `audio/`, not under `art/`, and that cost a run

`art/` is the bpy pipeline, and `art/build.py` hashes every `.py` under
it into `generated/manifest.json` to detect a stale model build. A
generator placed there made a sound edit mark every MODEL stale — and the
obvious fix, adding it to `build.py`'s exclusion list, broke the same
test a SECOND way, because `build.py` is itself one of the files it
hashes. The exclusion list lives inside the file the list is hashing.

Both reds are clearable only by `just build-assets`, which needs the
blocked wheel. So the generator sits beside the `.tres` table it feeds,
and `art/build.py` is untouched.

> **A staleness hash covers a PIPELINE, and a second pipeline needs its
> own.** Audio has `generated/audio/manifest.json` and its own test;
> separate is not unguarded.

## Why generated placeholders, and why they need nothing installed

D-081's pattern: committed generator, committed output, two runs
byte-identical (fixed seeds, sorted iteration, no timestamps — verified
by rebuilding and diffing).

A synthesised blip that is unmistakably a placeholder is better than a
borrowed sample: it cannot be mistaken for finished work and carries no
licence.

**And it needs nothing installed.** `wave`, `math` and `struct` are the
standard library, so `just build-audio` runs on a fresh clone — unlike
`build-assets`, whose ~1 GB `bpy` wheel is currently blocked host-wide by
an Application Control policy. Audio has no such constraint and should
not inherit one.

Missing audio costs SOUND and never the game (D-064): an absent stream
warns once and plays nothing, exactly as an empty `model_id` falls back
to the primitive tier.

## Non-positional players, deliberately

`AudioCue` already computes wrap-aware distance attenuation, because the
fog gate and the audible-range cull are one decision and splitting them
would put the torus tax in two places. So the director uses plain
`AudioStreamPlayer`s carrying a resolved `volume_db`, not
`AudioStreamPlayer3D`s with their own falloff — two attenuation curves
multiplying each other is a thing nobody can tune. Stereo placement is a
later pass and wants the camera basis; binding this file to the camera
now would buy nothing.

## Observed red

Every gate perturbed and watched to fail, then restored:

| perturbation | caught by |
|---|---|
| the fog gate removed | the two fog tests |
| EXPLORED treated as audible | `test_remembering_ground_is_not_hearing_it` |
| the rate throttle removed | the volley tests |
| the torus torn out of the distance | the seam test |
| `resolve()` made to record | the purity and voice-cap tests |
| `# AudioCue` appended to `combat.gd` | `test_the_simulation_does_not_know_sound_exists` |

One of my own guards fired on a **doc comment** — `sound_roster.gd`'s
header says *"a test fails if any `.gd` names a `.wav`"*, and the scan
counted that sentence as a reference. It reads code lines now, the same
correction `test_starting_positions.gd` needed the same day.

## Deliberately not in this slice

Named so nobody reads their absence as an oversight:

- **Real sound design.** These are synth placeholders and are meant to be
  replaced. The architecture is the deliverable.
- **Stereo placement and a listener transform.** See above.
- **Music, ambience, unit voice lines.**
- **A settings SCREEN.** The buses and persistence exist
  (`AudioDirector.save_settings` / `load_settings`, `user://audio.cfg`);
  a slider in the menu is UI work and wants the HUD layout rules.
- **Civ overrides.** The schema supports them (`event` is the key); no
  civ ships one yet, so the mechanism is unexercised and should be
  treated as untested until one does.

## Revisit trigger

If a cue ever needs to know something the SIMULATION knows and the client
does not, stop: that is a request to put audio on the wire, and it
reopens D-004's gating rather than extending this. And if the voice pool
is ever the reason a frame is late, the lever is the per-event caps in
data, not a bigger pool.
