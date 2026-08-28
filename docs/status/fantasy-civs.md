**The six fantasy civs are IMPLEMENTED and Legion and Northmen are gone**
(issue #191, `D-20260818-fantasy-civs-supersede-the-historical-frame`
flipped to Accepted 2026-08-26). `civs/` holds stoneblood (giant-kin,
quality), gravesworn (the deathless court, quantity), thornwood (sylvan
elves, ranged attrition), windmarch (centaur clans, mobility),
gildedreach (free cities, economy & flexibility) and emberdeep (deep-hold
dwarves, fortification & siege). The rosters are the design branch's
stat blocks verbatim (`docs/plans/fantasy-civs.md` — 27 combat units,
V/RP-screened), extended to 39 defs by the per-civ gatherers and generals
that D-20260823-the-opening-is-a-crew-and-a-general made mandatory after
the plan was written.

Six things to know before touching any of it:

- **The archetype vocabulary moved.** `militia` is `levy` now, and the
  roster adds `heavy`, `breaker`, `shades`, `greatbow`, `bowriders`,
  `sellswords`, `engine`, `ram`, `bombard`. `barracks.produces` lists the
  union; a civ that does not field an archetype simply never resolves it
  (D-047), which is how the build menu already coped with legion having
  no cavalry. The sandbox spawn picker lists every archetype in the
  roster rather than the five hotkeyed ones, because most of the new
  roster is fieldable by exactly one civ.
