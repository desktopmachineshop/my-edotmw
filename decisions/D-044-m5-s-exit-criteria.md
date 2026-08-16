### D-044 · 2026-08-02 · Accepted — M5's exit criteria
**Decision:** M5 is **"draw it at scale"**, not "LOD". D-015's ladder
named it LOD; M4's measurements make that name wrong in both directions,
so the milestone is reshaped to match what was measured rather than what
was guessed in July.

**Why the rename.** The simulation does not need LOD: D-040 brought the
worst tick to 73.4 ms at D-018's full 1,000 squads, inside D-020's 100 ms
with ~27% headroom, and D-012's own wording is that LOD is built "only
for the tiers M4's profiling shows are actually necessary" — on the
simulation side, currently none. Meanwhile the client has never been
measured at all (D-043 criterion 8), and Q15's deferral trigger —
*"client-render scale must be measured before M5 commits to any rendering
LOD tier"* — is now due.

Two structural facts make the render path the suspect before any LOD
tier: `client.gd` builds **one `MultiMeshInstance3D` per squad**, so
1,000 squads is ~1,000 draw calls; and `_refresh_squads` derives **every
known squad every frame**, including squads nowhere near the camera —
which is the frustum-culling lever D-041 already named as coming *ahead*
of any fidelity reduction.

So: **measure the client, take the cheap structural wins, then build only
the LOD the numbers demand.** LOD is an outcome of this milestone, not
its premise.

**Hardware caveat, stated before the work rather than after.** The
available GPU is integrated/modest, so M5 will **not** definitively
answer "can a client draw 40,000 soldiers". It will produce the shape of
the curve, the draw-call and derivation costs, and an honest
extrapolation — and it will re-arm Q15 with a sharper trigger naming the
hardware still needed rather than letting it lapse.

**The criteria.** Each derived from an accepted decision, each
observable-to-fail, numbered so a review can go line by line as D-026's
and D-027's did.

*Measurement — closes or sharpens Q15*

1. `just bench-render` exists: a **native** recipe (D-014 — the GUI
   client needs a GPU, and `test-client`'s Mesa software rasteriser
   cannot answer a performance question), running without a server, that
   sweeps squad counts to D-018's ~1,000 and reports per count: mean
   frame time, **worst** frame time, draw calls per frame, and soldiers
   drawn.
2. Every reported figure names **the GPU adapter it was taken on**, and
   the recipe prints it. Same discipline as CLAUDE.md's rule that
   µs/squad is never quoted without a squad count: a frame time with no
   hardware attached is not a number anyone can use.
3. Results recorded here, and **Q15 either closed or re-armed with a
   sharper trigger** naming the hardware still required. It must not
   silently lapse — D-043 criterion 13 exists because that already
   happened once.

*Structural wins, measured before and after*

4. Squads are drawn in batches keyed by **unit type** (and live/ghost),
   not one `MultiMeshInstance3D` per squad. Draw calls per frame at 1,000
   squads fall by at least an order of magnitude, with before/after
   numbers from criterion 1's harness.
5. Squads outside the camera are **not derived**. The cull is
   **wrap-aware**: a squad visible only through a seam copy must still be
   derived and drawn, and a test proves a squad across the seam is not
   culled. Getting this wrong makes armies vanish near the seam — D-008's
   recurring torus tax.
6. The lattice step vectors are defined **once**, promoted out of
   `client.gd`'s terrain builder into `TorusSpace`. Terrain tiling,
   camera wrap and the new cull must not become three copies of the same
   arithmetic — M3 deleted a duplicated spawn formula for exactly this
   reason (D-036).
7. Per-frame derivation cost at full scale re-measured against D-041's
   29 ms / 174%-of-a-frame baseline.

*LOD, only if the numbers demand it*

8. **If** frame time at target scale still misses a 60 fps budget after
   4–7, a **render** LOD tier is implemented: camera-keyed (D-012
   explicitly permits this for render), **cosmetic only**, with a test
   proving it never feeds back into simulation, into
   `composition_hash()`, or into anything the server reads — D-006 clause
   2's one-way boundary.
9. **If not**, D-012's render half is resolved with the evidence and an
   explicit revisit trigger — the same standard as the simulation half,
   not an unstated assumption that it is fine.
10. D-012's **simulation** half is resolved as *not needed yet*, citing
    D-040's 73.4 ms at 1,000 squads, with a written revisit trigger.
11. **Q9's remainder is answered** rather than deferred a third time:
    whether tick rate varies by LOD tier.

*The picture, not just the counters*

12. `just test-client` green **and the PNG inspected**. Batching and
    culling are precisely the class of change where every counter passes
    and the image is wrong — this project has already shipped a frame
    with 12 squads drawn, 384 soldiers derived, zero desyncs and no
    visible soldiers at all (D-022's audit).
13. A human `run-client` session confirms squads look right while panning
    across both seams, at minimum and maximum zoom.

*Process*

14. Every new check **observed to fail** before it is trusted (D-022's
    standing rule), with perturbation and revert applied atomically.
15. `just test-unit` green; `just test-load 20 120` still green — the
    client changes touch `ClientState`, so the server path must be shown
    unaffected rather than assumed to be.
16. CLAUDE.md's status section and this log updated to match.

**Rejected alternatives:** Building LOD as D-015's ladder names it
(rejected — D-012's rationale is explicitly against building a complex,
fairness-sensitive system against guessed numbers, and the simulation
budget is already met). Making M5 about playability instead (rejected for
now — D-027's "is it any good" question is real and still open, but Q15's
trigger is *due* and gates M7; playability has no such deadline).
Deferring the client measurement again (rejected — that is how Q15 nearly
lapsed once already).

**Revisit trigger:** If criterion 1's baseline shows the client already
meets 60 fps at target scale untouched, criteria 4–7 become optimisations
without a problem to solve, and M5 should shrink to the measurement plus
resolving D-012 — not proceed out of momentum.

---
