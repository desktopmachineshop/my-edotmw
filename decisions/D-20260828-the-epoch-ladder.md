### D-20260828-the-epoch-ladder · 2026-08-28 · Accepted — THE epoch ladder: five rungs, and the defining line is the gate

**This is the single description of the ladder.** Three entries described
three different ones and the newest of them lived in an issue rather than
a file, which is this project's own rule broken in the place it matters
most — `decisions/` is supposed to be what is being built. Issue #278,
from the gap assessment's §1.3 (C2).

**Supersedes, on the LADDER only:**

- **D-069** entirely — five historical rungs (antiquity → high medieval)
  and the `EpochDef` advance gate carrying `cost_*` and `research_time`.
  Its *verbs* survive verbatim and are the one part of it this entry does
  not touch.
- **`D-20260823-fantasy-civs-on-a-four-epoch-ladder`, its ladder half** —
  four rungs medieval → imperial → modern → futuristic, and the
  re-derived four-gate cost table. **Its CIV half is untouched here and
  is not this entry's business**; the civ set in force is
  `D-20260818-fantasy-civs-supersede-the-historical-frame` (Accepted
  2026-08-26), and the naming tension between the two is recorded as open
  in `docs/status/fantasy-civs.md`.
- **`D-20260827-the-tree-is-the-ladder`, its ladder half** — the rung
  count, the verbs, the per-civ names and the advance-cost table move
  here. **That entry keeps the tech MECHANISM** — `TechDef`,
  `TechEffect`, the closed effect vocabulary, per-player def resolution,
  research sites, fog. Code citing it for those things is citing it
  correctly; code asking *what the ladder is* cites this.

---

#### The ladder

**Five rungs. Every player climbs the same five, in the same order, and
the ladder is shared by every civ** — D-069's rule, kept for D-069's
reason: it is what makes "who is ahead" one legible integer to a player,
to an opponent and to the AI.

| # | Epoch | Verb | The epoch is when… |
|---|---|---|---|
| 1 | **The Founding** | settle | …a place becomes possible. |
| 2 | **The Mustering** | field | …a standing army becomes possible; the counter triangle arrives whole. |
| 3 | **The Holding** | hold | …ground you keep becomes possible — stone, sight, and the speed to cover it. |
| 4 | **The Breaking** | break | …fortified ground becomes attackable again. |
| 5 | **The Reckoning** | decide | …scarce, decisive troops become possible. |

**D-069's new-verb filter is retained and is the rule for ever adding or
removing a rung:** a rung must name a new *verb*, not a bigger number. A
rung whose honest one-line justification is "the stats go up" is a stat
bump and belongs merged into its neighbour.

Each civ names its own rungs (`CivDef.epoch_names`), taken from its
five-stage development arc in `docs/plans/fantasy-civs.md` Part 2. Those
strings are flavour — nothing mechanical reads them — but they are the
thing a player actually sees on advancing, and a rung with no name in the
civ's own words is a rung that reads as "Epoch 3".

#### The gate: completing the defining line IS the age-up

**There is no age-up button.** Each rung's `defining` techs are marked in
`/techs/*.tres`; hold every defining LINE of epoch *N* and you are in
epoch *N+1*, at the instant the last one completes.

D-069's gate was a payment. A payment has exactly one decision in it —
*now or later* — and D-056's finding is that the game's problem is not
that its one decision comes too early, it is that **there is no
progression at all**, so "after roughly three minutes there is nothing to
do but fight". A button adds one interesting moment per rung and leaves
the other fourteen minutes as empty as they were. A marked line through a
tree costs the same resources and gives a rung an *interior*.

**A rung's defining line is two techs**: one shared trunk tech every civ
researches, and one that is the civ's own arc line in its own words. The
full tree is `docs/plans/tech-tree.md`.

**Epoch 5 has no defining line**, because nothing is above it.

**A defining tech may only be researched at a site every civ walking that
rung actually has.** Three civs have no stables and two no forge
(`D-20260827-a-research-site-is-a-building`), and a defining tech behind a
building a civ lacks is that civ locked out of the ladder by its own
identity — asymmetry is the point, a permanent stop is a bug with a story
attached. `tests/test_tech_tree.gd` asserts it for every civ and every
rung.

#### The advance costs are D-069's, unchanged, split across each line

D-069 derived these from D-068's phase table; this entry re-derives
nothing and splits each row across its rung's two techs.

