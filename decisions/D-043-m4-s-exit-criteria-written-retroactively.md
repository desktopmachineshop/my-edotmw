### D-043 · 2026-08-02 · Accepted — M4's exit criteria, written retroactively, and the audit against them
**Decision:** M4 shipped without written exit criteria, unlike M1
(D-022), M2 (D-026) and M3 (D-027). This entry writes them down and
audits M4 against them.

Writing criteria *after* the work is exactly the failure mode D-022
records — criteria that drift to fit what was produced. The defence used
here is that **every criterion below is derived from a decision that
predates M4**, and each names the decision it comes from. Nothing is
derived from what M4 happened to produce.

**The criteria M4 should have been given:**

1. Per-squad update cost measured at D-018's full scale (~1,000 squads),
   against D-020's ~50 µs budget and its 100 ms tick.
2. Cost measured across a **range** of squad counts, not one point, so
   accidental non-linearity is visible rather than inferred (D-018's
   target assumes linearity).
3. **Worst** tick measured, not only the mean (D-003 warns a large
   engagement re-paths many squads at once; an average cannot see that).
4. Bandwidth per client per second at D-018's 20 players, with a
   budget-overrun count, against D-003's zero-cost-when-idle claim.
5. Memory measured: the server at scale, and per virtual client, against
   D-018's N-clients-in-one-process analysis.
6. Q8 (ship map size) answered **from the measured curve** rather than
   assumed.
7. An explicit verdict on **D-021's GDExtension trigger**: the named
   candidate kernel measured, and a yes/no with evidence attached.
8. Data that **sizes D-012's LOD tiers** — which phase dominates, and at
   what scale, on both the simulation and the rendering side.
9. Client-side derivation cost measured (D-006 trades bandwidth for
   client CPU; only one half of that trade had ever been quantified).
10. The transport question answered — reliable versus
    unreliable-with-resend, which D-026 explicitly listed as "an M4
    measurement".
11. Measurements taken through the **real system** — server, protocol and
    the actual client path — not only synthetic harnesses.
12. Every measurement reproducible from a named `just` recipe.
13. What M4 deliberately does **not** measure stated explicitly at
    completion, not left implied.

**The audit:**

| # | Verdict | Evidence |
|---|---|---|
| 1 | **Met** | 33 µs/squad, 73.4 ms worst tick at 1,000 squads (D-040) |
| 2 | **Met** | count sweep at 100 / 250 / 500 / 1,000 |
| 3 | **Met, with a scar** | see below |
| 4 | **Met** | 595 B/client/s, 0 overruns (D-038) |
| 5 | **Met** | server 42.5 MB; ~1.4 MB per virtual client |
| 6 | **Met, then re-answered** | see below |
| 7 | **Met** | hatch stays shut, candidate retired (D-040) |
| 8 | **Met for simulation, MISSED for rendering** | see below |
| 9 | **Met** | 0.72 µs/soldier (D-041) |
| 10 | **Met** | reliable-ordered kept, on measured loss (D-042) |
| 11 | **Met, and it was the milestone's most valuable finding** | see below |
| 12 | **Met** | `just profile`, `just test-load`, `just test-client` |
| 13 | **Missed** | see below |

**Criterion 3 — met with a scar.** The worst tick was *not* measured at
first. D-038's original pass reported a comfortable 20 ms average while
the real spike was 323 ms, and the correction is recorded in D-038
because the mistake is instructive. It ended up met, but only after the
average had already produced one confident wrong conclusion.

**Criterion 6 — met, then re-answered inside the same milestone.** D-038
answered Q8 as "keep the ship map at or below ~8,192 cells unless field
building is amortised". D-040 then amortised it, and the answer changed
completely: worst tick is now flat in map size, so the solver no longer
bounds it at all. Both answers were correct when taken. Worth recording
that a milestone's own later work invalidated its earlier conclusion —
that is what a conditional answer is *for*.

**Criterion 8 — the real gap, and it was a knowing one.** Simulation-side
sizing data exists and is good: combat dominates at every scale, which is
where simulation LOD would have something to save. **Rendering-side
sizing data does not exist at all.** Nothing has ever been drawn at
scale.

This is not a discovery — Q15 predicted it precisely, saying M4 leaves
"D-012's LOD tiers only partly served: simulation LOD is measurable, but
rendering LOD is not, and M5 must not design that half blind." So the
gap is real, accepted deliberately, and its trigger is now due. **It is
why M5 opens by measuring the client rather than by building LOD**
(D-044).

**Criterion 11 — met, and the most valuable thing M4 produced.** The
sweep and a live 20-player run disagreed by an order of magnitude (~29 ms
against 866 ms), and the sweep was the one that could not see the truth:
`UnitRoster.by_id` re-scanned `/units` from disk on every call, which a
harness resolving its defs once at setup structurally cannot reproduce.
Had M4 been judged on synthetic profiling alone it would have passed
while the live server spent eight tick budgets in a filesystem walk.

**Criterion 13 — missed.** M4's scope boundary lives in Q15's deferral
note, but was never restated when the milestone was called complete.
That is the documentation gap this entry closes, and D-044 criterion 3
makes the same omission impossible for M5 by requiring Q15 to be either
closed or explicitly re-armed.

**Verdict: M4 is complete on the simulation and network side.** One
criterion (8) is half-missed by prior agreement rather than by oversight,
and one (13) is a documentation gap now closed. Neither blocks M5;
criterion 8's missing half *is* M5's first slice.

**Consequences:** The milestone ladder gains a standing rule —
**exit criteria are written before the milestone, not after.** M4 is the
only milestone that broke it, and this audit is the cost of that. The
practice exists because M1's first "complete" was wrong in two ways
(D-022) and M2's and M3's reviews each found real failures a green suite
could not see.

**Revisit trigger:** None — M4 is closed. If criterion 8's rendering half
turns out to change any conclusion M4 drew about the simulation, that is
a D-038/D-040 amendment, not a reopening of this entry.

---
