# D-20260824-the-client-renders-on-the-servers-clock

**Date:** 2026-08-24 · **Status:** Accepted

From the owner, on the third round of "the dwarf does not walk", with a
video: *"still not working. The animation is tied incorrectly somewhere."*
They were right, and the tie was not in the animation.

## The defect

**The GUI client sampled every curve at a wall clock started at its own
node's `_ready`,** while curve keyframes live on the SERVER's clock — a
clock that is ahead by however long the client spent connecting and
building terrain (6–23 s measured this session). Every sample therefore
CLAMPED to the edge of the curve.

What made it survive from M1 to now is that the clamp is almost
invisible:

- **Positions still moved.** Each fresh curve's first keyframe is the
  squad's position when the server sent it, so the clamped sample
  advanced with every curve update, and `SoldierMotion.ease` smoothed
  the hops into what read as marching. The march the owner has been
  watching for months was eased hops, not interpolation.
- **Nothing the test estate checks depends on the render clock.** The
  state-hash compares composition; `test-client`'s verdict counts squads
  drawn and casualties applied; bots sample with times from the packets
  themselves. The one number the clamp forced to zero was **measured
  speed** — a clamped curve has no gradient — and the only consumer of
  speed was ANIMATION.

So `AnimationState.clip_for(... moving: speed > 0.15)` never saw a
moving squad, and **the walk clip has never played in a live client, for
any unit, since animation shipped (D-082/M7)**. On capsules nobody
could tell — and `footfall_bob`, which should have bobbed only movers,
was fed a literal `1.0` at its one call site, so everything bobbed all
the time and read as "life". The two defects masked each other: fixing
the literal (same day) made everything stiller, which is what finally
made "no walking" undeniable on a model with a real rest pose.

## Measured, not inferred

Telemetry added to `set_clip_data` (prints on write — a change-driven
write that never fires is the evidence) and a throttled per-squad
speed/clip line:

- Owner's live session: six move orders, squads marching on screen,
  **one clip write for the whole session** — `idle rate=0.28
  speed=0.00` at connect. No walk write ever.
- `just test-client` (the capture client, real server, real orders):
  **every speed sample 0.00**, every clip idle, both drawn squads, all
  run long.
- After the first fix (tick anchor minus a fixed 0.25 s delay): the
  first nonzero speed a live client has ever measured and the first walk
  clip ever selected — **and a new fault**, reported from play as
  formations misbehaving and units teleporting. The telemetry showed a
  SAWTOOTH: speed ramping 0.25 -> 2.07 over ~0.2 s, snapping to 0.00,
  repeating. Cause: a curve packet REPLACES the squad's whole curve
  (`_handle_curve`) and starts at SEND time, and a moving squad's curve
  was being re-emitted every ~0.25 s — so a render clock even slightly
  behind the freshest start spends most of every interval clamped
  BEFORE it: jump to the new first keyframe, freeze, slide in, jump
  again. A fixed delay of any size loses: too small clamps at the front
  on jitter, too large clamps at the front on every replace.
- After the second fix (the curve anchor below): 385 writes over a
  session, 295 walk / 90 idle, **2** hard walk->idle snaps in total
  against one per ~0.25 s before; speed traces ramp, hold through the
  march, and decay smoothly into idle at arrival.

## Decision

1. **`_now` is anchored to THE CURVES THEMSELVES:**
   `ClientState.render_time()` free-runs from the freshest curve START
   this client has received. That start is the squad's position at send
   time, so it is the closest thing the client has to "the server's
   now, on the axis curves are actually sampled on" — and it self-tunes
   to whatever the emission cadence is, which a tick-anchored estimate
   plus any fixed delay demonstrably does not (see the sawtooth above).
   A squad whose curve is OLD is simply unchanged: sampling past its
   end clamps to the spot it stands on, speed zero, idle clip — correct
   by construction, and D-003's zero-bandwidth idle claim intact.
2. **One jump at first sync, monotonic after** (`maxf`): a clock that
   runs backwards re-derives soldiers backwards. Re-sync is allowed
   again after a return to the lobby, where the next match's anchor
   restarts.
3. **Wall time survives only where the question is about THIS process:**
   the capture run's duration (`_wall_now`). Everything that reads the
   WORLD — soldier derivation, speed, minimap, selection, missiles —
   reads `_now` and therefore now reads one consistent clock.
4. The HUD match clock stays on `match_elapsed()` — a wall-anchored
   timer is the right clock for a NUMBER a player reads, and the wrong
   one for sampling curves.

## Rejected alternatives

- **A separate `_sim_now` used only for curve sampling.** Keeps `_now`
  untouched, but every future call site must pick the right clock of
  two, and one wrong pick puts selection and drawing at different
  times. One clock, with the process-local exceptions named, inverts
  the default the safe way round.
- **Fixing only `squad_speed`** (sampling relative to the curve's own
  span). Cures the animation and leaves positions as eased hops —
  interpolation is the design (D-003), and this was the chance to make
  it true.

## Consequences

- Squads interpolate properly for the first time; marching should be
  visibly smoother, latent only by the freshest packet's flight time.
- `footfall_bob` fed real speed now does what its doc always said.
- The general renders as a capsule (`model_id = ""` on both shipped
  generals) — surfaced by the same telemetry, working as designed
  (D-081's fallback), noted here so nobody re-diagnoses it as a bug.
  An authored general model is content work waiting for an owner.
- The `CLIP`/`CLIP-GUARD` prints stay: writes are change-driven and
  rare, and a write that never fires was exactly the evidence this
  needed. The per-frame throttled `ANIM` line is diagnosis-only and
  comes out with this entry's landing.

## The lesson, which is D-022's again

Every instrument this project has measured the client with counts
THINGS — squads drawn, soldiers derived, hashes compared. All of them
were green for six milestones over a client that had never interpolated
a curve or played a walk cycle. The number that would have caught it is
a RATE, and no check ever asked for one. When a system's whole design is
"state as curves, interpolated locally", a test that never measures a
derivative is a test of the packets, not of the design.

## Revisit trigger

- Any report of squads stuttering or rubber-banding: the relationship
  between `render_time()`'s anchor and the server's curve emission
  cadence is the first place to look — and the CLIP telemetry (writes
  are change-driven) is the instrument that found both faults here.
- Why a MOVING squad's curve is re-emitted every ~0.25 s is a question
  this entry surfaces and does not answer. If that cadence is the
  invalidation scheduler doing more work than D-003 intends, fixing it
  is bandwidth won — but the render clock above is correct at ANY
  cadence, which is the property that matters.
- A second clock consumer with its own idea of "now" appearing anywhere
  in `client.gd`.
