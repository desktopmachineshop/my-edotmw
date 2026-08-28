### D-20260828 · 2026-08-28 · Accepted — morale is a fraction of the squad, not a count of men

**Decision:** `UnitDef.morale_loss_per_casualty` is **scaled by squad
size**. The authored number is now read through
`UnitDef.morale_loss_for(casualties)`, which multiplies it by
`MORALE_REFERENCE_SQUAD / squad_size`, and both of combat's readers go
through that accessor. `MORALE_REFERENCE_SQUAD` is **36** — the size the
shipped 4.0 was authored against.

**Rationale.** The field was a flat per-man number, 4.0 on every shipped
def but gravesworn's, while this roster runs from **3 men to 48**. Flat,
the casualties needed to break are a CONSTANT:

    need = (morale - rout_threshold) / morale_loss_per_casualty
         = (100 - 25) / 4.0 = 18.75

so **any squad of 18 men or fewer was annihilated before it could be
frightened** (#266). Not rarely — never, at any level of beating, from
any direction, with recovery disabled entirely. Reproduced here by
removing the scaling: **17 defs unroutable**, every one matching the
issue's figures.

That is 12 combat defs plus all five generals, and it includes **every
cavalry def in the game** and the whole of stoneblood's non-levy roster.

**What it costs beyond morale.** It made D-019 inert for over half the
combat roster, and with it everything built on top:
`D-20260819-morale-reads-the-fight`'s flank and rear multipliers, chain
shock from a breaking ally, the routed-defender damage multiplier, and
`D-20260819-a-general-holds-the-line`'s aura — which halves chain shock
for squads that could not be shocked.

**And it quietly erased a civ's identity.** #191 names *fearless* as the
deathless court's distinguishing feature and `tests/test_fearless.gd`
verifies it structurally — while twelve units belonging to the other five
civs shared it silently. #207's criterion 6 asks that fearless *read* as
fearless at the table; this is why it did not.

**Why scaling and not per-def numbers.** #266 offers both. Per-def values
are cheaper and purely `.tres`, and they **re-open the same trap the next
time a squad size moves** — which on this project is a certainty, since
the roster has been replaced once already. A rule cannot rot that way. It
is also 27 numbers against one, and the 27 would each need a derivation
nobody would write down.

**Why 36.** It is the size the shipped 4.0 was authored against — the old
legion/northmen line squad. So a 36-man squad behaves EXACTLY as it
always has, and every other size is normalised to it rather than to a
number chosen now. That makes this a normalisation rather than a retune,
and a test pins it.

The resulting breaking point is about **half the squad** (75 / (4 × 36) =
0.52) for an ordinary troop, whatever its size. A six-man breaker and a
forty-eight-man levy now break at comparable attrition, which is what
morale was always supposed to mean.

**Fearlessness survives for free**, and that is the neatest part: zero
times any scale is zero, so gravesworn's `morale_loss_per_casualty = 0`
needs no special case anywhere.

**Two legitimate exceptions, measured rather than excused:**

- **`gildedreach_sellswords`** break at 0.66 of themselves rather than
  0.52, because they ship `morale = 120`. Elite mercenaries being
  steadier is the knob doing its job.
- **Generals** break at 0.99 — `morale 160` against `rout_threshold 18`
  in an eight-man command party. That is
  `D-20260819-a-general-holds-the-line` working: a general's DEATH is the
  morale event, and one that fled at ordinary attrition would undermine
  the aura it exists to project. They are excluded from the
  spread test by their own `is_general` field, and a separate test
  asserts they are the ONLY units above 0.75 — so a future def that
  quietly acquires general-like steadfastness without being a general
  fails rather than hiding inside the exclusion.

**Rejected alternatives:**
- *Per-def `morale_loss_per_casualty`* (rejected — see above: it fixes
  today's roster and rebuilds the trap.)
- *Lowering `rout_threshold` instead* (rejected — it moves the same
  constant from one end to the other and still scales with nothing. A
  4-man engine would need a threshold of 85 to break at all, which is
  not a number anybody could reason about.)
- *Making the loss purely fractional and dropping the authored field*
  (rejected — `morale_loss_per_casualty` is how gravesworn expresses
  fearlessness and how a future civ would express brittleness. The field
  keeps its meaning; only its scale is normalised.)

**Consequences: this changes every rout in the game.** Small squads can
now break at all, and large ones break slightly earlier than they did
(a 30-man levy at 0.52 of itself rather than 0.62). **Every ladder and
load-test number taken before this was measured against a game where
morale did nothing for half the roster**, and the standing rules apply
with a fourth clause: quote a result with its cap, its squad count, its
roster, and which side of this change it came from.

It also stacks with `D-20260828-a-fortification-frightens-men` (#218, PR
#257), which is a RATE fix to the same system — recovery outrunning the
kill rate — where this is a REACHABILITY fix in the totals. They are
independent and both were needed: with recovery suppressed to zero, a
14-man cavalry squad losing all 14 men still shed only 56 morale against
a 75-point gap. If both land, re-take any morale-sensitive measurement
rather than assuming either one's numbers survive.

**Measured:** `just test-unit rout_is_reachable` — 8 tests. Observed to
fail first by removing the scaling: 17 defs reported unroutable by name,
matching #266's table.

**Revisit trigger:** if a unit ever ships with a squad size far outside
the 3–48 band this normalises across — a one-man hero, a hundred-man
horde — check the breaking fraction before shipping it, because the
reference makes the FRACTION constant and not the *feel*: one casualty in
a three-man squad is 33% of it, and a rule that is right for a levy may
be absurd there.

---
