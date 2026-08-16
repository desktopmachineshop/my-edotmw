### D-104 · 2026-08-16 · Accepted — a start is a PLACE, not a legal cell: spawns need land, top-ups need ground, and one derivation feeds both sides

*(Editorial, 2026-08-16: first written as D-101 and renumbered to D-104
before merge. Several fix sessions were working in parallel off a `main`
that tops out at D-098, and each independently picked "the next free
id" — four of them chose 101. The ids were assigned centrally afterwards:
#68=D-099, #70=D-100, #66=D-101, #76=D-102, #71=D-103, this one=D-104,
#75=D-105. Same failure as D-081's collision and the same fix; the
lesson, now paid for twice, is that "the next free id" is not a local
question when the log has more than one author at a time.)*

**Decision:** Three rules, all from one playtest report (#53, the P01
`islands` session), all of the same shape — a check that tested the
cheapest available property and called it the answer.

1. **A spawn candidate must stand on a landmass of at least
   `min_spawn_landmass` cells** (96, and map data like every other spawn
   rule). Passability of the candidate's own cell is necessary and not
   sufficient. The test is a flood fill capped at the minimum, so it is
   O(min) per candidate and answers only the question asked — "does this
   clear the bar", never "how big is this island".
2. **The fairness post-pass (D-036 revised) picks ground before it picks
   a cell.** A top-up goes to the nearest reachable cell whose biome
   would GROW that resource; failing that, any walkable cell; failing
   that, a beach. It says out loud how many landed on unsuitable ground,
   per CLAUDE.md's no-silent-caps rule. The old pass chose by passability
   alone.
3. **`MapSettings.to_spawn_config()` is the ONE derivation of where
   players start**, and what it reads (`spawn_seed`, `min_spawn_spacing`,
   `min_spawn_landmass`) travels on the wire with the rest of the
   settings. `MapSettings.from_map()` is the one place a map file becomes
   those settings. No other script may assign `spawn_seed`; a
   source-scanning test enforces it.

**Rationale:**

*On (1).* `islands` is ~71% water at its shipped settings. On the
reported world (168x194, seed 1337) the sampler returned 20 of 20
points, 0 on impassable ground, and **one of them was a six-cell rock**
— a founding party rendered standing in open sea, and a player dead on
arrival, because a town hall plus the resources to work it do not fit on
six cells and D-031 makes that founding party the entire opening.
Nothing failed: `validate_spawns` compares COUNTS, and twenty of twenty
were found. This is the "mechanism correct, shipped numbers do nothing"
family (D-066) wearing its other face — the mechanism was correct about
a property that was not the one that mattered.

96 was measured, not guessed: a sweep of four presets x four map sizes x
three seeds. It rejects every stranded start the sweep found (smallest
under a spawn went 6 → 400+ on the reported world, 4 → 235 on
`islands` Standard) while still seating 20 of 20 on every size from
Standard up. 271 — a full `fairness_radius` disk — would have cost
`islands` Skirmish every one of its spawns. Skirmish maps are bounded by
`min_spawn_spacing` long before they are bounded by this.

The check runs LAST of the three, after passability and spacing, purely
for cost: the three are an AND so the order cannot change the answer,
and it is the only one of them that is not O(1)-ish. Measured on the
over-packed Skirmish maps — 20 slots on 2,016 cells, where the sampler
burns its whole attempt ceiling and every candidate reaches the fill —
**1.0–3.5 s with the fill first against 0.2–0.4 s with it last**.

*On (2).* D-087 moved stone to the mountain FOOT precisely so a node
reads as belonging to the ground it sits on, and noted its old
MOUNTAIN-cell placement was unreachable scenery. The fairness pass then
put stone outcrops on grass and sand anyway — measured on the reported
world, **38 top-ups, 9 of them on beach, none on ground that grows what
they hold**. `resource_visuals.gd` already had a comment shrugging at
this case. The mechanism was right, its caller walked straight past it:
the third instance in this project of a rule that is fully written,
fully called, and reached by nobody who honours it (D-061, D-065).

