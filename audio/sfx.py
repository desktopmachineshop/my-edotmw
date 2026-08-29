"""Placeholder sound effects, generated (#344).

THE SOURCE OF TRUTH for every file in `generated/audio/`, following
D-081's pattern exactly: a committed generator, committed output, and two
runs must be BYTE-IDENTICAL — fixed seeds, sorted iteration, no
timestamps. `just build-audio` runs it.

## Why generated, and why placeholders are the point

#344's deliverable is the ARCHITECTURE, not sound design. A synthesised
blip that is unmistakably a placeholder is better than a borrowed sample
here: it cannot be mistaken for finished work, it carries no licence, and
it makes the pipeline real without pretending the content is.

Unlike the model pipeline this needs NOTHING installed — `wave`, `math`
and `struct` are the standard library, so `build-audio` works on a fresh
clone where `build-assets` cannot (bpy is a ~1 GB wheel, and is blocked
host-wide by an Application Control policy at the time of writing).
That is deliberate: audio has no such constraint and should not inherit
one.

## Why this lives beside the TABLE and not under `art/`

`art/` is the bpy pipeline, and `art/build.py` hashes every `.py` under
it into `generated/manifest.json` to detect a stale model build. Putting
this generator there made a sound edit mark every MODEL stale — and,
worse, the obvious fix (adding it to `build.py`'s exclusion list) edits a
file that is ITSELF hashed, so it broke the same test a second way. Both
reds are clearable only by `just build-assets`, which needs the blocked
wheel.

So it sits in `audio/`, next to the `*.tres` table it feeds. Audio has
its own manifest and its own staleness test (`tests/test_audio.gd`); it
is a separate pipeline and is now filed as one.

## The shapes

Every cue is one of four gestures, chosen so a listener can tell them
apart on a laptop speaker without any mixing:

  impact   noise burst, fast decay          — a volley landing
  twang    detuned pluck, medium decay      — a bow released
  tick     short square blip                — UI, order acknowledgements
  chime    stacked partials, slow decay     — build complete, stingers

Loudness is deliberately conservative: these are placeholders that will
be played dozens of times a minute, and a generator that ships hot audio
teaches everyone to turn the game down.
"""

import json
import math
import os
import struct
import wave

SAMPLE_RATE = 22050
BIT_DEPTH = 16
PEAK = 0.35  # headroom on purpose — see the module docstring


def _noise(seed):
    """A deterministic LCG, because `random` is not pinned across Python
    versions and D-081 requires two runs to be byte-identical."""
    state = seed & 0xFFFFFFFF
    while True:
        state = (1664525 * state + 1013904223) & 0xFFFFFFFF
        yield (state / 0x7FFFFFFF) - 1.0


def _envelope(i, total, attack, decay_power):
    """Attack-then-decay in [0, 1]. `attack` is a FRACTION of the sound,
    so a cue keeps its shape whatever its length."""
    a = max(1, int(total * attack))
    if i < a:
        return i / a
    t = (i - a) / max(1, total - a)
    return (1.0 - t) ** decay_power


def impact(duration, cutoff_hz, seed, decay_power=3.0):
    """Filtered noise burst — a volley landing, a wall coming down."""
    n = int(SAMPLE_RATE * duration)
    rng = _noise(seed)
    out = []
    prev = 0.0
    # One-pole low pass. Cheap, and enough to turn white noise into
    # something with a body rather than a hiss.
    alpha = min(1.0, 2.0 * math.pi * cutoff_hz / SAMPLE_RATE)
    for i in range(n):
        prev += alpha * (next(rng) - prev)
        out.append(prev * _envelope(i, n, 0.005, decay_power))
    return out


def twang(duration, hz, seed, detune=1.006):
    """Two detuned saws beating against each other — a bowstring."""
    n = int(SAMPLE_RATE * duration)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        a = 2.0 * ((t * hz) % 1.0) - 1.0
        b = 2.0 * ((t * hz * detune) % 1.0) - 1.0
        out.append(0.5 * (a + b) * _envelope(i, n, 0.002, 4.0))
    return out


def tick(duration, hz, decay_power=6.0):
    """A short square blip — UI and order acknowledgements. Square rather
    than sine so it cuts through a battle without being loud."""
    n = int(SAMPLE_RATE * duration)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        square = 1.0 if (t * hz) % 1.0 < 0.5 else -1.0
        out.append(square * _envelope(i, n, 0.01, decay_power))
    return out


