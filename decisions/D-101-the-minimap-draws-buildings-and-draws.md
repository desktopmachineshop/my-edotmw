### D-101 · 2026-08-16 · Accepted — the minimap draws buildings, and draws them from knowledge rather than from sight
**Decision:** The minimap paints every building a client **knows about**,
in its owner's colour (D-052), **unconditional on current visibility**,
sized from data:

1. **A pass over `ClientState.buildings` exists.** Destroyed buildings
   are dropped; everything else is painted, the player's own included.
2. **Not gated on vision, and not gated on `_explored`.** Resource nodes
   are gated (a node is terrain, and terrain you have never walked past
   is unknown); buildings are not, because a client only ever holds a
   building because the server showed it one (D-030), and *knowing* is
   the state being drawn.
3. **Size comes from `BuildingDef.no_build_radius`**, never from a list
   of ids (D-010): a building claiming a settlement's worth of ground
   (`>= 4`, which in the shipped data is the town centre alone) draws
   3 cells across, everything else 2 — the same as a squad dot.
4. **Buildings paint before squads**, so an army defending a base is
   drawn on top of it.
5. **The decision half lives in `minimap_paint.gd`**, all-static and
   pure, the same split as `render_cull.gd`, `selection_pick.gd`,
   `hud_layout.gd` and `ground_cover.gd`. `client.gd` keeps the image
   work.

**Rationale:** `_update_minimap` drew terrain, squad dots and resource
nodes and made **no pass over `_state.buildings` at all**. Town centres,
barracks, towers, storehouses and walls have never appeared on the
minimap, so it could not answer "where is my base" — the question a
minimap is asked most often in an RTS — and, worse, **persistent-explored
building fog (D-030) had no representation anywhere in the interface**.

That second consequence is what makes this a design decision rather than
a missing feature. D-025 and D-030 split knowledge deliberately: a squad
ghosts and then goes, because it moves while unseen and its position goes
stale; a building is kept forever, frozen at last-known, because it does
not move and there is nothing to go stale. The minimap is the one view
that can show a player that difference at a glance — and it was showing
the half that does NOT persist. Playtest #40's criterion 3 ("buildings
once seen stay on the map, squads do not") was therefore unjudgeable:
there was nothing on the minimap to watch persist, and the 3D view cannot
substitute while unscouted ground renders fully lit (#58), because a
player has no way to tell "drawn because I remember it" from "drawn
because everything is always drawn".

Sizing from `no_build_radius` reuses the data that already declares how
much ground a building claims (D-062), so the hierarchy a player reads is
the hierarchy the design already stated, and a new civ's town hall needs
no edit here.

**Rejected alternatives:**
- **Gate buildings on `_explored`, like resource nodes.** Nearly a no-op
  in practice (a building's cell is explored by the act of seeing it) and
  wrong in principle: it would say a building is drawn because the GROUND
  is known, when the reason is that the BUILDING is known. The two come
  apart the moment explored is ever recomputed or trimmed, and the
  version that survives that is the one that gates on nothing.
- **Gate on current vision.** This is what the 3D view effectively does
  today, and it would delete the only representation persistent-explored
  fog has. It also makes the minimap worse at its commonest job: a base
  behind your own lines would blink out whenever no squad stood near it.
- **One pixel per building, like a resource node.** At one image pixel
  per cell drawn into 216 screen px, that is ~2.5 screen pixels — smaller
  than a squad dot, which would say a militia patrol outranks a town
  centre.
- **A `minimap_size` field on `BuildingDef`.** A schema addition (D-010's
  log) to express something two existing fields already imply, and one
  more number to get wrong per def.
- **Special-casing walls into a thinner mark.** Tried on paper; a wall
  chain at 2 cells already reads as a line rather than a blob, and a
  1-cell wall would be invisible at this scale — the resolution problem
  the issue raises separately, not a reason to hide walls.
- **Fixing this inside `client.gd` alone.** The absence could not be
  tested from GUT at all (D-014), and an absence is exactly what a pure
  module plus a source-level guard can pin. The guard is the interesting
  half: every arithmetic test in `test_minimap_paint.gd` passes happily
  in a build where the client never calls any of it, which is the state
  the game shipped in.

**Consequences:**
- `minimap_paint.gd` joins the pure client-decision modules, and
  `_plot_minimap` delegates its footprint (including the torus wrap) to
  it, so a mark at the seam is handled in one place for squads and
  buildings alike.
- Building sizes are memoised from one `BuildingSim.all_defs()` walk. The
  minimap repaints at 4 Hz over every building a client knows, and a
  `ResourceLoader` call on that path is the defect shape that cost 858 ms
  of a tick budget in M4 and a frame in M5.
- The minimap now shows three kinds of thing with two colour schemes:
  squads in own/enemy cyan-and-red, buildings in per-player colour. That
  is a deliberate split — a building says *whose ground this is*, for
  which D-052's identity is the useful answer — but it is worth revisiting
  the squad dots against it.
- **This does not fix #59.** Explored and currently-visible ground still
  render identically, so the minimap has two fog states where it wants
  three; buildings are now drawn on top of that, and will inherit the
  third state when it exists.

**Revisit trigger:** A player reports a building they have never seen
appearing on the minimap (that would be a wire-gating bug, D-004, not a
paint bug); the minimap gains a third fog state (#59) and buildings need
to distinguish remembered from visible; or minimap resolution changes
enough that cell-count footprints stop being the right unit.

**Amendment, 2026-08-17 (D-20260817-minimap-squad-colours):** the
two-colour split this entry recorded as deliberate — "squads in own/enemy
cyan-and-red, buildings in per-player colour ... worth revisiting the
squad dots against it" — is **resolved in favour of per-player colour
everywhere**. A playtester hit it the same week: their own army read cyan
where it is red in the lobby and on the field, and their ALLY read in the
enemy colour, which is worse than inconsistent given allies share vision
(D-050). Everything else here stands.

Worth carrying forward on its own account: this entry SAW the
inconsistency, described it accurately, and shipped it anyway.
**Recording a known defect in a decision file is not the same as having a
check that fails** — the note was read by nobody in the weeks it took a
player to hit it, and what closes it is a test, not a better note.
