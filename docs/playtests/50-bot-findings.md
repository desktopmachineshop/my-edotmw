# Playtest #50 — two-human LAN match: bot findings

**Ticket:** [#50](https://github.com/desktopmachineshop/my-edotmw/issues/50) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`,
instance `ao-my-edotmw-85-playtest-visual-infra` on udp **25158** (D-095).

## What was substituted, and what that can and cannot say

Two GUI clients driven by two humans is the thing under test. The approximation
run here is **two bot clients through the real wire**: a real containerised
server, two virtual clients running `ClientState` — the same class the GUI client
runs, which is exactly why the substitution is worth anything — and the real
protocol between them.

That covers the wire: fog gating, order authority, state agreement, and what
happens when a client goes away. It cannot cover anything about two people
looking at two screens, which is criteria 1, most of 5, and all of 6's
human-facing half.

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | join, lobby and start work with two real humans | **human** | untouched |
| 2 | fog is truly per-player | bot-observable | **fog demonstrably gates** (14 conceals, 11 ghosts); one harness caveat below |
| 3 | ownership authority is airtight | bot-observable | server refuses; covered by tests |
| 4 | both clients agree on every battle; **zero desyncs** | bot-observable | **0 desyncs in 116 checks, 0 building desyncs**, across 182 casualties |
| 5 | disconnect resolves cleanly per D-033 (wipe), no ghost artifacts | bot-observable | covered by a test; not driven live here |
| 6 | title bars name their instance (D-095) | bot-observable | **confirmed** by test + this run's own instance line |

## The run

`just test-scenario siege 2 60`, docker runtime:

```
VERDICT ok — 2/2 bots connected, 4277 curve packets received, 42 squad curves held,
192 soldiers derived client-side, 116 state-hash checks, 0 desyncs,
casualties_applied=182 conceal_events=14 reveal_events=4 ghosts_peak=11
patrol_legs=9 scouts_peak=4 raid_orders=12 military_peak=0 known_squads_max=21
buildings_known=8 building_desyncs=0 nodes_known_max=369 nodes_felled=4
```

### Criterion 4 — zero desyncs. The strongest result here.

**116 client/server state-hash comparisons, 0 desyncs, 0 building desyncs**, over
a match that applied **182 casualties** and felled 4 resource nodes. Both clients
derived soldier positions from the same squad strengths the server used, through
the whole engagement.

That is the check M1's audit block exists for — the `desync` scan that matched no
code path and passed vacuously for a milestone while every client derived from a
different strength. The comparison count is non-zero here, which is the first
thing `test-load`'s verdict was later made to assert.

Building desyncs are called out separately because
`docs/status/sandbox.md` records a playtest finding **106 building desyncs in
55,239 checks** caused by `_return_to_lobby` dropping the `visible` baseline and
not `known_buildings`. This run does not return to the lobby, so it does not
exercise that path — **a clean building-desync count here is not evidence that
bug is gone.** Criterion 5's real content (a disconnect and what follows) is
where it would show.

### Criterion 2 — fog gates, with a caveat about the gate rather than the fog

The run reports `conceal_events=14`, `reveal_events=4`, `ghosts_peak=11` — squads
left vision, became ghosts, and came back. Fog is doing per-player work.

But `gate-check.sh`'s own fog comparison **failed**:

```
gate-check(fog-squads): fog did not gate anything —
the most-informed client knew 21 of 21 simulated squads (expected fewer)
```

Both statements are true and they answer different questions. The gate asks
whether the best-informed client *ever* knew everything; two players on a
close-quarters siege scenario satisfy that trivially. Noted on
[#230](https://github.com/desktopmachineshop/my-edotmw/issues/230) rather than
filed separately, because it may be intended that the comparison only means
something at `test-scenario`'s default of four clients.

**So: fog gating is confirmed by the conceal/reveal counters and NOT by the
gate.** For a two-human LAN match the owner's criterion 3 — "things player A has
scouted that player B has not" — is the real check and stays with them.

### Criterion 3 — ownership authority

Not driven live (a bot does not try to cheat). It is guarded on both sides:

- `tests/test_commands.gd::test_a_client_will_not_send_an_order_for_a_squad_it_does_not_own`
  — the client refuses to send;
- `server.gd:1271` refuses again and logs *"player %d tried to order squad %d it
  does not own"*, and `server.gd:1987` does the same for producing at a building.
  Both are re-checks rather than a cached ownership answer, which is D-038's
  lesson — the ownership cache taken at join silently refused every *produced*
  squad an order for a whole milestone.

A human trying to click an opponent's army is still the honest test, because what
the tests cannot see is whether the client's *UI* offers it.

### Criterion 5 — disconnect

`tests/test_match.gd::test_disconnect_leads_to_elimination_through_the_normal_rule`
and `test_eliminate_player_wipes_squads_and_describes_it_as_casualties` cover
D-033's wipe, and both pass. Not driven live here.

The thing a live run would add is the one the tests structurally cannot see:
**what the surviving client's screen does** when an army it can see is wiped, and
whether any ghost artefact is left behind. Given the `_return_to_lobby` building
desync above, that is worth doing carefully.

### Criterion 6 — instance naming

`just instance` reports `ao-my-edotmw-85-playtest-visual-infra`, udp **25158**,
compose project `edotmw-ao-my-edotmw-85-playtest-visual-infra`, and the server
line confirms it published on that port.
`tests/test_multi_agent_isolation.gd::test_client_titles_itself_with_its_instance`
passes, and `client.gd:305-315` builds the title as
`eDotMW — <instance>  [<address>:<port>]`.

(The same test file has one *other* assertion failing on `main` for an unrelated
false positive — see
[#209](https://github.com/desktopmachineshop/my-edotmw/issues/209) — but the
title assertion itself is green.)

## Bugs filed

- [#230](https://github.com/desktopmachineshop/my-edotmw/issues/230) —
  `military_peak` reports 0 on every scenario run, because it is gated on a
  founding squad that scenarios never produce. Found here; the run reports
  `military=2` and `military_peak=0` in the same line while issuing 12 raid
  orders.

## What remains for the owner

Everything two humans are for:

1. **Criterion 1** — two people in one lobby, different civs, start. Nothing here
   touched the lobby at all.
2. **Criterion 3's real form** — A scouts something B has not; check both screens
   disagree in the right direction. The counters say fog works; only two screens
   say it works *per player*.
3. **Criterion 4's human half** — both watch the same fight and compare what they
   saw. Zero desyncs says the state agreed; it does not say both players *saw* the
   same thing.
4. **Criterion 5 live** — one player closes their client mid-match. Watch the
   other screen for the wipe and for leftovers, and watch for building desyncs
   afterwards specifically (the `_return_to_lobby` family).
5. **Criterion 3's UI half** — try to select and order the opponent's squads.

### How to set it up in this worktree

```
just instance          # prints this checkout's udp port — 25158 here
just up                # server, scoped to this instance
just run-client        # first client
just run-client <host> 25158   # second client, from the other machine
```

Per D-095, launch clients only through the recipes so `--instance` is passed and
the two windows are tellable apart.
