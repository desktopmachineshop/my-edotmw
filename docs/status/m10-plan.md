## M10 (scale optimisation) — PLANNED, not built

The map ladder moved up a rung on 2026-08-17 so the zoom cap could stop
showing the same ground twice
(`decisions/D-20260817-the-zoom-cap-was-modelling-the-wrong-axis.md`).
The default map is **168 x 194 = 32,592 cells**, four times its old area,
and the owner has confirmed the scale is wanted.

**M10 is the work that makes that shippable, and it runs BEFORE M8.**
Exit criteria are `decisions/D-20260817-m10-scale-optimisation.md`,
written before any of the code. Every item is independently tackleable
and independently measurable; they are filed as **issues #105-#112**
against the `M10 — scale optimisation` milestone.

**What it costs today, measured rather than feared:**

| | measured | how |
|---|---|---|
| terrain meshing at client start | **5,071 ms**, 143 chunks | `just gen-terrain-preview` |
| flow-field waits | **2,968 of 3,005 ticks** | `just test-load 4 300` |
| per-squad update | **167.7 µs at 48 squads** (was ~83 at 28) | same run |
| worst tick | 44.9 ms, **0 dropped** | same run |
| server memory | 43.3 MB with **4** squads | `quick-test` |
| resource nodes | 7,694 (was 1,958) | same |

The **server is fine** — the tick budget is met with 55 ms of headroom.
What is not fine is the **client**: five seconds of blocking terrain
meshing before a match is playable. That is the one a player feels first,
and it was found by a human closing the window and asking whether the
server was down.

**Three things to know before picking up any of it:**

- **The per-squad rise is attributed (#105, done):** it is the
  **flow-field expansion slice** (D-040), and the reason no reported phase
  moved is that the tick had only two reported phases. Every region of
  `SquadSim.tick()` is timed and printed now, with a computed residual —
  `decisions/D-20260818-every-microsecond-of-a-tick-has-a-phase.md` has
  the A/B (same squads, same orders, only the map changes: field expansion
  52.5 -> 453.1 µs/squad on 4x the cells, every other phase FELL, residual
  0.03%). The mechanism is a per-TICK cell budget divided by a squad
  count, which is D-040 working as designed — spending it better is #107,
  not this. **M6's older 40.8 -> ~77 rise is declared SEPARATE** in the
  same entry: those two numbers were taken at 120 and ~52 squads on builds
  with no breakdown, so no attribution can be recovered from them, only
  invented.
- **`just profile` currently cannot see the shipped ladder (#108).** Its sweep
  tops out at 32,768 cells, which is now the *default* map; the largest
  size is 130,368. The sweep is this project's authority on scaling, so
  re-basing it is a prerequisite for trusting anything it says.
- **The biggest item (#110) is the one twice rejected on scope**: drawing
  entities at every visible lattice copy. It deletes the recurring
  copy-choice bug class (armies vanishing at the seam, "half the screen
  renders no units", click-selects-nothing, forests snapping a map period
  sideways), fixes two known live bugs for free, and would let the zoom
  cap rise instead of the map ladder having to carry it.

**What is NOT in M10:** the zoom cap itself is fixed and its bug class is
closed. Culling has been cleared twice by measurement — 0 wrongly-culled
chunks in 36,288 tests on the old map and 41,184 on the new one — so a
report of forests popping is not a culling fault and should not be
diagnosed as one.
