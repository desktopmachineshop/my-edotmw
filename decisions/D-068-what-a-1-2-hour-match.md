### D-068 · 2026-08-04 · Provisional — what a 1–2 hour match is made of
**Decision:** The design centre is a **90-minute match**, with 60 and 120
as the band edges (D-056 set 1–2 hours). Six phases, and for each one the
question the player is actually answering. **This table is the derivation
base for D-069's epoch timings and D-072's costs. A number in either that
cannot be traced to a row here is unjustified and should be challenged.**

| Phase | Minutes | Epoch | The decision being made |
|---|---|---|---|
| Opening | 0–8 | 1 | **Where**, not what. Site quality versus site safety. |
| Expansion | 8–22 | 1→2 | The first real fork: bank toward the next epoch, or field levy troops now. |
| First contact | 22–35 | 2 | Contest the middle or concede it. Which archetype to commit to. |
| Consolidation | 35–55 | 3 | Where your ground actually *is*, and what you are willing to lose. |
| Mid-war | 55–75 | 3→4 | Commit to a breakthrough, or grind. Siege is an investment that does not defend you. |
| Decision | 75–95 | 4→5 | The decisive battle, or bleed them. Signature troops arrive and are scarce. |

**Rationale — the gap this has to close is 4×, and it is in the opening.**
Measured: first contact at ~326 s (5.4 min) and `ai-ladder` deciding at
~325 s. This account puts first contact at ~22 min and the decision after
75. **The entire current match fits inside the row labelled "Opening."**
That is the honest size of the problem, and it is why D-056's tuning
could not reach the target and said so.

**Both figures predate D-066/D-067**, which raised building damage
sharply and imposed "one squad must fail, two must succeed" — a change
that pushes decidedly toward longer matches and was made for its own
reasons, not for this table. **Re-measure before treating the 4× as
current.** The direction of the gap is not in doubt; its size is, and a
number that has been overtaken is exactly what this project's own rules
say not to quote.

The stretch is not achieved by slowing anything down. It is achieved by
epoch 1 having no standing army in it at all (D-069): the opening is
genuinely economic because there is nothing else to spend on yet. D-056's
2026-08-04 amendment already established that the owner wants the slower
ramp — this extends the same direction on purpose rather than as a
side effect of gatherer crew size.

**Time in epoch, derived from the table:** E1 0–15, E2 15–33, E3 33–55,
E4 55–75, E5 75+. That is 15–22 minutes a rung, against a genre norm of
8–20. Deliberately at the top of the band: five rungs at genre-typical
pace produces a 50-minute match, not a 90-minute one.

**This entry also answers Q15's "is an army a ratchet or a running cost?"
— it is a running cost.** The phase-by-phase account is what the owner
said should decide it, and the account cannot support its own last three
rows without it:

- **Rows 4–6 need losing an army to hurt.** Without upkeep a defeat costs
  only the rebuild time, so there is no such thing as a decisive battle —
  which is the entire content of the "Decision" row.
- **Raiding must be strategy, not flavour.** The Northmen identity
  (D-071) is raiding economy; with no upkeep, killing workers slows an
  opponent's *rate* of buying and never the *size* of what they hold.
- **It is already measured.** D-056 found Legion banking a peak stockpile
  of **2,480 while pinned at the squad cap**. Accumulation with nowhere
  to go is exactly the endgame texture rows 5–6 need to not have.

**Shape:** a per-soldier food drain per second (`UnitDef.upkeep_food`,
scaled by `CivDef.upkeep_modifier`). When the wallet cannot pay, **morale
decays** rather than soldiers vanishing — this reuses D-019's existing
morale and routing machinery instead of inventing a second failure mode,
and a starving army breaking is the historically apt outcome.

**Upkeep replaces `squad_cap` as the binding constraint, and that resolves
Q15's "one mechanism too many" worry.** Both stay, with different jobs:
`squad_cap` reverts to being the **engineering ceiling** protecting
D-018's ~50 squads/player and D-020's tick budget, and should be set high
enough that it is not what a player feels. Upkeep is the **design**
constraint and is what actually bites. Q15 was right that two caps is one
too many — the fix is that only one of them is a cap you play against.

**Rejected alternatives:**
- *No upkeep, reach 90 minutes on epoch costs alone.* Rejected — it
  produces the D-056 endgame verbatim: two maxed armies and a stockpile
  nobody can spend.
- *Upkeep as a hard population cost (AoE-style houses).* Rejected — that
  is a second hard cap, which is the thing Q15 warned against, and it
  makes losing an army *free* again.
- *Unpaid upkeep kills soldiers.* Rejected — a death spiral with no
  player agency, and it fights D-024's casualty model for ownership of
  `alive`.

**Consequences:** the AI must learn to value an army it has to keep
paying for, which is a real change to `ai_player.gd` and not a tuning
pass. The HUD needs a net-income figure or upkeep is invisible until it
hurts. And every cost in D-072 is now a *rate* decision as well as a
price.

**Revisit trigger:** if telemetry (D-074) shows matches landing outside
60–120 minutes in the majority, this table is wrong and D-069's and
D-072's numbers must be re-derived from a corrected one — not patched
individually, which is precisely the failure D-056 recorded.

---
