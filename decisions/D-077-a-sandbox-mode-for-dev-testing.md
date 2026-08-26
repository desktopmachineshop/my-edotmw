### D-077 · 2026-08-12 · Accepted — a sandbox mode for dev testing, kept structurally unable to leak into a real match
**Decision:** `MatchState` gains three independent flags — `sandbox`,
`instant_build`, `ai_economy_only` — settable from a `--sandbox=1` server
launch arg or, live, by the lobby admin via the existing `LOBBY_SET_OPTION`
channel (a "key=value" pair, the same one a map slider already uses,
rather than three new opcodes). Unlike map settings, none of the three
are locked to the LOBBY phase: the whole point is iterating on a running
match without restarting the server.

With `sandbox` on, three new C2S opcodes are accepted, each gated behind
`MatchState.sandbox` at the top of its handler (`_validated_cheat`, mirroring
`_validated_squad`'s shape): `CHEAT_ADD_RESOURCES` (a flat grant to the
sender), `CHEAT_SPAWN_UNIT` (full-strength squads at a cell, bypassing
cost and the squad cap), `CHEAT_SPAWN_BUILDING` (a complete building at a
cell, bypassing cost/footprint/claim but still refusing water/mountain —
a spawned building should never look broken even with every game-balance
rule around it skipped). `instant_build` and `ai_economy_only` are match-
wide settings rather than one-shot actions, so they ride the lobby channel
instead: `instant_build` makes `_finish_build`/`_handle_order_produce`
raise things already complete (`BuildingSim.add_building`'s existing
`complete` param, `BuildingSim.enqueue`'s new `instant` param queuing at
~0s remaining) rather than adding a second completion code path;
`ai_economy_only` sets `AiPlayer.economy_only`, which skips `_fight`
entirely and holds `_train`'s `wanted` archetype at `"gatherers"` so an
economy-only AI doesn't quietly stockpile an unused army either.

**Rationale:** three flags, not one "sandbox" bit that does everything —
someone may want instant construction without also wanting free resources
and unit-spawning, and a host running an AI-only economy stress test
doesn't need the other two at all. Admin-gating and the launch-flag path
both matter for the same reason: a client cannot turn sandbox mode on for
itself (D-002), and a production server never started with `--sandbox=1`
has no code path that ever sets `MatchState.sandbox` true, so the cheats
are unreachable by construction, not merely unreachable by convention.

**Rejected alternatives:**
- *A single "cheats enabled" bool covering everything* — rejected per the
  three-independent-flags reasoning above.
- *New opcodes for `instant_build`/`ai_economy_only`* — rejected: they are
  admin-gated MATCH settings, the exact shape `LOBBY_SET_OPTION` already
  exists for, and a fourth near-identical opcode would be the copy this
  project's own `_validated_squad` header warns eventually drifts.
- *A debug console (type a command)* — considered; an on-screen panel was
  chosen instead (user's explicit choice) since a discoverable button beats
  remembering command syntax for a tool used occasionally, not daily.

**Consequences:** `just test-unit` is green at **545 tests** across 35
scripts (13 new — `test_lobby.gd` gained flag-independence/admin-gating
cases, `test_sandbox.gd` is a new file for the cheats/instant-build/
economy-only behaviour itself, including a paired test proving the
economy-only scenario WOULD have attacked without the flag, not merely
that nothing happened either way). `test-load 4 120` stays clean with
sandbox off (the default) — 57.46 µs/squad at 52 squads, no regression.
The in-match debug panel and cheat-arm-and-click flow are client-only UX,
unverified by the automated suite for the same reason D-076's placement
tools are — look at them before trusting the geometry.

**Revisit trigger:** none anticipated — this is dev tooling, not a game
mechanic with a balance surface to re-derive. If `ai_economy_only` ever
grows per-seat granularity (some AI fighting, some not, in the same
match) rather than the current match-wide toggle, that is a new decision,
not an amendment to this one, since it would need seat-scoped wire state
`encode_lobby`'s per-seat fields do not currently carry.

---

**Amended 2026-08-21 (D-20260821-the-sandbox-panel-runs-the-world):**
the panel grew — map regen, a resources on/off flag (a FOURTH sandbox
option on the same channel), enemy spawns — and the lobby now shows only
the master Sandbox checkbox, with `instant_build`/`ai_economy_only`
moved onto the in-match panel. The safety structure above is unchanged:
same gating, same channel, still unreachable without `--sandbox=1` or an
admin's explicit toggle.