def chime(duration, hz, partials=(1.0, 2.0, 3.0), weights=(1.0, 0.5, 0.25)):
    """Stacked partials with a slow decay — completions and stingers."""
    n = int(SAMPLE_RATE * duration)
    total = sum(weights)
    out = []
    for i in range(n):
        t = i / SAMPLE_RATE
        v = 0.0
        for p, w in zip(partials, weights):
            v += w * math.sin(2.0 * math.pi * hz * p * t)
        out.append((v / total) * _envelope(i, n, 0.01, 2.0))
    return out


def sequence(*parts):
    """Concatenate cues — a two-note stinger is two chimes."""
    out = []
    for p in parts:
        out.extend(p)
    return out


def write_wav(path, samples):
    """16-bit mono PCM, normalised to PEAK.

    Normalised rather than clipped: a generator that clips is a generator
    whose output changes shape when somebody edits an unrelated
    parameter, and D-081's byte-identical requirement makes that a
    silently reviewable diff.
    """
    peak = max((abs(s) for s in samples), default=0.0)
    scale = (PEAK / peak) if peak > 0.0 else 0.0
    frames = bytearray()
    for s in samples:
        v = int(max(-1.0, min(1.0, s * scale)) * 32767)
        frames += struct.pack("<h", v)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(BIT_DEPTH // 8)
        handle.setframerate(SAMPLE_RATE)
        handle.writeframes(bytes(frames))


# The table. Keys are the EVENT ids `/audio/*.tres` name, so a reader can
# match a cue to its trigger without opening the resources — and sorted
# iteration below keeps the build deterministic.
CUES = {
    "combat_volley": lambda: impact(0.22, 1400.0, seed=1001),
    "combat_missile": lambda: twang(0.18, 220.0, seed=1002),
    "squad_broken": lambda: sequence(
        chime(0.16, 300.0, (1.0, 1.5), (1.0, 0.6)),
        chime(0.30, 200.0, (1.0, 1.5), (1.0, 0.6)),
    ),
    "building_placed": lambda: tick(0.09, 300.0),
    "building_complete": lambda: chime(0.55, 520.0),
    "building_destroyed": lambda: impact(0.70, 500.0, seed=1003, decay_power=2.0),
    "order_move": lambda: tick(0.05, 720.0),
    "order_attack": lambda: tick(0.07, 480.0),
    "ui_click": lambda: tick(0.04, 900.0),
    "match_start": lambda: sequence(chime(0.22, 392.0), chime(0.45, 523.0)),
    "victory": lambda: sequence(
        chime(0.20, 523.0), chime(0.20, 659.0), chime(0.60, 784.0)
    ),
    "defeat": lambda: sequence(chime(0.28, 330.0), chime(0.70, 220.0)),
}


def source_hash():
    """A hash of THIS generator, so `generated/audio` can be shown stale.

    This generator lives outside `art/` (see the module docstring), so
    the model manifest neither hashes it nor can be broken by it.
    Separate is not unguarded: this is audio's own half of D-081, and
    `tests/test_audio.gd` compares it.
    """
    import hashlib
    with open(os.path.abspath(__file__), "rb") as handle:
        return hashlib.sha256(handle.read()).hexdigest()


def build(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for name in sorted(CUES):  # sorted: D-081's determinism
        samples = CUES[name]()
        path = os.path.join(out_dir, name + ".wav")
        write_wav(path, samples)
        seconds = len(samples) / SAMPLE_RATE
        written.append((name, seconds, os.path.getsize(path)))
    # Sorted keys and no timestamp: the manifest is part of the
    # byte-identical guarantee, not an exception to it.
    manifest = {
        "source_hash": source_hash(),
        "sample_rate": SAMPLE_RATE,
        "cues": sorted(CUES),
    }
    with open(os.path.join(out_dir, "manifest.json"), "w", newline="\n") as handle:
        json.dump(manifest, handle, indent="\t", sort_keys=True)
        handle.write("\n")
    return written


def main():
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    out_dir = os.path.join(root, "generated", "audio")
    written = build(out_dir)
    for name, seconds, size in written:
        print("  %-20s %5.2f s  %6d bytes" % (name, seconds, size))
    print("audio: %d cues -> %s" % (len(written), out_dir))


if __name__ == "__main__":
    main()
