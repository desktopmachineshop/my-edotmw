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
  `sellswords`, `engine`, `ram`, `bombard` — and `harriers` since
  2026-08-28 (#332), which was `skirmishers` until that one word covered
  a javelin unit reaching 5.5 and a light melee unit reaching 1.9. The
  design already called the melee one **Harriers** and its
  `display_name` always said so; only the archetype and the def id
  lagged. `skirmishers` keeps its classical meaning — the missile one. `barracks.produces` lists the
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

**And three of the roster's own rules were shipped absent, found only by
the suite going red** (`D-20260828-a-guard-is-written-in-a-vocabulary-that-moves`,
#215 with duplicates #202/#203/#211/#212, 2026-08-28). #191 landed the
data and did not land the rest; `just test-unit` was red on `main` for a
week and read as noise:

- **`emberdeep_ram` could not attack anything.** `attack_range` 1.5
  against a hex width of 1.73 floors to a radius of ZERO cells, so the
  one unit whose design brief is cracking a building geometrically could
  not reach one. It is 1.9 now — the roster's own melee reach, and still
  the shortest in it. `docs/plans/fantasy-civs.md` specifies 1.5 and the
  PLAN is what is wrong. **The schema default is 1.5 too**, so a new
  `UnitDef` that does not set the field ships unable to fight; filed, not
  fixed here.
- **Nobody knew the shield wall.** #191 dropped every `formations` grant,
  so D-20260819's two specials shipped reachable by no unit in the game.
  Granted again by that decision's own rule — spearmen know the wall
  (`gildedreach_spearmen`, `gravesworn_spearmen`) and the fortification
  civ's heavy knows it too (`emberdeep_heavy`, the **Shieldwall
  Vanguard**, whose design text is "the formation IS the silhouette");
  `stoneblood_heavy` takes the testudo. A grant is opt-in — a client
  button and a server allowance — so no default shape moved and PR #222's
  re-derived D-067 numbers are undisturbed.
- **The six per-civ gatherers were one stat block copied six times.**
  Naming was done and differentiating was not, which is the shape this
  project keeps rediscovering wearing a passing test (there IS a test
  that each crew names its own civ, and it passed throughout). Each crew
  now sits on its civ's axis — stoneblood few/tough, gravesworn ten
  cheap diggers, windmarch fast with the biggest load, gildedreach the
  best rate, emberdeep slow and hard, thornwood the reference — with
  **steady-state throughput held to -4.6%/+9.5%** of what shipped, so
  this differentiates six crews without re-balancing six economies. Both
  shipped bands were respected rather than discovered afterwards: food
  per head inside (1, 6) and a tree cleared in 45-75 s. The table is in
  the decision.

**Timings tuned against the old crews are stale**, per the standing rule
— but only just: the throughput band is narrow on purpose, and squad
sizes moved (5-10 against a flat 7), so an opening's LOOK changes more
than its clock.

**The art question is decided, owner ratified 2026-08-29 (#191):
`model_id` keys by ARCHETYPE by default and gains a PER-CIV OVERRIDE.**
Not keyed by civ outright — that would make the shipped fallback the
exception rather than the rule, and the fallback is what lets five civs
field a primitive-tier crew today without anything failing (D-064). An
override is additive: a civ with no authored body resolves exactly as it
does now.

The schema change and the four-civ art queue are **filed for cycle 2 and
deliberately not started**, because the same ratification held the
feature freeze. So the sentence above this one — that the supplied elf
presumably belongs to the sylvan civ and waits for a rig — is still the
state of the art queue; what changed is that there is now an agreed way
to attach a body to a civ when one exists.

**The BUILDING half of that shape shipped on 2026-08-30 for emberdeep**
(`D-20260830-a-building-wears-a-civs-own-body`, owner-directed): the
supplied dwarf town hall and storehouse are authored sources now,
imported like the ships (textures into `COLOR_0`, scaled to the neutral
originals' heights) but UNDECIMATED at ~19k triangles under an
owner-set 20,000 ceiling — a building bakes no VAT and a match holds a
handful of them, and both decimation levels tried first (2,500, 6,000)
visibly damaged the thin timber parts. `buildings/
town_centre.tres` / `buildings/storehouse.tres` name them in a new
`BuildingDef.model_overrides` dictionary. Resolution is ONE applied
function (`BuildingDef.model_for(civ)`, the civ-knobs rule) read at
`client.gd`'s one building-mesh site, keyed by the owner's PUBLIC civ
(D-102) — nothing on the wire, nothing simulation-side. A per-civ
town-centre DEF was rejected: `defs_for_civ` shadows nothing, so it
would be offered beside the neutral hall, and it would be a second
`consumes_builder` def, which `test_opening.gd` pins at one by design.
The units half of #413 is untouched. The imported bodies carry no
owner-colour mask (the ships' trade) — the minimap and selection ring
carry attribution until somebody paints vertex alpha into the
`.blend`s.

**And the BUILD PREVIEW wears that body too, since 2026-08-31**
(`D-20260831-a-placement-ghost-is-the-building-it-will-build`, owner's
call): the ghost is the model it will raise, semi-transparent and tinted
by whether the ground will take it, resolved through the same
`model_for` against the viewing player's civ. It is its own shader
rather than a `StandardMaterial3D`, because COLOR_0's alpha is the
owner-colour MASK (D-052) and the standard shader multiplies vertex
alpha into ALBEDO — a ghost built that way loses its walls and keeps its
roof, with nothing failing. `just test-client SECONDS BOTS HOLD
RESOLUTION <def_id>` is the instrument, and it exists because a preview
only lives while somebody holds a build order, which no capture had ever
done — the fifth time that framing has had to be aimed on purpose.

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
