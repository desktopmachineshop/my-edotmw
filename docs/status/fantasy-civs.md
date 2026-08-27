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
  tower's pair-rule carve-out was `TOWER_EXCEPTIONS` in
  `tests/test_buildings.gd` — **that list is gone as of 2026-08-27**
  (`D-20260827-a-buildings-hp-is-one-knob-and-the-rule-needs-two`, #152).
  It was not re-measured against the new roster after all: the pair rule
  was left asking all 22 troops, ten of which are cavalry, missile or
  light infiltrators, and 15 of 22 failed it on `main`. The pair rule is
  asked of LINE troops now (`levy`, `spearmen`, `heavy`, `sellswords`,
  derived from `UnitDef.archetype` and asserted against the roster), and
  the tower and town centre carry re-derived HP. **The lesson is the
  roster-wide one, not the siege one:** a hand-written list of unit ids
  survives a roster replacement looking perfectly plausible, and the
  same day it was written it was already asking horse archers to crack
  fortifications.
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
