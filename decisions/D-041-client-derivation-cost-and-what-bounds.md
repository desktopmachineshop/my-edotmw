### D-041 · 2026-08-01 · Accepted — client derivation cost, and what bounds soldiers on screen
**Decision:** Record what D-006's trade actually costs on the client, and
name the constraint it creates. D-006 sends squad curves and never
soldier positions; the bandwidth saving has been measured since M4's
first day, and the CPU it was traded for never had been.

**Measured** — a real `ClientState` fed by a real `CurveReplicator`, so
the figure includes the dictionary walk and composition lookups a client
actually pays, not just the formation maths:

| squads | soldiers | µs/soldier | ms/frame | of a 60 fps frame |
|---|---|---|---|---|
| 100 | 4,000 | 0.63 | 2.5 | 15% |
| 250 | 10,000 | 0.64 | 6.4 | 38% |
| 500 | 20,000 | 0.70 | 14.1 | 84% |
| 1,000 | 40,000 | 0.72 | 29.0 | **174%** |

Live, 20 players: **1.49 µs/soldier** over 25.9M derivations, worst
single pass **0.52 ms**. The live figure is worse per soldier because
twenty virtual clients share one process and contend; the sweep is the
better estimate of what one real client pays.

**The budget here is a FRAME, not a tick**, and unlike the server's tick
there is nothing to amortise: every soldier must be somewhere every
frame.

**This was 3.7x worse when first measured** — 2.66 µs/soldier, 106 ms and
639% of a frame at full scale. `Formation.soldier_transform` re-sampled
the squad curve twice (position and heading) and rebuilt the rotation
basis *per soldier*, so a 40-man squad took 40 identical curve samples
every frame. Only the slot offset varies per soldier. Hoisting the
squad-wide work out of the loop is not a shortcut around D-006's purity
clause — it is the same pure function with its loop invariants lifted —
and `test_bulk_derivation_matches_the_single_soldier_path` asserts the
bulk and single paths stay bit-identical, because a divergence there is a
client and a server disagreeing about where a man is standing.

**Conclusion: derivation is comfortable for realistic on-screen counts
and is what bounds the pathological one.** A player's own 2,000-soldier
army (D-018) costs ~1.4 ms, under 9% of a frame. 20,000 visible soldiers
fit at 60 fps. All 40,000 visible at once does not — but that is a case
fog of war (D-004/D-025) already prevents and D-012's LOD exists to
handle, and it now has a number attached instead of an intuition.

**Consequences:** D-012's LOD gains its first hard trigger on the CLIENT
side, alongside the server-side one D-038 gave it. The obvious first
lever is not LOD at all: the client currently derives every squad it
knows about, including squads outside the camera frustum. Culling before
deriving is a rendering-layer change with no bearing on D-006, and should
come before any fidelity reduction.

**Rejected alternatives:** Deriving at a lower rate than the frame rate
and interpolating (rejected for now — soldier positions move continuously
along the curve, so this trades a real CPU saving for interpolation state
per soldier, and per-soldier state is precisely what D-006 clause 1
forbids). Sending soldier positions after all (rejected — that is D-006's
40x bandwidth multiplier, and the measurement shows the CPU side is not
the binding constraint at realistic counts).

**Revisit trigger:** If frustum culling lands and a realistic engagement
still exceeds ~30% of a frame in derivation, that is the point to bring
D-012's LOD to the client rather than tune this further.

**Corrected 2026-08-02 (M5): 0.72 µs/soldier understated the real cost,
because the sweep passed no terrain sampler.**

D-006's input tuple is (curve, formation shape, slot index, **terrain
sample**), and the real client always supplies that fourth input — it is
what stands soldiers on the ground instead of at y=0. The sweep behind
the table above passed `Callable()`, so it skipped the sampler entirely
and measured a client that does not exist.

Measured with the sampler attached, as the client actually runs:
**~3.4 µs/soldier**, not 0.72 — nearly five times more, because
`TerrainGen.elevation_at` evaluates 3D simplex noise per call and the
sampler is called once per soldier per frame. Memoising elevation into a
per-cell field (D-045) took it back down, and that single change was
worth 29% of the whole frame at full scale.

The conclusions this entry drew survive — derivation is comfortable at
realistic on-screen counts and binds only the pathological one — but the
margin was much thinner than the number said.

**This is the same failure as D-043 criterion 11's**, one milestone
later and in the opposite direction: there, a harness resolved UnitDefs
once at setup while the live server resolved them per tick; here, a
harness omitted an input the live client always provides. Both are a
measurement of something adjacent to the thing being measured. The rule
worth keeping: **when a harness stands in for the client, list what the
client feeds it and check the harness feeds the same.**

---
