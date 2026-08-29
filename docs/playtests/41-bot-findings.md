# Playtest #41 — walls, gates and the wall-top tier: bot findings

**Ticket:** [#41](https://github.com/desktopmachineshop/my-edotmw/issues/41) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`, native runtime.

## Verdict

**Mostly not bot-dischargeable, and the ticket says so itself:** *"This
feature's placement UX is explicitly only provable by playing — it lives in
`client.gd`, unreachable from GUT — and no AI uses walls, so no automated run
ever exercises it."* That is still true. Nothing in the estate builds a wall
without a human at the mouse: no scenario places one (`scenarios/*.tres` — only
`developed.tres` mentions a "garrison" and that is prose in its description),
no AI profile builds one, and `just ai-ladder` / `just test-load` / `just
test-scenario` never construct one.

What a bot **can** do here is inventory what the simulation-side rules are
already guarded by, and read the rules that nothing guards. That found one real
defect.

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | placement preview is honest; invalid cells refused | **human** | untouched — `client.gd` geometry |
| 2 | gates: friendly-pass, enemy-block, pathing prefers an open gate | **mixed** | **defect found**, see below |
| 3 | climb is the ONE way up; up and down both work | bot-observable | covered by tests, green |
| 4 | tier combat: melee cannot hit wall-top; ranged and tier-1 can | bot-observable | covered by tests, green |
| 5 | contested build sites behave per D-097 | **human** | needs an enemy squad marched onto a live site |
| 6 | no squad stranded when its wall dies under it | bot-observable | covered by tests, green |

## What was observed

### Criteria 3, 4 and 6 are genuinely guarded, and the guards pass

`tests/test_wall_top.gd` — 11 tests, all green in the full run:

- `test_a_squad_at_the_door_climbs_onto_the_tower`
- `test_a_squad_on_the_wrong_side_cannot_climb_directly`
- `test_a_squad_on_the_wrong_side_walks_around_to_the_door_and_climbs`
- `test_no_tower_anywhere_means_no_climb_at_all`
- `test_climbing_is_not_ownership_gated`
- `test_a_squad_can_descend_back_through_the_same_door`
- `test_tier_1_movement_walks_a_connected_run_and_stays_at_tier_1`
- `test_destroying_a_tower_drops_its_occupant_to_the_ground` (criterion 6)
- `test_a_melee_squad_cannot_hit_a_tier_1_defender_even_when_adjacent` (criterion 4)
- `test_a_ranged_squad_can_hit_a_tier_1_defender` (criterion 4)
- `test_the_height_bonus_extends_a_defenders_effective_range` + its ground-level
  control (criterion 4's "range bonus is felt")

`tests/test_wall_run.gd` — 17 tests, all green, covering the D-096 continuous
placement arithmetic including **two seam cases**
(`test_a_run_across_the_seam_does_not_span_the_whole_map`,
`test_offsets_stay_sub_cell_even_across_the_seam`) and the wire round-trip of
facing and sub-cell offset.

So criteria 3, 4 and 6 are as discharged as they can be without a picture. What
the tests cannot say is whether the climb *feels* reliable at the mouse, which
is criterion 3's real content.

### Criterion 2 — an ally cannot pass a teammate's gate → **filed as [#210](https://github.com/desktopmachineshop/my-edotmw/issues/210)**

`server.gd`'s `_update_auto_gates()` decides whether a gate opens with a raw
owner comparison:

```gdscript
if _sim.owner_of(squad) == owner:
    near_owner = true
```

`SquadSim.are_allied()` exists and is what the rest of the simulation asks —
`combat.gd` calls it in five places, `client.gd` and `ai_player.gd` in more.
D-076 specifies the behaviour as *"auto-open when the owner's own squads are
near"* and **mentions teams nowhere in the entry**, while D-050 (allies share
vision) predates it. So this is a question that was never asked, not an
alternative that was rejected.

Third instance of the same family after #83 (the AI's targeting read "not mine"
as "hostile") and #82 (the minimap's two-colour squad scheme, correct when
written and never re-read after D-052). The tell is identical each time: a raw
owner comparison sitting in a codebase that compares teams everywhere else, with
nothing failing.

**No test would go red on a fix.** `test_wall_top.gd` and `test_wall_run.gd`
contain the word `gate` zero times between them; `test_buildings.gd` exercises
`set_gate_open`/`is_gate_open` as flags and never calls `_update_auto_gates`.

### Two related behaviours deliberately NOT filed

- **Climbing is not ownership-gated at all** — an enemy that fights to the door
  climbs exactly as the owner does. D-076 argues for this explicitly: *"A wall's
  tier-1 top is therefore a contestable objective, not an automatically safe
  one."* Considered position, not an oversight.
- **An open gate is open to everyone standing in it.** An enemy can follow the
  owner's squad through while it is open. Arguably what a physically open gate
  means. Named here so the next reader does not have to re-derive whether anyone
  noticed.

Both are worth the owner's eye during criterion 2, because they are exactly the
places where "correct rule" and "reads as a bug" can diverge.

## Bugs filed

- [#210](https://github.com/desktopmachineshop/my-edotmw/issues/210) — an ally's
  squad does not open a teammate's auto-gate.

## What remains, and it needs the owner's hands

Everything in criteria 1 and 5, and the *feel* half of 2, 3 and 6:

1. **Drag wall runs** — short, long, round corners, across a seam, through water
   / buildings / resource nodes. Watch the preview against what gets placed.
   D-096's arithmetic is well tested; whether the preview tells the truth about
   it is not, and cannot be.
2. **Contested build sites (D-097)** — start a wall segment, march an ENEMY
   squad onto the site before it finishes. Nothing automated reaches this: it
   needs two players and a mouse, or sandbox cheats to spawn a hostile squad.
3. **Gate pathing preference** — "pathing prefers an open gate over a long
   detour" is checkable in principle, but only once a wall exists, and no
   automated harness can build one.
4. **The allied case from #210**, once fixed: two allied players, one wall.

Sandbox mode is the right staging tool for all of these (`just quick-test`, the
cheats panel spawns an enemy squad without a second human). It needs a GUI
client on the owner's desktop, which this pass does not launch.

## A note on why no bot run was even attempted

Constructing a wall headlessly would mean writing a new scenario or a bespoke
harness that places `garrison_wall`/`wall_tower`/`gate` through
`BuildingSim.add_building`. That is buildable — but it would exercise the
simulation rules that `test_wall_top.gd` already covers, and it would still say
nothing about the placement UX, which is the half the ticket exists for. The
honest gap is the instrument, and the honest instrument is a person.
