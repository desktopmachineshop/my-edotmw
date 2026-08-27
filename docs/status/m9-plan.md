**M9 (epochs, six civs) is PLANNED but NOT BUILT** — the planning
milestone Q15 reserved ran on 2026-08-04 and produced **D-068 through
D-074**. Everything in them is design; **no code or `.tres` was written**,
so treat the schema in D-070 and D-010's log as a specification, never as
a description of the repo. The shape:

- **Five epochs, antiquity → high medieval** (D-069), each earning its
  rung by adding a new *verb* — settle, field, hold, break, decide — not
  bigger numbers. The ladder is shared by all civs and lives in
  `/epochs/*.tres`; **no script may name an epoch**, exactly as none may
  name a civ.
- **Six civs** (D-071): Legion, Northmen, Magyars, Byzantines,
  Carthaginians, Chinese — filling one seven-column frame, no two
  matching on more than one column.
- **Rosters grow by replacement** (D-070), which costs ~90–130 unit
  `.tres` at completion and is accepted knowingly.
- **An army becomes a running cost** (D-068). Per-soldier food upkeep;
  unpaid upkeep decays morale through D-019 rather than killing anyone.
  **`squad_cap` stops being a design lever and reverts to an engineering
  ceiling** for D-018/D-020 — upkeep is what a player should feel.
- **D-068 is the derivation base.** Its six-phase table is what D-069's
  timings and D-072's costs are derived from. The whole current match
  fits inside its first row.

**Of the two things M9 had to fix before it starts, one is done.** The
three `CivDef` knobs (`squad_cap_bonus`, `production_speed`,
`gather_speed`) were **read by nothing** — the fourth declared-and-unread instance, with two of the six
civ identities depending on them. They are wired up as of 2026-08-23
(`decisions/D-20260823-a-civs-knobs-are-read-by-the-simulation.md`, #158);
see `docs/status/civ-knobs.md`. Still outstanding: M6's unattributed
**40.8 → ~77 µs/squad** rise must be explained first, or M9's own
tick-budget numbers cannot be interpreted.

**A power budget now exists for balancing units** (D-072):
`V = sqrt(DPS × EHP)` against `RP = food + wood + 1.5×(gold + stone)`.
Run against the shipped roster it found that **militia leads on both
power and cost-efficiency for both civs**, and that `legion_heavy` has
lower DPS than `legion_militia` at 2.5× the cost. Two rules came out of
it: price must buy power, and no unit may lead on both axes within its
role.

**The CIV HALF of M9 is implemented as of 2026-08-26** (issue #191,
`D-20260818-fantasy-civs-supersede-the-historical-frame` Accepted): the
six fantasy civs ship as data and Legion/Northmen are deleted — see
`docs/status/fantasy-civs.md`, including the OPEN naming tension with the
entry below. The epoch ladder remains design-only.

**The setting is FANTASY and the ladder is FOUR rungs as of 2026-08-23**
(`decisions/D-20260823-fantasy-civs-on-a-four-epoch-ladder.md`, owner's
call) — medieval → imperial → modern → futuristic, superseding D-069's
five historical rungs and D-071's six historical civs. The seven-column
frame and its six mechanical AXES are kept verbatim (Dominion, Warhost,
Centaurs, Deepholds, Gilded, Sylvans replace Legion … Chinese by axis),
so every D-047 knob still has a civ asking for it; D-070, D-072, D-073
and D-074 stand. The entry carries a per-civ, per-epoch flavour table
that every art brief is written against. **Still nothing in code or
`.tres`** — the shipped `legion`/`northmen` ids stay until M9's first
slice renames them.

**The TECH TREE is designed as of 2026-08-27** (issue #206) — the full
tree is `docs/plans/tech-tree.md`, the mechanism is
`decisions/D-20260827-the-tree-is-the-ladder.md` and the research-site
building family is `decisions/D-20260827-a-research-site-is-a-building.md`.
The headline: **there is no age-up button.** Buildings research techs, an
epoch's `defining` techs are marked in the data, and completing them IS
the advance — which is what gives a rung an INTERIOR rather than one
payment moment. D-069's four advance totals are unchanged and each is now
split across a line of two techs (a shared trunk tech and the civ's own
arc tech); a test asserts the two halves still sum to D-069's row.

Three things to know before implementing it:

- **The rung COUNT is unresolved and deliberately cheap.** The design is
  written at five rungs with D-069's verbs, because the six civs that
  actually ship carry a five-stage arc table in `docs/plans/fantasy-civs.md`
  and issue #206 names those five verbs, while D-20260823's four-rung arc
  table is written for the Dominion/Warhost set that does NOT ship.
  Collapsing to four is deleting one `EpochDef` and moving a flag on ten
  files, with **no script change**, because no script names an epoch or a
  tech. That is the same open naming tension `docs/status/fantasy-civs.md`
  already records, and it is answered the same way: the shipped ids win
  until the owner says otherwise.
- **An effect never reaches a call site.** A tech resolves a per-player
  `UnitDef`, and `SquadSim._defs[squad]` already holds a def reference
  that `combat.gd`, `vision.gd`, `economy.gd` and `squad_sim.gd` read at
  roughly forty places — so **none of the forty changes**, and there is no
  forty-first that could forget to apply techs. `TechEffect.field` comes
  from a CLOSED list and an unknown field is a load error, because a tech
  whose effect is a typo would be the fifth declared-and-unread defect
  wearing a green verdict.
- **Three civs cannot research mobility at all and two cannot research
  siege**, because a stables or a forge is simply a `.tres` they do not
  have. Gildedreach is the only civ with both, which is its axis expressed
  as structure. The rule that keeps a hole from locking the ladder is that
  a rung's DEFINING line only ever sits on universal sites or the civ's
  own — the branches are what a missing building costs.