| Advance | food | wood | gold | stone | research |
|---|---|---|---|---|---|
| 1→2 | 500 | 300 | — | — | 90 s |
| 2→3 | 800 | 500 | 200 | — | 120 s |
| 3→4 | 1200 | 800 | 500 | — | 150 s |
| 4→5 | 1800 | 1200 | 900 | 400 | 180 s |

`tests/test_tech_tree.gd` asserts the two halves still sum to the row, for
every civ. Without that the halves drift until the total is a number
nobody chose — which is exactly how a derivation base stops being one.

**Provisional in their VALUES, settled in their SHAPE.** What they are
worth in minutes of a player's income is
`D-20260828-the-phase-table-has-numbers` (#281), which is the derivation
base D-068 was always supposed to be and, until that entry, was not.

#### Epoch gates TECHS; techs gate everything else

One gate per question. `TechDef.epoch` is the earliest rung at which a
tech may be *started*; `UnitDef.requires_tech` and
`BuildingDef.requires_tech` name a tech line and nothing else.

**D-070's proposed `UnitDef.epoch` and `BuildingDef.epoch` are
deliberately NOT in the schema.** Two gates on one question is one too
many and the pair would be free to disagree — the D-058/D-065 family,
which this project has now paid for four times. It also matters for
*design* rather than only for hygiene: an epoch gate is not a decision,
because everybody climbs. A tech gate is, because it is bought instead of
troops, which is why every civ's signature unit sits behind one.

---

#### The rung COUNT, stated plainly as an open owner call

**Five ships.** D-069 said five, `D-20260823` said four, and issue #206
named D-069's five verbs. The tie-break used here is **which civs
actually ship**: `/civs` holds the six of `docs/plans/fantasy-civs.md`,
whose own arc table is five-stage and is the only per-civ epoch content
that exists for them. D-20260823's four-rung arc table is written for the
Dominion / Warhost / Centaurs / Deepholds / Gilded / Sylvans set, **which
does not ship** — designing giant-kin and sylvan elves a *futuristic*
rung would be inventing content for civs on the strength of a table
written for different ones.

**The count is DATA, and that is what makes this cheap to overturn.**
Epochs are `/epochs/*.tres` and the line is a `defining` flag on a
`TechDef`. Collapsing to four is deleting one `EpochDef`, merging two
rungs and moving a flag on ten files, with **no script change at all**,
because no script names an epoch or a tech and a test forbids it. If the
owner prefers four, that is a data edit and not a redesign; this
paragraph is the reason it was built that way.

---

#### Rejected alternatives

- **Leave the three entries standing and let readers work out which is
  current.** Rejected — it is the state that produced this ticket. A
  reader arriving at D-069 finds a confident, fully specified ladder that
  is not the one in the repo.
- **Amend D-069 in place.** Rejected by `decisions/README.md` rule 3:
  historical IDs are frozen and code cites them. Superseding keeps the
  rationale trail; editing destroys it.
- **Fold the ladder into `D-20260827-the-tree-is-the-ladder` and leave
  one entry for both.** Rejected — that entry is already the largest in
  the directory and the two questions have different lifetimes. The rung
  count is an open owner call that may move next week; the effect
  vocabulary and the per-player def resolution are architecture that
  should not. Superseding one must not force a re-read of the other.
- **A separate `EpochDef.requires` prerequisite list, so the ladder's
  shape lives on the epochs rather than on the techs.** Rejected — it is
  a second description of the same edge, and the pair would disagree the
  first time somebody moved a `defining` flag without editing the epoch.

#### Consequences

- **`decisions/` now answers "what is the ladder" in one file.** Code
  that asks that question cites this ID: `epoch_def.gd`,
  `TechRoster.max_epoch` / `defining_lines`, `ResearchState.epoch_of`,
  `TechDef.epoch` / `defining`, and `tests/test_tech_tree.gd`'s ladder
  half.
- **D-069 and D-20260823 keep their status lines and gain a pointer.**
  Neither is edited beyond that, per rule 3.
- **The rung count remains the one open thing**, and it is open in a file
  now rather than in an argument between three files.

#### Revisit trigger

D-069's, unchanged and now the only copy of it: **any rung that telemetry
shows is entered and left without the player's behaviour changing is a
stat bump, not an epoch, and merges into its neighbour.** And this
entry's own: **the owner settling the rung count**, which is a data edit
plus a status-doc line, not a new decision.

---
