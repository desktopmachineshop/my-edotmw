# Bot-observation passes over the playtest tickets

One file per playtest ticket, written by an agent pass that discharged
as much of each ticket as **bot-vs-bot matches plus scripted observation
of the real simulation** can honestly cover, and handed the rest back.

Each file says three things, in this order:

1. **Every checklist item classified** — bot-observable or needs-a-human.
2. **What was observed**, with numbers and the log that produced them.
3. **Exactly what is left for the owner**, and why a bot cannot do it.

The standing rule these were written under is this repo's own: *a green
run is not the same as a run that happened*. Where a result looked like a
finding and turned out to be the harness, the mistake is recorded rather
than quietly corrected — see #38's "A fixture mistake worth recording"
and #36's note on the civ handover, both of which would have produced
plausible and completely false bug reports.

## The passes

| ticket | subject | filed |
|---|---|---|
| [#43](43-bot-findings.md) | full match vs AI, pacing | #217, #224 |
| [#38](38-bot-findings.md) | field combat: counters, fairness, morale, rout | #218, #219, #220 |
| [#39](39-bot-findings.md) | siege: razing, defensive fire, health UI, upgrades | #218, #227 |
| [#37](37-bot-findings.md) | production, costs, squad cap, rally | none — all clean |
| [#36](36-bot-findings.md) | economy: gathering, hauling, depletion, storehouse | none — all clean |
| [#35](35-bot-findings.md) | formations, and the RTW gap analysis re-rated | none |
| [#42](42-bot-findings.md) | match lifecycle: victory, elimination, lobby | none |
| [#207](207-bot-findings.md) | civ differentiation across the six fantasy civs | #266, #267, #268, #269, #270, #275, #276 |

## The harnesses

`playtest_obs/*.gd` — standalone `SceneTree` scripts, run directly:

```
tools/godot.exe --headless --path . -s res://playtest_obs/obs_combat.gd
```

| script | ticket | what it stages |
|---|---|---|
| `obs_combat.gd` | #38 | mirror fairness, counters, rout, casualty integrity, a big engagement |
| `obs_counters.gd` | #38 | D-072 power table + the full missile/infantry matrix, squad-for-squad and per resource point |
| `obs_morale.gd` | #38/#39 | morale traces under building fire, against a melee control |
| `obs_siege.gd` | #39 | defensive fire, `health_fraction` on the wire, second-squad reach, upgrades, elimination |
| `obs_siege_diag.gd` | #39 | the screening-squad finding and its position control |
| `obs_production.gd` | #37 | the real `server._handle_order_produce` / `_handle_order_rally` over a `LoopbackPeer` |
| `obs_economy.gd` | #36 | node census, haul cycles, tree timing, retargeting, storehouse |
| `obs_formations.gd` | #35 | `SQUAD_INFO` wire round-trip, shape survival, RTW row survey |
| `obs_lifecycle.gd` | #42 | the elimination rule in all four states, lobby round trip |
| `obs_civs.gd` | #207 | roster leakage, the shared archetypes' spread and their duels, both live `CivDef` knobs against the real economy, rout reachability, the opening's affordability, seats against starting positions |

They are **observation harnesses, not tests**: they print, they do not
assert, and they deliberately live outside `res://tests` so GUT does not
collect them. They go through the simulation's own objects — the same
`SquadSim`/`BuildingSim`/`Economy`/`Combat` wiring `server.gd` builds, and
for #37 the real server handlers — so what they measure is what a match
does, not a restatement of it.

`logs/` holds the output each one produced, copied out of the gitignored
`artifacts/` so the evidence behind every number above survives.

## The tree these were taken on

Base commit **`cc2f4c6`**, 2026-08-27. Native runtime
(`EDOTMW_RUNTIME=native`) throughout, because the docker `test` service's
1 GB `mem_limit` OOM-killed a cold import twice on a host down to ~1.2 GB
free.

**`just test-unit` is RED at this commit** — 22–24 failing of 1249,
captured in `logs/test-unit-full.log`. That is already filed by another
worker as **#215**, with #212, #211, #203, #202, #209, #208 and the older
#152 covering the same ground: all `#191` fantasy-roster fallout, plus
twelve `test_recipe_args.gd` / `test_gate_checks.gd` failures that are the
known native-runtime shell-out gap and **not defects**. Nothing about the
red suite was re-filed from these passes.

Two of those failures land directly on ticket #39 (D-067's two-squads
rule fails for 12 archetypes against a town centre and 15 against a
tower), and one lands on #35 (no unit grants `shield_wall` or `testudo`).
Both are noted in the relevant files. Every test cited *as evidence* in
these passes was checked green individually: `test_squad_turning.gd` 9/9,
`test_fearless.gd` 4/4, `test_return_to_lobby.gd` 21/21,
`test_civ_knobs.gd` 18/18, `test_economy.gd` 44/44.

## Two things to know before adding another

**A fixture that skips a handover reports a wired feature as unwired.**
`obs_economy.gd` first measured every civ's tree time as identical,
which looks exactly like the declared-and-unread family — the cause was
that it never called the equivalent of `server._hand_civs_to_sim()`.
Set `sim.civs[player]`.

**A control run is what separates a finding from the harness.** #207's
six-way ladder run showed three of six civs never founding a base, which
reads as a civ result and is not one: the map had four starting
positions for six seats (#276), and a four-seat control then showed
seats failing there *too*, for a third reason already fixed in review
(#217 / PR #255). One of the three civs was a real defect (#275) and it
took two runs to say which.

**Order squads at each other, not past each other.** Ordering two sides
to points beyond one another lets them cross, separate and walk away; the
run then reports enormous attrition margins with nothing decided, which
reads as "combat does not resolve". Order each side at the other's own
start cell.
