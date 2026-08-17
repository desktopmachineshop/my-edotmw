### D-20260817 · 2026-08-17 · Accepted — M10 (scale optimisation), and its exit criteria written before the code

**Decision:** the work needed to make the enlarged map ladder
(D-20260817-the-zoom-cap-was-modelling-the-wrong-axis) actually
shippable becomes its own milestone, **M10**, rather than being absorbed
into the change that created it. Its exit criteria are below, written
before any of it is built — the pattern D-022, D-026, D-027, D-044,
D-085 and D-094 all follow, and the one M2 and M6 had to learn twice.

**M10 runs BEFORE M8 (Steam).** M8's headline criterion is a 20-seat
match with real remote humans on installed builds; shipping that on a map
that freezes the client for five seconds at start would be shipping the
defect to playtesters. M8 and M9 keep their numbers — D-087..D-094 and
D-068..D-074 cite them, and this directory's rule 3 forbids renumbering.

---

**Rationale.** The size increase was taken deliberately and the owner has
confirmed the scale is wanted. It is not free, and the costs are now
measured rather than feared:

| | measured | where |
|---|---|---|
| terrain meshing at client start | **5,071 ms**, 143 chunks, 235,728 verts | `just gen-terrain-preview` |
| flow-field waits | **2,968 of 3,005 ticks** | `test-load 4 300` |
| per-squad update | **167.7 µs at 48 squads** (was ~83 at 28) | same run |
| server memory | 43.3 MB with **4** squads | `quick-test`, 168x194 |
| resource nodes | 7,694 (was 1,958) | same |

The tick budget is still met — worst tick 44.9 ms against D-020's 100 ms,
zero dropped ticks — so nothing here is an emergency. What is not met is
the *client*, and the per-squad rise is unexplained, which makes every
other number harder to read.

**Every item is independently tackleable**, which is the point of
spinning it out: they touch different files, have different owners, and
each carries its own measurement. They are filed as issues against the
`M10 — scale optimisation` GitHub milestone (#105-#112), in the order
below.

**The workstreams:**

1. **Client start-up cost** (#106). 5,071 ms of terrain meshing in one blocking
   pass. Levers: chunk size (D-017 was decided *by measurement* and that
   measurement is now four years of map sizes stale — `gen-terrain-preview
   --chunk-size` exists precisely to re-take it), meshing spread across
   frames, or a worker thread. Whichever wins, the recipe that decides it
   already exists.
2. **Flow-field latency** (#107). `field_cells_per_tick` at 4,096 is an eighth of
   a field on the default map, so a squad can wait ~0.8 s to start moving,
   and ~3.2 s on the largest. D-040 chose a per-TICK budget precisely so
   map size costs latency rather than a spike, and that trade is now being
   spent. Raising the budget trades straight against worst tick, which
   has 55 ms of headroom.
3. **Attribute the per-squad cost** (#105). 83 -> 167.7 µs while vision and
   combat both FELL. Also still open: M6's unattributed 40.8 -> ~77 rise.
   **This one goes first** — until the number is explained, no other
   optimisation here can be shown to have worked.
4. **Re-base `just profile`** (#108). Its sweep tops out at 32,768 cells, which
   is now the DEFAULT map; the largest shipped size is 130,368. The sweep
   is the authority on scaling and it currently cannot see the shipped
   ladder at all.
5. **Resource-node placement** (#109). 7,694 nodes, and `_place_node` does ~7
   noise evaluations plus stand generation per cell, all in one frame when
   a region is revealed. Suspected source of frame hitches, and a
   candidate for the playtest report of forests appearing in bulk that
   culling has been cleared of (0 wrongly-culled in 41,184 tests on the
   shipped map).
6. **Draw entities at every visible lattice copy** (#110). Named in
   `render_cull.gd` since M5 and rejected on scope twice. It deletes the
   recurring copy-choice bug class outright, fixes the two live bugs below
   for free, and would let the zoom cap rise instead of constraining the
   map ladder. The largest item here and the most valuable.
7. **Server memory at scale** (#111). 43.3 MB with four squads on the new default
   says the map itself now dominates. D-018 targets 20 players; that
   figure has never been taken on this ladder.
8. **Iteration cost** (#112). `test-load` needs ~300 s where 150 s did. D-098's
   scenarios are the existing answer and there are only a handful; more of
   them, or a scenario-based gate, keeps the loop usable.

**Two live bugs, filed here because item 6 fixes both:** per-soldier
selection discs are drawn at the canonical position with no lattice
offset, so they detach from a wrapped squad; and a missile's endpoints are
baked at launch, freezing it to the copy it was fired at.

---

**Exit criteria.** Written before the code, and each one a thing that can
be *observed to fail*:

1. **The client is interactive within 1.5 s** of a match starting on the
   default map, measured and printed, not eyeballed. No single blocking
   pass over 250 ms.
2. **No frame over 50 ms** during a normal match on the default map, on
   the integrated-graphics baseline M5 and D-086 both used — measured
   across a real session, not a benchmark loop.
3. **A move order produces movement within 2 ticks (0.2 s)** on the
   default map, or a longer number is stated, defended and made visible to
   the player. `field_waits` is reported by the server and must fall.
4. **The per-squad update cost is fully attributed** — every µs of the
   83 -> 167.7 rise assigned to a named phase, with M6's older 40.8 -> ~77
   rise closed at the same time or explicitly declared separate.
5. **`just profile` sweeps the shipped ladder**, 8,064 to 130,368 cells,
   and its worst-tick curve is flat or has a stated reason not to be.
6. **`just test-load` is clean at 20 players on the default map**, with
   bandwidth, memory and worst tick all inside D-018's and D-020's
   budgets. Server memory quoted with its player count.
7. **`just bench-render` at 1,000 squads on the new default**, on named
   hardware, against M5's 35.66 ms and D-086's 53.93 ms — so the cost of
   the bigger map on the client is a number and not a shrug.
8. **A human plays a full match on the default map and says it feels
   right** — start-up, pathing responsiveness and zoom. This is D-085
   criterion 14's lesson: every milestone that skipped it had to come
   back.

Criteria 1, 3 and 8 are the ones the owner actually reported; 4 is the one
that makes the rest interpretable.

**Rejected alternative: shrink the maps back.** Available at any time and
genuinely cheap — 126x146 still fixes the duplication bug the cap change
was for. Rejected because the owner asked for the scale explicitly, and
because every cost above is a real cost the project would meet at D-018's
20-player target regardless; a smaller map defers them rather than
avoiding them.

**Revisit trigger:** if criterion 3 cannot be met without exceeding
D-020's tick budget, the map ladder is too big for the pathfinder and the
honest response is fewer sizes, not a slower game.