Beach is ranked below other walkable ground rather than merely
unpreferred, because that is what the screenshot was actually showing: a
beach cell borders water by definition, and the authored node models
span ~2.3–2.6 world units against a ~1.73-unit cell, so a rock dropped
there overhangs the sea. Measured after: **beach top-ups 9 → 0** on the
reported world, 16 → 0 on `islands` Standard, and top-ups on
naturally-yielding ground 0 → 3, 0 → 10, 2 → 13, 1 → 10 across four
worlds.

The band table `_roll_kind` walks is now ONE table (`Economy._bands`)
read by both the generator and the fairness pass, rather than a second
spelling of the same knowledge. Verified equivalent to the code it
replaced across 16 worlds and **63,359 nodes, 0 mismatches** — a
refactor of the generator was not the point and must not have been a
side effect.

*On (3).* `client.gd` drew the lobby's spawn markers from its own
`MapConfig` seeded with the match seed; `server.gd` seeded its own with
the map file's base **plus** the match seed. Both called
`MapConfig.spawn_points`, under a comment in the client saying "this is
the SHARED implementation the server uses (D-039), so this is the same
answer rather than a second guess at it". Measured: **0 of 20 markers
were real spawns.** An admin choosing a map by looking at where players
will start was being shown fiction — including being unable to see that
one start was a six-cell rock.

**Sharing an implementation is not sharing its arguments**, and a
comment asserting otherwise is the D-065 pattern exactly: a claim about
the code that outlived the code. The fix is that neither side may build
the sampler's inputs; both ask `MapSettings`, and the inputs travel on
the wire for the same reason terrain parameters do (`MapSettings`'
header: concrete numbers travel, not preset names).

**Rejected alternatives:**

- **Reject the `islands` preset, or the seed, instead.** The single-cell
  test is shared by every preset — `continents` 42x48 seed 1337 has a
  seven-cell spawn too. `islands` has enough water to hit it often; it
  does not own the defect.
- **Score each start's surroundings and re-roll bad maps.** The
  heuristic nobody has designed, giving a statistical guarantee, that
  `test_map_symmetry.gd`'s header already rejects for terrain fairness.
  A hard floor on connected ground is a rule you can state.
- **Make the fairness pass biome-strict.** A player with no forest in
  reach still needs wood; "fair" beats "geologically tidy" when the
  alternative is losing at map-generation time. The fallback stays — it
  just stopped being the first choice, and it now says when it fires.
- **Send the server's spawn POINTS to the lobby instead of the inputs.**
  Tempting and wrong in the same way as sending a preset id: the preview
  is drawn for a world that does not exist yet, so there is nothing to
  send until the admin presses start. The inputs exist; the world does
  not.
- **Cache the per-cell ground rank in the fairness pass.** Measured
  SLOWER than recomputing (it ranks every reachable cell where the plain
  loop ranks only free ones). Left simple, and the measurement recorded
  in the code so nobody re-optimises it on intuition.

**Consequences:**

- `MapConfig.min_spawn_landmass` is a new map-data field (`maps/*.tres`
  carry it explicitly). Zero disables the check, which is also what a
  caller with no `passable` gets — the fill has nothing to walk.
- A map too fragmented to seat everyone now surfaces through
  `validate_spawns`' existing warning rather than as a stranded player.
  That path was already there and already visible; this makes it the one
  that fires.
- `Economy.terrain` is remembered by `generate()`. An Economy that never
  generated has no ground to reason about and falls back to the old
  biome-blind behaviour — the only callers that do this are tests
  authoring nodes by hand.
- Spawn sampling costs more at world build: **12–33 ms against
  1.0–4.5 ms** at 20 slots, across every preset from Standard (8,064
  cells) to Huge (32,592). The fairness pass costs **~0.45 s against
  ~0.12 s** on a 20-player 168x194 map. Both are once, at world build,
  and neither is on a tick. (Measured on a host running several other
  agents' containers, so read them as orders of magnitude — the M6
  worst-tick lesson.)
- The lobby preview and the server now agree by construction, so the
  preview is evidence about the match again.

**Revisit trigger:** A map preset whose intended play is genuinely
archipelagic — where a six-cell rock start is the point — needs
`min_spawn_landmass` as a per-preset value rather than per-map, and
needs the naval movement that would make it playable. Also revisit if
the fairness pass's log line reports a large majority compromised on
maps people actually play: that is the pass telling you the guarantee
and the terrain disagree, and the answer then is the terrain, not the
pass.