- **"Fearless" is verified, not assumed** (`tests/test_fearless.gd`,
  #191's flagged question). Gravesworn ships `rout_threshold 0` +
  `morale_loss_per_casualty 0` on every def, and the tests pin the
  structural facts that make that mean "never routs": morale is clamped
  at 0 on both subtraction paths and every rout comparison is strict.
  Observed to fail at threshold 0.1 before being trusted. A fixture
  lesson worth keeping: a hammer that wipes a squad in ONE round proves
  nothing about routing — `alive <= 0` returns before the rout check —
  and the ally-separation pass can shove a chain-shock witness fixture
  apart; both vacuities were caught by the tests' own setup guards.
- **The naming tension with D-20260823's four-epoch entry is OPEN, on
  purpose.** That entry names the same six axes Dominion / Warhost /
  Centaurs / Deepholds / Gilded / Sylvans. #191 is the implementation
  order and names this set, so this set ships; renaming is a mechanical
  id sweep whenever the owner settles it. The epoch LADDER is untouched
  — nothing here names an epoch.
- **Emberdeep wears the supplied dwarf models**
  (D-20260826-the-dwarf-roster-wears-supplied-models): levy = the
  shieldwarden body (axe + round shield), heavy = the plate knight
  (spear + kite shield), archers = the kettle-helm crossbow body,
  general = the thane (banner + runed axe) with a mixed retinue, bombard
  = the wooden gun with three tenders in the crossbow body
  (D-20260826-a-squad-wears-more-than-one-model), and its gatherers are
  the dwarf miner with his tools. Gildedreach borrows the two surviving
  authored HUMAN models (sellswords = heavy_infantry, outriders =
  cavalry). Everything else is the primitive tier — including the other
  five civs' GATHERERS, by the owner's explicit call (2026-08-26): the
  dwarf miner stops standing in for every civ's crews the moment the civ
  it belongs to exists, and a capsule crew is the designed degradation
  (D-064) until each civ's own body arrives. This supersedes
  D-20260824's "the dwarf is the gatherer model for every civ", whose
  own revisit trigger was the fantasy pivot.
- **D-067's building-rush rules are re-scoped to TROOPS.** Siege units
  (breaker, engine, ram, bombard) are excluded from both the solo and
  the pair rule: cracking a defended building alone is their design
  brief — the Ember Bombard's identity is outranging the tower. The
  tower's pair-rule carve-out list is `TOWER_EXCEPTIONS` in
  `tests/test_buildings.gd`, re-measured against the new roster.
- **Every ladder and load-test number taken before this is measured
  against civs that no longer exist.** The standing quote-it-with-its-cap
  and quote-it-with-its-squad-count rules apply with a third clause:
  quote which ROSTER. `test-load`'s CIVS_FIELDED gate is roster-agnostic
  (it parses the marker, not names) and unchanged.

**Deliberately not done:** epochs (M9's ladder is still design);
per-civ walls/buildings; any strength ordering between the six — that is
`just ai-ladder`'s job now that they exist, and the first run of it on
this roster is the number to take next; and bodies for the other five
civs — the supplied stylised ELF in the owner's batch is presumably a
thornwood body and waits for a rig rather than shipping as a second
T-posing placeholder.

**The levies are sidegrades now, and the reason they could not be one by
tuning is the interesting part**
(`D-20260828-a-levy-is-a-sidegrade-and-a-duel-is-not-the-test`, #267,
2026-08-28). Every civ's levy was strictly ranked — as filed, 14 of 15
pairings 6-0 with 13 of them leaving no survivors, so the civ you picked
decided the fight. It is **1 of 15 now, and 13 pairings are dead even**.

Five things to know before touching a levy:

- **#267's own numbers were stale, and its named mechanism was the wrong
  one.** Re-measured on the #334 base (armour class is a role) the sweep
  was already down to 2 of 15 — reclassifying windmarch's levy from
  `cavalry` to `infantry` fixed most of it, because the counter triangle
  had been firing on a levy for being flavoured as horse. And the
  frontage cap #267 blames is real but mild: measured off
  `Engagement.contact_count`, a levy gets **100% of its men into contact
  up to n=40, 92% at n=48**.
- **A 5% edge in squad power is a clean sweep**, measured in a mirror
  with a single field changed: `damage` x1.10 scores 12-0. `V² =
  n²·(damage/interval)·health` is exactly Lanchester's square-law
  strength for a fight where everyone is engaged, and it compounds — the
  side one rounding puts a man ahead pulls away and never comes back.
  **So levies cannot be made sidegrades by moving numbers closer
  together**; that only makes the sweep noisier. They are held inside a
  band on BOTH power and power-per-resource (3.6% and 2.6%), and their
  identity lives on axes a duel cannot see.
- **No other field in `UnitDef` is worth 8% of V.** Reach 1.9 -> 2.6 is
  worth +21 men, and an 8% damage cut wipes that out completely (0-8, and
  the three reach settings return identical margins). `move_speed` scores
  6-6 doubled — correctly, since it is spent choosing whether to fight.
  That is why reach and speed are safe to carry FLAVOUR (a dwarf's hand
  axe is short, a sylvan glaive long) and useless as balance levers.
- **Quantity means bodies per squad, not a discount.** Gravesworn's levy
  went 32 -> 47 food: at 32 it led power-per-resource by 50%, which is
  not an identity. It keeps its 48 men, its `sparse` block and its
  fearlessness. **Every levy cost moved** (windmarch 38 -> 47, thornwood
  40 -> 46, stoneblood 50 -> 46, emberdeep 48 -> 46, gildedreach 45 ->
  46), so any ladder or load-test timing taken before this was measured
  against a different price list — this page's own "quote which ROSTER"
  rule. The opening is unaffected: a town hall costs WOOD.
- **One sweep survives on purpose and it is a counter, not a tier.**
  Stoneblood's narrow, very tough block beats gravesworn's sparse horde
  12-0 at **any** power — measured at V 662 and V 734 it is 0-12 both
  times, while that same increase sweeps the other four 12-0. It is a
  shape matchup, so raising gravesworn cannot fix it and was not tried.

**The structural cause is filed as #346 and is NOT fixed here.** While a
5% edge sweeps, "equal power, difference elsewhere" is forced rather than
chosen, and no unit anywhere in the roster can carry genuinely trading
strengths. Damping it is an amendment to D-024 and the owner's call.

**A/B on the same host, 4 bots 120 s, driven manually** (`test-load`
cannot start a server under `EDOTMW_RUNTIME=native` — #223): base
**209.15 µs/squad at 33 squads**, branch **213.31 at 33 squads**, combat
93.73 vs 94.63, 0 desyncs and 0 dropped ticks both sides. The absolutes
are high because the host was loaded throughout; the delta is the
trustworthy column, and it is noise.
