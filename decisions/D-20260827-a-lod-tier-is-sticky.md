### D-20260827 · 2026-08-27 · Accepted — a LOD tier is sticky, and the distance it reads is a minimum

**Decision:** Render LOD tier selection (D-045) moves out of `client.gd`
into `render_cull.gd` and gains two properties it never had:

1. **A hysteresis band.** A squad LOSES detail only once it is
   `LOD_HYSTERESIS` (15%) past a tier boundary, and REGAINS it at the
   plain boundary — 55 out at 63.25, back at 55; 110 out at 126.5, back
   at 110. Which side of the band applies is decided by the tier the
   squad was drawn at last frame, which the client now remembers: one
   int per squad, cleared with the match.
2. **The distance is a MINIMUM over the squad's visible lattice copies**
   (`RenderCull.lod_distance`), not the distance to whichever copy
   `nearest_offset` picked.

`RenderCull.LOD_TIERS`, `detail_tier`, `lod_soldiers` and `lod_distance`
are the one definition of the ladder. `bench_render.gd`'s hand-copy of
the three tier numbers is deleted.

**Rationale.** Reported from a playtest (#155) as *squads semi popping in
/ out whilst still in player camera* — part of a squad, in the middle of
the view, not at its edge. `_detail_for` was a pure lookup on the current
frame's distance with no memory anywhere in the client, and the steps in
the ladder are not subtle: crossing 55 takes a forty-man squad to twelve
(**-70%**) and crossing 110 takes twelve to five (**-58%**). A squad
sitting anywhere near either boundary flipped on the smallest movement of
itself or the camera, and got its men back on the next frame.

**This is a correctness fix, not polish, and D-045's own rule is why.** A
distant squad is drawn thinner and never smaller *because unit size is
tactical information a player reads off the screen*. A representation
that flickers between forty men and twelve is not information at all —
it is worse than either tier honestly held, because the player cannot
learn to read it. It also quietly undoes
`D-20260818`'s footprint separation (#104): a thinned squad no longer
visually occupies the ground it now correctly holds.

**The second trigger is newer than the first and would have survived a
hysteresis-only fix.** Since
`D-20260818-entities-are-drawn-at-every-visible-copy` a squad is drawn at
every copy on screen, and the client picks one with `nearest_offset` for
the things that still need a single position. That is an **argmin**, and
it is taken against what the camera LOOKS AT while the ladder measured to
where the camera IS. Those are different points on this rig
(`PITCH_RUN` behind, one height above), so when two copies were
near-equidistant *from the look-at point* the distance handed to the
ladder jumped a whole map period as the argmin alternated — **with the
camera completely still**. Measured on the rig at height 40 with a
100-unit period: the two copies stand **84.1** and **47.7** units from the
eye, which straddles the 55 boundary, so the same motionless squad was
drawn with every man on one frame and twelve on the next. A **minimum is
continuous across exactly that tie**; the argmin is not. Fixing the
distance rather than stabilising the argmin also leaves `nearest_offset`
alone for its other callers, which want a placement and not a magnitude.

**The band is one-sided on purpose.** Erring toward detail is the cheap
direction to err: coming back early costs a little derivation, leaving
early under-draws a squad the player is looking straight at. And a squad
with no history reads the ladder as tuned — the band must not become a
permanent 15% shift of numbers that were measured against
`just bench-render`, smuggled in as a stability fix. A test pins that.

**The memory is legal, and it is worth saying which clause makes it so.**
D-006 clause 1 forbids per-soldier integration state in the DERIVATION of
soldier positions. This decides nothing about where anybody stands: the
same slots come back, `soldier_transforms_sampled` picks a subset of them,
and the existing tests that a LOD soldier stands exactly where a
full-detail one would are untouched. It is weaker than the per-soldier
render state D-006 clause 2 was amended to permit by
`D-20260819-tier-three-lives-on-the-render-side` — bounded (one int),
one-way (nothing reads it back), outcome-blind (it never reaches the
simulation, the wire or the composition hash) — and it sits beside
`_drawn_cache` and `_static_deal`, which are the same thing at a larger
size.

**Rejected alternatives:**
- *Stabilising `nearest_offset` with a remembered offset and a margin*
  (rejected — it makes a placement rule carry memory for a consumer that
  wants a magnitude, and every other caller of it pays. The minimum is
  the cheaper answer and it is continuous by construction rather than by
  a tuned margin.)
- *Keying LOD on projected screen size instead of raw distance*
  (rejected for now — the principled version, and the issue says so.
  `extent_scale` already computes projected extent for culling, so it is
  a small change; but it re-tunes the ladder against numbers taken with
  `bench-render`, and re-tuning is a measurement this change did not
  take. The stability defect is fixable without touching what the tiers
  mean, and those are separable, so they are separated.)
- *More tiers with smaller steps* (rejected as the primary fix — it makes
  each flip less visible without making any of them stop, and it is the
  same re-tune above wearing a different hat. Worth doing when somebody
  re-measures the ladder.)
- *Leaving it in `client.gd` and adding the memory there* (rejected —
  every LOD check that existed was single-frame, and the defect is a
  frame-to-frame difference. `client.gd` needs a GPU (D-014), so a rule
  that lives there cannot be watched to fail. "When a rule cannot be
  tested where it lives, that is a fact about where it lives" — D-106's
  own amendment, applied.)

**Consequences:** a squad may now be drawn at full detail out to 63.25
units where it previously thinned at 55, so a frame at scale derives
marginally more soldiers — bounded by the band, and only for squads that
have receded rather than for squads that were always there. Every tier is
still reached by a squad that genuinely walks away, which a test asserts
by walking one from 20 to 420 units out and requiring it to pass through
all three in order: "never changes" would satisfy every stability
assertion here and delete D-045's only lever on the frame budget.
`bench_render.gd` keeps its own copy of the one-int memory, because a
benchmark running a memoryless ladder would re-derive on flips the
shipping client no longer has.

**Measured:** `just test-unit` — see the PR; the hysteresis tests were
observed to FAIL with `LOD_HYSTERESIS` set to 0.0 and the tie tests with
`lod_distance` replaced by the old argmin distance, before either was
trusted (D-022's standing rule). No per-squad simulation cost changes:
nothing in this touches the sim, the wire or any hashed value.

**Revisit trigger:** if the ladder is ever re-tuned — new tier distances,
more tiers, or a move to projected screen size — the band comes with it
and 15% is a number to re-derive, not to keep. And if a playtest still
reports popping with hysteresis in force, that is the *third* mechanism
(genuine culling at the frame edge, `visible_offsets_of_extent`), not
this one, and it should be reported as such rather than by lowering the
band.

---
