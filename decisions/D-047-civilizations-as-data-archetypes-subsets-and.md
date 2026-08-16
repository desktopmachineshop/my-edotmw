### D-047 · 2026-08-02 · Accepted — civilizations as data: archetypes, subsets, and per-civ tuning
**Decision:** A **unit archetype** is the shared idea of a troop type —
spearmen, archers, cavalry. A **UnitDef is one civ's version of an
archetype**. Each civ fields a *subset* of the archetypes, and tunes the
ones it has differently, so the same type is not the same troops in two
armies.

The worked example that set this: one civ's spearmen may be cheap and
weak, fielded in numbers quickly, and lose to a smaller body of another
civ's stronger spearmen. Same archetype, different answer to it.

**Schema (logged against D-010):** `UnitDef` gains `archetype`. It
already has `civ`, and it already has per-unit `cost_*`, stats and
`bonus_vs`, so "cheap and weak" versus "expensive and strong" is
expressible today with no new machinery.

**A civ's roster is DERIVED, not listed.** A unit declares its `civ`;
which archetypes a civ fields is simply which unit files name it. Adding
a `.tres` gives that civ a type — no register to update, and no second
place for the roster to disagree with itself. `CivDef` therefore carries
only what is genuinely civ-level: display name, starting stockpile,
buildings, and declarative modifiers.

**Why `archetype` is not just `armour_class`.** `bonus_vs` already keys
on `armour_class` (infantry/cavalry/missile), which is why the counter
triangle survives new civs untouched — a civ added tomorrow is countered
correctly by every civ written before it, with no edits anywhere. That
was a genuinely lucky call in D-032. But `armour_class` has three values
and exists to answer "what beats this". `archetype` answers "what IS
this", and there are more archetypes than armour classes.

**What archetype buys, and it is the point of the whole design:** every
script can stay civ-agnostic. The client's train keybinds bind to
*archetype*, so one key trains your civ's spearmen whatever that civ
names them; production, UI grouping and AI all reason about archetypes.
Nothing needs to know a civ id — which is exactly what D-046 criterion 3
tests for.

**Mechanical asymmetry stays declarative**, per D-046's governing
constraint: a civ that wants a new mechanic adds a knob every civ has and
turns it. `CivDef`'s modifiers are that surface.

**Rejected alternatives:** One shared UnitDef per archetype plus per-civ
stat multipliers in `CivDef` (rejected — less duplication, but it hides
a unit's real numbers behind arithmetic in another file, and this project
optimises for stats being directly readable and editable as text; balance
work wants to see the number, not derive it). Per-civ unit ids referenced
directly in `bonus_vs` (rejected — every new civ would then require
editing every existing civ's counter lists, which is precisely the
"adding a civ is an engineering project" failure D-046 exists to
prevent).

**Consequences:** The existing four units become one civ's roster and
gain an `archetype`. The client's keybind table stops naming units and
starts naming archetypes. `UnitRoster` gains civ- and archetype-aware
lookups; `UnitRoster.first()` — currently "the default unit" — has to
become civ-relative or its callers do.

**Revisit trigger:** If two civs want the same archetype to differ
structurally rather than numerically — different formation behaviour, a
different number of attacks — that is the moment to check whether it is
still a parameter or has become a branch, and to amend D-046 honestly if
it has.

**Amended 2026-08-04 — this decision extends to epochs unchanged, and it
held under pressure.**

D-070 grows rosters by replacement, so an epoch unlocks new *archetypes*
rather than new versions of existing ones. That needs **no change here**:
`for_civ_archetype()` still returns one def per (civ, archetype) pair,
and epoch gating is one filter on top. A civ's roster stays DERIVED — a
`.tres` declares its `civ` and now its `epoch`, and nothing registers
anything.

Two consequences worth naming:

- **The archetype vocabulary grows from 8 to roughly 25–30.** This clause
  — "the client's train keybinds bind to *archetype*, so one key trains
  your civ's spearmen whatever that civ names them" — stops fitting on a
  keyboard. The binding stays archetype-based; the UI has to become
  epoch-scoped. Tracked as *unlock overload* in D-074.
- **The revisit trigger above did not fire, and was tested.** D-073's
  parameterisation pass put six civs' identities through it and found
  three claims with no knob. Two were cut and re-expressed numerically;
  one — "Byzantine builders raise fortifications faster" — named a
  genuine gap and became `CivDef.build_speed`, a knob every civ has.
  That is this decision working as designed rather than being defended.

The trigger stands unchanged for the future.

---
