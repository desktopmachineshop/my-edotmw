# D-20260819 · A charge is spent on its impact

**Status:** ACCEPTED — workstream 6 of
D-20260818-battle-quality-outranks-player-count (exit criterion 6).
**Relates to:** D-034 (attack-move — a charge is its sprinting cousin),
D-20260819-only-men-in-contact-fight (the impact multiplies contact
damage), D-20260819-morale-reads-the-fight (a rear charge compounds with
rear shock by construction), D-024 (still squad-level, still seeded).

## Decision

A charge is a player order (`C2S_ORDER_CHARGE`, carried like
attack-move): the squad closes at `CHARGE_SPEED_MULT` (×1.5) its speed
and its FIRST landed attack while the charge is live deals
`CHARGE_IMPACT_MULT` (×3) damage. Then the charge is spent. Squad-level
state throughout (`_charge_until`, a tick deadline — squads may have
state, D-024's own note), nothing per-soldier, nothing on the wire but
the order itself: the speed reaches clients through the curves it
changes, and the impact through the casualty events it causes.

Five rules, each closing an exploit or a misfire found at design time:

1. **A charge is spent ON THE BLOW, not on contact.** Attack-move halts
   on contact (D-034) and the halt clears orders — run first-contact
   through that unmodified and the flag dies one line before the attack
   that was meant to carry it. A charging squad therefore skips the
   halt until its attack actually fires; the same tick it lands the
   impact, it halts and the charge is spent. One blow by construction —
   no double-impact, no impact lost to an attack-interval coincidence.
2. **Point-blank charges are attack-moves.** An order from closer than
   `MIN_CHARGE_CELLS` (3) gets no flag — otherwise re-ordering a charge
   against the man in front of you is a free ×3 every click.
3. **Charges expire.** `CHARGE_TICKS` (80 — eight seconds of sprint)
   after the order, the flag drops and the curve rebuilds at walking
   speed: an unexpired flag would make "charge" the strictly better
   move order everywhere. The real price of sprinting is fatigue,
   which is workstream 11; the deadline is the interim guard and says
   so here.
4. **A plain move or a player stop cancels a charge** — the sim's own
   halt-on-impact is the only stop that spends rather than cancels.
5. **Nothing is cavalry-cased.** A knight's charge hits harder than a
   spearman's because his `damage`, `bonus_vs` and `move_speed` say so
   through the same multiplier — per-class branches are how D-047 dies.

## What compounds, for free

The impact multiplies the CONTACT damage, so a wide charge hits with
more men; the casualties it causes carry the ASPECT multiplier, so a
rear charge is ×3 damage × ×2.5 morale — and the rout it causes chains.
Nothing here reads another mechanic's internals; the terms stack because
each reads the same replicated state.

## The picture criterion, honestly

Exit criterion 6 asks that a cavalry charge "visibly reads" — and the
visible half of a charge is SPEED, which no still frame can show. The
clip rate already follows curve speed, so a charging squad runs on
screen with no new work; the judgement is the owner's next playtest,
recorded against this entry, not a screenshot gate pretending motion.

## Rejected alternatives

- **Impact scaled by measured approach speed.** Honest-sounding, but
  curve speed is piecewise-constant — the measurement would be of the
  flag with extra steps.
- **A charge morale-shock term of its own.** The casualties already
  carry aspect shock; a second terror term would double-count exactly
  where charges already break lines. Revisit only if playtests read
  frontal charges as toothless.
- **Replicating the charging flag.** No client decision needs it: speed
  arrives in the curves, the impact in the events.

## Revisit trigger

Workstream 11 (fatigue) replaces rule 3's deadline with a real cost —
this entry gets the amendment then. If playtests show charge-cancel
micro (order, cancel, re-order to reset the deadline) mattering, the
deadline moves to a cooldown; both are one constant.
