# D-20260819 · A casualty is visible: death animations and corpses

**Status:** ACCEPTED — workstream 2 of
D-20260818-battle-quality-outranks-player-count (exit criterion 2: "a man
falls where he stood and his corpse is still there a minute later, in the
picture"). **Relates to:** D-006 (clauses 2 and 3), D-024 (which soldier
died is not an input to anything), D-082 (derived animation phase), D-099
(a ghost is drawn nowhere), D-030/D-101 (a building once seen is
knowledge), D-20260817-fog-covers-props (#81).

## Why this exists

Combat's only visible output today is subtraction: `alive` falls, the
formation restamps, and the man is simply not there any more. Nothing
falls, nothing stays fallen, and a battlefield five minutes into a fight
looks exactly like one where nothing has happened. RTW battles are read
off the ground — where the line held is where the bodies are.

## Decision, in six parts

1. **Which man dies is already decided, and stays decided.** D-024:
   occupied slots are `0..alive-1` and the formation restamps, so the men
   who visibly vanish on a casualty event are exactly slots
   `[new_alive, old_alive)`. Corpses spawn at those slots' derived
   positions at the moment the event is applied. No per-soldier identity
   is introduced anywhere — the corpse layer is a record of where the
   formation function last put a man the wire then subtracted.

2. **The wire says whether the men FELL, because it is the only honest
   source.** `consume_squad` (a founding party spent on a town hall,
   D-031) and `eliminate_player` (a disconnect wipe, D-033) both report
   through the same casualty event shape as combat — deliberately, so
   clients apply one message. A corpse is a claim about HOW a man left,
   and the client cannot infer it: corpses at every town-hall foundation
   would be the visible result. Casualty events therefore carry a `fell`
   flag — true from combat resolution (squad-vs-squad and building fire),
   false from consumption and elimination. One byte per event; the
   composition hash reads none of it; the replay format changes with the
   wire as it always does (D-016), which is acceptable before M8's
   version handshake exists.

3. **The fall is the VAT's fifth clip, and its phase is still derived.**
   `art/lib/clips.py` gains `death` (a crumple: knees buckle, torso
   pitches, body sinks — ends flat). The corpse instance's phase is
   `clamp((now - t_event) / DURATION, 0, 1)` — a pure function of the
   replicated event time and the clock, no accumulator (D-082's rule in
   different clothes). Mechanically: the shader's rate field is 0, so
   `phase = custom.r` exactly, and the client rewrites that one float per
   falling corpse per frame from the formula, then stops forever at the
   final frame. Rejected: a one-shot mode in the shader keyed on a start
   TIME (the client cannot robustly know the shader's TIME origin), and a
   baked static corpse mesh per archetype (a second art artifact per
   model for one frame the VAT already holds).

4. **A corpse is knowledge, and fog dims it like the ground it lies on.**
   D-099's squad ghosts are drawn nowhere because a squad that was there
   has moved; a corpse has not, which puts it on the buildings' side of
   that line (D-030/D-101): once seen, drawn forever. #81's rule then
   applies in full — everything standing (or lying) on fogged ground
   takes the fog tap — so corpses render through their own small shader
   (`unit_corpse.gdshader`, a second compile-time program for the same
   reason D-099's note gives). It reuses `unit_vat.gdshaderinc`
   unchanged; per-instance custom data is remapped to
   `(phase, fog_u, fog_v, fog_flag)` since a corpse layer has one clip
   and rate 0 by construction — the clip index is a uniform. The fog UV
   comes from the CELL, exactly as props' does.

5. **Corpses are capped, and the cap is a ring.** D-018-scale battles
   kill tens of thousands of men; corpse count is bounded
   (`CorpseLedger.MAX_CORPSES`), oldest evicted first via swap-remove in
   per-(model, owner) buckets. The ledger — append, evict, cross-bucket
   replacement, falling-phase bookkeeping — is a pure-logic class tested
   headless, because a headless MultiMesh stores nothing
   (D-20260817-fog-covers-props' lesson) and the render half is looked at
   in the preview instead.

6. **The layer is drawn at every visible lattice copy**
   (D-20260818-entities-are-drawn-at-every-visible-copy) — mirrored the
   same way terrain tiles, since corpses accumulate over the whole map.
   And it is client-render-only: `ClientState` records casualty sites
   into a drain (`take_casualty_sites`) only when `record_corpses` is
   set, which the GUI client sets and the load-test bots do not — a bot
   accumulating an unread corpse list for a whole run would be a slow
   leak in the instrument.

## What this deliberately does not do

- No per-soldier simulation state, no reading anything back (D-006
  clauses 1–2 untouched; the revisit trigger is workstream 10's, not
  this one's).
- No corpse persistence across conceal/reveal EVENTS beyond what the
  client saw: casualties are visibility-gated on the wire already, so a
  fight nobody watched leaves no bodies for that client. Truthful, same
  as D-025's reveal.
- No decay, no looting, no gore tiers. A corpse is one frozen VAT frame.

## Revisit trigger

If the capped layer visibly churns in normal play (bodies popping out
under the cap during one battle), raise the cap and re-measure before
inventing spatial eviction. If a future feature needs to KNOW where
corpses are (looting, morale from carpets of dead), that is simulation
reading a render record — stop, and move the record to the server first.
