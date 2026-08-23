# D-20260821 · The sandbox panel runs the world

**Status:** ACCEPTED — the owner's request (2026-08-21): *"upgrade the
dev sandbox panel. Give me the ability to live regen the map. control
whether resources are on or off. spawn enemy units and buildings, change
lobby option to just sandbox mode on or off. Bring the instant build and
so on into the dev panel."* **Amends:** D-077 (the panel's scope grows;
its safety structure does not move).

## The five changes

1. **Live map regen** — a new one-shot cheat, `C2S_CHEAT_REGEN_MAP`
   (opcode 38). The server returns the match to the lobby (the ordinary,
   tested D-075 path — seats held, world dropped), force-rolls a fresh
   seed EVEN IF PINNED (regenerating the identical map is the one thing
   nobody pressing this button wants; the pin governs lobby rerolls, not
   an explicit dev order), and starts the next match immediately. The
   client rides the exact match→lobby→match sequence
   `test_return_to_lobby.gd` already guards, terrain streaming included.
   Nothing is a new lifecycle; that is the entire design. Admin-gated —
   it restarts everyone's match, so it follows `set_sandbox_option`'s
   gate, not `_validated_cheat`'s any-player rule.
2. **Resources on/off** — a fourth sandbox flag, `resources_enabled`
   (default true), riding the same `LOBBY_SET_OPTION` channel as the
   other three (D-077's shape: match-wide settings are options, one-shot
   actions are opcodes). Consulted by `_build_world` at generation time:
   off means `Economy.generate` is skipped and the world has no nodes at
   all. **It applies on the next regen**, and the panel says so — a live
   bulk node clear would need either a fog-violating broadcast or a
   ghost-forest of stale trees (D-087's conceal semantics), and the
   regen button is one click away on the same panel.
3. **Enemy spawns** — the two spawn cheats carry a trailing `enemy`
   byte. The server resolves "enemy" to the first seat not allied with
   the sender (`MatchState.enemy_of`), refuses with a notice when no
   hostile seat exists, and resolves the unit ARCHETYPE against the
   TARGET's civ — D-047's "a client cannot name another civ's unit"
   held, with the civ now being the recipient's.
4. **The lobby shows ONE checkbox** — Sandbox mode on/off. The other
   flags stop being lobby furniture:
5. **— and live in the dev panel instead.** Instant build, AI
   economy-only and Resources are checkboxes on the in-match panel,
   sending the same admin-gated `LOBBY_SET_OPTION` messages they always
   did (D-077 deliberately never phase-locked them). The lobby loses
   nothing a player needs — the flags only matter once a match runs, and
   the panel is where the person iterating actually is.

## What deliberately does not move

- The safety structure: cheats gated on `MatchState.sandbox`, which a
  production server never sets — unreachable by construction (D-077).
- `_validated_cheat` stays any-player for per-player cheats; only the
  two match-wide acts (regen; the option channel) are admin-gated.
- A spawned enemy squad is an ordinary squad: the enemy AI's brain
  commands it, vision stamps it, fog gates it. No special casing.

## Rejected alternatives

- **In-place world regen keeping armies.** Every client cache — terrain
  meshes, fog, node visuals, knowledge, flow fields — would need a
  bespoke mid-match reset path, duplicating the teardown the
  return-to-lobby edge already does correctly and has a regression test
  for. A ~10 s restart through proven code beats a new lifecycle.
- **Live node clearing for the resources toggle** — see 2 above.
- **A dedicated enemy-seat picker.** First hostile seat is right for the
  solo-vs-AI session this panel serves; a picker is worth adding only
  when someone tests a three-sided fight and says so.

## Revisit trigger

If sandbox iteration ever wants regen WITHOUT losing placed test
armies, that is the in-place reset above — a new decision with the
client cache inventory as its first section.

## Amended same day — placement, freeze, and a window that fits

The owner's first session with the panel asked for three more things:

- **A cheat building spawn rides the ORDINARY placement flow.** Arm from
  the panel and the real ghost follows the cursor — facing (V / scroll),
  validity colouring, wall snapping — with no builder-squad requirement;
  the commit sends the cheat packet instead of a build order, honouring
  the enemy checkbox. The wire grew the sub-cell OFFSET for it, because
  the ghost promises one and a spawn that ignored it would drift from
  the preview — D-096's shared-pose rule, which is precisely the defect
  that decision records. Walls place one piece per click in cheat mode:
  the placement DRAG compiles build orders, which a cheat has no builder
  to execute.
- **Freeze AI** — a fifth sandbox option (`ai_frozen`, same admin-gated
  channel). The server SKIPS the brains entirely rather than feeding
  them a no-op, so a frozen brain does not advance its own timers and
  thawing does not fire a backlog of queued decisions. Squads already
  marching finish the march: a curve is not an order.
- **The panel window sizes itself to its content**, deferred one frame
  so theme fonts resolve, capped below the screen height — the fixed
  300x500 was clipping a control per session as the panel grew.

## Amended again — full world visibility, and the baseline it exposed

**Full world visibility** is a sixth sandbox option (`reveal_all`), and
the hook is inside `Vision.is_visible` itself: squads, buildings and
resource nodes all already funnel through that one answer, so revealing
there IS the curve gating D-004 requires rather than a second
data-hiding path beside it. Two rules ride with it:

- **Humans only.** `Vision.reveal_all_players` is a SET of players, and
  the server fills it from human seats. An AI given the whole map would
  not look like a bug, it would look like a good AI — the exact trap
  `docs/status/ai-opponent.md` records against resource and vision
  bonuses.
- **The ground needs telling separately.** Terrain fog is derived
  client-side (D-106), so a server sending everything still leaves the
  map black. `TerrainFog.rebuild` reveals every cell when
  `ClientState.reveal_all()` is set — and LATCHES, because that refresh
  runs four times a second over 32,592 cells and a dev flag gets left
  on. The latch clears the moment the flag does; the test that proves it
  has to toggle back ON, since nothing reads the latch while the flag is
  off (the first version of that test could not see the reset deleted).

**And it exposed a live desync.** A playtest using the Regen button
reported **106 building desyncs over 55,239 checks** with squads clean.
`_return_to_lobby` cleared each client's `visible` baseline — under a
comment saying none of them may keep a reveal baseline from the old
match — and left `known_buildings` untouched beside it. That is D-030's
ever-revealed set, which the server HASHES; building ids restart at 0 in
the next match, so it hashed stale ids against a client that had torn
its world down. Present since leave-to-lobby existed (D-075); the Regen
button just made it a one-click reproduction. Guarded now by a source
scan, the idiom this project already uses where GUT cannot reach.
