**The game had no audio at all, and now has the foundations for it**
(`D-20260828-a-sound-is-a-cosmetic-you-must-be-able-to-see`, #344,
2026-08-28). **The architecture is what landed; the sounds are
placeholders and are meant to be replaced.**

```
just build-audio          # regenerate generated/audio from audio/sfx.py
just test-unit audio      # the table, the gating, the throttles
```

Five pieces, split along one line — **what may be heard** is pure and
tested headless, **what makes a noise** is the only part that needs a
device. Same split `render_cull.gd` makes against `client.gd`, and for
the same reason: the half with the interesting failure mode is the
GATING, and a gate that needs a speaker to exercise is a gate nobody
exercises.

| file | device | what it is |
|---|---|---|
| `audio/sfx.py` | no | the generator — source of every `generated/audio/*.wav` |
| `audio/*.tres`, `sound_def.gd` | no | the event -> sound table |
| `sound_roster.gd` | no | loads it, cached, stable order |
| **`audio_cue.gd`** | **no** | **the decision: fog, distance, rate, voices, loudness** |
| `audio_director.gd` | yes | buses, a voice pool, the ledger |

Five things to know before touching any of it, and most are not about
sound:

- **Ears use the ONE vision query.** `TerrainFog.level_at()` — the field
  the ground shader and the minimap already read (D-106). #344 is
  explicit that a second must not be invented. **EXPLORED is not
  enough**: a player who once saw a hill does not hear the battle on it
  now, which is the same distinction D-030 draws for buildings. A
  fog-gated cue with no cell FAILS CLOSED, because the alternative leaks
  that something happened somewhere. Interface sounds are exempt by
  DATA (`SoundDef.fog_gated`), not by a branch — a click has no cause on
  the map.
- **A volley is one sound, not thirty-six.** D-024 resolves combat as
  aggregate arithmetic over a squad, so one exchange bursts many
  casualty events in a tick. Two limits, deliberately separate:
  `min_interval` caps the RATE of an event, `max_voices` caps
  CONCURRENCY — twenty engagements across a map is not thirty-six
  casualties in one tick, and one number cannot express both.
- **It is one-way and the simulation does not know sound exists**
  (D-006 clause 2). A test scans `squad_sim.gd`, `combat.gd`, `server.gd`
  and the rest for `AudioCue`/`AudioStreamPlayer` and fails if any
  appears. `resolve()` decides and never records — the ledger is passed
  in — which is what makes the same call answer the same way twice.
- **The generator lives in `audio/`, NOT under `art/`, and that is not
  tidiness.** `art/build.py` hashes every `.py` under `art/` into the
  model manifest, so a generator there made a sound edit mark every
  MODEL stale — and adding it to build.py's exclusion list broke the
  same test a SECOND way, because build.py is itself one of the files it
  hashes. Both reds clear only by `just build-assets`, which needs the
  bpy wheel that is blocked host-wide. **A staleness hash covers a
  PIPELINE, and a second pipeline needs its own**: audio has
  `generated/audio/manifest.json` and its own test.
- **`build-audio` needs nothing installed.** `wave`, `math` and `struct`
  are the standard library, so it runs on a fresh clone where
  `build-assets` cannot. Missing audio costs SOUND and never the game
  (D-064) — an absent stream warns once and plays nothing, exactly as an
  empty `model_id` falls back to the primitive tier.

**Deliberately not in this slice**, so nobody reads the absence as an
oversight: real sound design (these are synth placeholders); stereo
placement and a listener transform; music, ambience and voice lines; a
settings SCREEN (the buses and `user://audio.cfg` persistence exist, the
slider does not); and civ overrides, which are **not supported at
all**: there is no `civ` field and no per-civ lookup, so a duplicate
`event` is ignored rather than resolved. An earlier draft of the decision
entry claimed a civ could override a cue; it could not, and the entry
carries the correction.
