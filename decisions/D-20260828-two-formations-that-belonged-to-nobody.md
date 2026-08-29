### D-20260828 · 2026-08-28 · Accepted — two formations that belonged to nobody

**Decision:** `shield_wall` and `testudo` are granted to shipped units
again, and the guard is widened from the one formation it named to the
whole class.

| formation | granted to | why |
|---|---|---|
| `shield_wall` | `emberdeep_levy`, `gildedreach_spearmen` | fortification, and flexibility |
| `testudo` | `emberdeep_heavy` | the siege approach |

And: **every formation that is not globally `offered` must be granted by
at least one shipped unit**, asserted over the roster rather than by name.

**Rationale.** Both formations ship as `/formations/*.tres` with full
directional stats, both are implemented, both are tested — and no player
could order either (#309). Two conditions must hold and neither did:
`FormationDef.offered` is `false` on both (correct — they are meant to be
granted, not offered), and **no shipped unit had a `formations` field at
all**; `grep -l '^formations' units/*.tres` matched nothing across all 39
defs.

**It is a regression, not an omission.**
`D-20260819-a-formation-is-a-fighting-style` shipped the mechanism WITH
grants — `legion_heavy` granted `testudo`, `northmen_spearmen` granted
`shield_wall`. `af9c3f4` (#191) replaced all 43 unit files, and the two
files that carried the grants went out with the civs that owned them.
`docs/status/rtw-battles.md` still says *"granted per unit through
UnitDef.formations"*, which had been false since that commit.

**Nothing failed because the caller exists.** Every part of the mechanism
is correct and covered: the directional stats are read by combat, the
client offers `offered() + def.formations`, and `server._handle_order_
formation` validates against offered-or-granted. A caller scan finds
nothing wrong, because **it is the grant that is missing and a grant is
data.** The D-055 family in its data half.

**Which units, and why these.** The numbers make the call rather than the
flavour:

- **`shield_wall`** is `taken_front 0.5`, `taken_rear 1.2`, `pace_scale
  0.6`. It halves damage from the front and raises it from behind — a
  formation for standing still and holding a line, useless on the move
  and punishing if flanked. That is the **fortification** half of
  emberdeep's declared thesis, and the ART already said so: emberdeep's
  levy is modelled as a shieldwarden with a round shield
  (`D-20260826-the-dwarf-roster-wears-supplied-models`).
- **`testudo`** is `missile_taken 0.35` against modest melee numbers and
  `pace_scale 0.5`. It is an **advance-under-fire** formation before it
  is a fighting one — crossing open ground to a wall, which is
  emberdeep's **siege** half. `emberdeep_heavy` carries the kite shield
  and the survivability to be the thing that does it.
- **`gildedreach_spearmen`** get `shield_wall` too. Gildedreach's axis is
  economy AND FLEXIBILITY, and free-city spearmen drilling a shield wall
  is the archetypal use of the thing.

**`testudo` ships with exactly ONE grantee, and that is accepted rather
than overlooked** (raised on #324 against an earlier draft of this entry,
which argued that "a second grantee stops a formation belonging to
exactly one unit"). That argument was a PROXY for a guard I had not yet
written, and it does not survive contact with two facts:

- **The guard now does the job the proxy was standing in for.** The old
  check named `shield_wall` alone, which is exactly why `testudo` went
  unreachable through #191 with nothing going red. It iterates every
  non-offered formation now, so `testudo` dropping to zero grantees fails
  the suite whether or not a second unit holds it. Protection against a
  roster rewrite is a test, not a spare grantee.
- **A second grantee cannot be justified from the shipped models at the
  same standard as the first.** `emberdeep_heavy`'s claim is specific:
  D-20260826 gives it the plate knight with a **kite shield**, and a
  testudo is a large shield locked overhead. The nearest candidate,
  `gildedreach_sellswords`, wears the generated `heavy_infantry` model —
  and `SoldierParams.shield` is a BOOLEAN. It does not distinguish a
  kite shield from `militia`'s round one, so "it has a shield" is not
  evidence it can form a testudo.

Granting a second one anyway would be granting a formation for the
guard's sake rather than the game's, which is the D-055 family inverted:
data added so a check has something to find. One grantee is honest, and
the check that matters is watching for zero.

Emberdeep gets one of each rather than both of one: the civ's thesis is
*fortification and siege*, and the two formations are precisely those two
verbs. Concentrating them there is expressing the civ, not hoarding.

**Rejected alternatives:**
- *`stoneblood_heavy` for the shield wall* (rejected — a shield wall is
  numbers and discipline, and stoneblood's heavy is 8 giants at 380 HP
  each. Stoneblood's identity is quality, which the unit already
  expresses; wedging a line formation onto eight individuals reads as
  filling a slot.)
- *Making both `offered`* (rejected — it deletes the mechanism.
  `D-20260819-a-formation-is-a-fighting-style` grants them per unit
  precisely so a formation can be part of a civ's identity, and a
  universally available shield wall is a global buff, not a style.)
- *Fixing this inside #305's manual work* (rejected there and correctly:
  the manual documents what the data does, and a design call does not
  belong in a documentation change. #309 was found by writing that page
  and filed rather than patched.)

**Consequences:** `test_granted_formations_exist_and_are_not_globally_
offered` — one of `main`'s 22 standing failures — goes green, and it now
enumerates the CLASS: any granted-only formation with no grantee fails,
by name. That is D-106's caveat applied to itself, since the old version
asked only about `shield_wall` and would have watched `testudo` disappear
in silence exactly as it did.

`docs/status/rtw-battles.md`'s sentence about workstream 9 is true again.

**Measured:** `just test-unit fighting_styles` — 6 tests, all passing.
Observed to fail first: removing the `testudo` grant reds the widened
guard by name (*"granted-only formation(s) that no shipped unit knows...:
testudo"*), which the old single-formation version did not catch.

**Revisit trigger:** if a civ is ever given a formation as its *whole*
mechanical identity, this becomes a balance question rather than a
data-integrity one, and the grants want re-deriving against
`just ai-ladder` rather than against the flavour text.

---
