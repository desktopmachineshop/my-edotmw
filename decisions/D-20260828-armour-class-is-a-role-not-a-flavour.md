### D-20260828 · 2026-08-28 · Accepted — armour class is a role, not a flavour

**Decision:** `armour_class` names what a unit **does**, not what it is
made of. `windmarch_levy`, `windmarch_general` and
`windmarch_skirmishers` move from `cavalry` to `infantry`, and a test
asserts one archetype maps to one armour class across every civ, with a
documented allow-list.

**Rationale.** `armour_class` is what the counter table reads:
`bonus_vs` maps an opponent's armour class to a damage multiplier
(D-032). Three archetypes carried a different class depending on which
civ fielded them — `general`, `levy` and `skirmishers` (#268) — and the
consequences were not deliberate:

- **One civ's levy was the only backbone unit in the game that any
  spearman countered**, at the table's strongest multiplier (1.5–1.6),
  while five civs' levies had one weak counter (archers at 1.3–1.4) and
  that one had two.
- **Its general was the only general anywhere a spearman countered** — a
  unit a player has exactly one of and cannot replace
  (`D-20260819-a-general-holds-the-line`).
- And `skirmishers` meant a **12-man 110 HP missile unit at reach 5.5**
  for one civ and a **24-man 48 HP melee unit at reach 1.9** for another,
  so cavalry's `bonus_vs {"missile"}` hit one and not the other. A player
  who learns "cavalry beat skirmishers" from one civ learns something
  false about the next.

The roster treated the field as FLAVOUR — centaurs are horses, so
everything they field is cavalry — and the counter table reads it as
ROLE. Only one can be right.

**Role wins, and the data had already decided.** The same civ's own
GATHERERS were classed `infantry`. So centaur-ness never actually
determined armour class anywhere; the flavour reading was already broken
by the roster that is supposed to embody it. What was left was a
mechanical penalty applied to one civ's line troops for a reason nothing
followed consistently.

It also lands on the civ #267 measures as **already losing levy-vs-levy 0
of 6 to every other civ's**. The one levy that was also counterable was
the weakest uncountered — which is the strongest argument that this was
an oversight rather than a balancing choice.

**The flavour is not lost; it was never in this field.** That civ is the
fastest army in the game by a clear margin (`move_speed` 6.2 against a
2.9–5.8 field) and its models are centaurs. Speed and art carry the
identity; the counter table carries the role. `windmarch_cavalry` and
`windmarch_bowriders` remain `cavalry`, because mounted melee and mounted
missile genuinely *are* the cavalry role.

**Rejected alternatives:**
- *Keep flavour and compensate the civ elsewhere* (rejected — it needs a
  compensating knob that does not exist (#270), and it leaves the build
  menu implying that `skirmishers` means one thing when it means two. A
  rule that needs an apology attached is the wrong rule.)
- *Class every skirmisher `missile`* (rejected — one of them swings at
  reach 1.9, so an anti-missile bonus would hit a melee unit. That is the
  same defect pointed the other way.)
- *Rename the archetypes instead of reclassifying* (deferred, and it is
  the real fix for `skirmishers` — see below.)

**Consequences:** every levy and every general in the game now sits in
one class, so no civ's backbone or command party takes a counter the
others do not. Spearmen lose a target they should not have had, which
makes `bonus_vs {"cavalry"}` slightly less useful in practice — it now
hits actual cavalry only, which is what it says.

**`skirmishers` stays on the allow-list, and that is a flag rather than a
fix.** Both defs are now classed by what they do, so the counter table is
correct; but one archetype label still covers a missile unit and a melee
one, which is a NAMING defect. Renaming touches build menus, AI archetype
lists, scenarios and tests, so it is filed separately rather than
smuggled into a balance change. The allow-list carries its reason, and a
test asserts each exception still varies — an allow-list that outlives
its reason is how a rule quietly stops applying.

**A second guard that does not depend on names at all:** a def classed
`missile` must be able to shoot (reach >= 3.0), and a def that shoots
must not be classed `infantry`. That covers the case the allow-list
excuses, and it is the check that would catch a future melee unit
labelled as a shooter whatever its archetype is called.

**Measured:** `just test-unit armour_class_is_a_role` — 5 tests.
Observed to fail first: reverting one levy to `cavalry` reds both the
archetype-consistency guard and the uniquely-counterable-backbone guard,
naming the classes it found.

**Revisit trigger:** if `bonus_vs` ever gains an entry keyed on something
other than armour class — a keyword, a tag — this decision is what says
the class is a role, and the new axis is where flavour belongs.

---
