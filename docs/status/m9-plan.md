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

**Two things M9 must fix before it starts, both found during planning:**
three `CivDef` knobs (`squad_cap_bonus`, `production_speed`,
`gather_speed`) are shipped with non-default values and **read by
nothing** — the fourth declared-and-unread instance, and two of the six
civ identities depend on them. And M6's unattributed **40.8 → ~77
µs/squad** rise must be explained first, or M9's own tick-budget numbers
cannot be interpreted.

**A power budget now exists for balancing units** (D-072):
`V = sqrt(DPS × EHP)` against `RP = food + wood + 1.5×(gold + stone)`.
Run against the shipped roster it found that **militia leads on both
power and cost-efficiency for both civs**, and that `legion_heavy` has
lower DPS than `legion_militia` at 2.5× the cost. Two rules came out of
it: price must buy power, and no unit may lead on both axes within its
role.
