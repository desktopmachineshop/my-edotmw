# #35 — formations: choice, latching, replication (reframed as an RTW gap analysis)

Bot-observation pass, 2026-08-27, worktree `ao/my-edotmw-84/root`.

#35's own instruction is that shape must be verified **through the wire** —
D-065's history is that `SQUAD_INFO` did not carry shape at all while a
decision entry said it did, so a server-side assertion proves nothing.
Everything below therefore round-trips real bytes:
`SquadSim.squad_info_entries` → `NetProtocol.encode_squad_info` →
`ClientState.handle_packet` → read back off the **client**, with both
`composition_hash()` implementations compared.

**Ticket status: LEFT OPEN.** The five original pass criteria are
discharged bar one that needs a second client. The reframed gap-analysis
table is **substantially out of date** and is re-rated below — that is
this pass's main contribution.

---

## Headline: the "Code says" column predates the RTW programme

#35's table was written on 2026-08-18. The twelve workstreams of
`D-20260818-battle-quality-outranks-player-count` all landed after it
(`docs/status/rtw-battles.md`), and #158 wired the civ knobs on
2026-08-23. **Six rows marked "absent" and one marked "absent in
practice" are now present** — and one, A15, is *still* absent for a
reason the ticket did not have. Each was exercised rather than grepped —
`playtest_obs/obs_formations.gd`, log `docs/playtests/logs/obs35-formations.log`.

### A. RTW battle behaviour — re-rated

| # | Behaviour | Ticket said | **Now** | Evidence |
|---|---|---|---|---|
| A1 | Wheeling, inside men slow | present | **present** | `tests/test_squad_turning.gd` prints 1.003x outer-man speed, 0.57°/frame |
| A2 | Formation held while marching | present | **present** | — |
| A3 | Morale / routing | present, per-squad | **present** — *but see #218* | routs at 2.7–4.4 s in melee; **never** under building fire |
| A4 | Shape survives the per-tick suggestion | present | **moot** | `SquadSim.suggest_shape` and its latch are **gone** (D-20260820 amendment): nothing in the sim asserts shape per tick any more. Measured anyway — a player's `wedge` on a working crew held for a full 120 s haul, the only shape ever seen |
| A5 | Shape replicated | present, hashed | **present** | wire round-trip below |
| A6 | Casualty restamp orderly | by design | **present** | `soldier_motion.gd` deals survivors to restamped slots (D-006 cl.2 as amended) |
| A7 | All six shapes selectable | **partial — only 3 offered** | **6 of 8 offered** | `offered=true`: column, line, ring, sparse, tight, wedge |
| A8 | Player sets **facing** | **absent** | **PRESENT** | `set_facing(2048)` → `facing_of=2048`, `facing_angle_of=3.142 rad`; replicated |
| A9 | Player sets **width/depth** | **absent** | **PRESENT** | `set_files(12)` → footprint recomputed; replicated |
| A10 | **Charge** | **absent** | **PRESENT** | `order_charge` → `is_charging=true`, ×3.0 impact, ×1.5 pace |
| A11 | **Flanking / rear attacks** | **absent — combat reads no facing** | **PRESENT** | `Engagement.aspect` returns front/flank/rear; ×1.5 / ×2.5 morale multipliers |
| A12 | **Men pair off in melee** | **absent** | **PRESENT** | `cosmetic_duel.gd`, render-side under D-006 cl.2 — exactly the client-only change #35's own structural note predicted |
| A13 | Men fill vacated slots | absent by design | **present** | `soldier_motion.gd`; D-006 cl.2 amended in its own file |
| A14 | Individual routing | absent | **absent** — per-squad by design (D-019) | unchanged |
| A15 | Phalanx / testudo / square | absent | **still absent IN PRACTICE** | `shield_wall.tres` and `testudo.tres` ship as FormationDefs with directional `taken_*`, and **no unit in the roster grants either**: `UnitDef.formations` is empty on all 39 defs, and both are `offered=false`, so nothing can ever select them. Already filed as part of **#215** |
| A16 | Guard mode | **absent** | **present in the sim** | `STANCE_GUARD` set and read back; the stance byte also carries SKIRMISH, HOLD_FIRE, RUN. Whether the UI offers them is a client question this pass did not reach |
| A17 | Formations interpenetrate while marching | deliberate | **unchanged, deliberate** | D-20260818 cl.5 |

Also landed since the table: **fatigue** (`fatigue_of`, charge refused
under 40, ended at 25) and **height advantage** in combat — neither has a
row.

### B. RTS economy / civ building — re-rated

| # | Behaviour | Ticket said | **Now** | Evidence |
|---|---|---|---|---|
| B1–B6 | resources, nodes, storehouse, construction, queues, walls | present | **present** | B1–B3 measured in `36-bot-findings.md`, B5 in `37-bot-findings.md` |
| B7 | Building upgrades | partial, towers only | **partial — and it is the WALL tower** | only `wall_tower` has `upgrade_from`; nothing upgrades from `tower`, and `wall_tower` has damage 0.0. See `39-bot-findings.md` step 6 |
| B8 | Ages / epochs | absent | **absent** | M9's ladder is still design-only |
| B9 | Tech tree | absent | **absent** | |
| B10 | Unit upgrades | absent | **absent** | |
| B11 | Civ mechanical difference | **absent in practice — read by nothing** | **wired, but only 2 of 6 civs use it** | #158 wired all three knobs; `gather_speed` measured working (55.1 s → 48.1 s) and `squad_cap_bonus` measured working (cap 6 → 10 with the right refusal text). But the shipped values are: gravesworn (cap +4, production 1.15), gildedreach (gather 1.15), **and four civs at every default**. Rate `partial`: the mechanism is real, the data uses it twice. That matches `docs/status/fantasy-civs.md`, which built exactly those two identities on these fields |
| B12 | Number of civs | 2 of 6 planned | **6 shipped** | legion/northmen deleted 2026-08-26 (#191) |
| B13 | Renewable resource | absent | **absent** | still strictly finite |
| B14 | Army upkeep | absent | **absent** | M9 |
| B15 | Match length vs 1–2 h | ~200–230 s | **still far off** | one clean AI match had first attack at 152 s; see `43-bot-findings.md` |

### A correction this pass had to make to itself

An earlier draft rated **A15 as PRESENT**, on the strength of the two
FormationDefs existing. The harness had in fact printed *nothing* for
"which units grant them", and an empty list was read as "granted
elsewhere". `UnitDef.formations` is empty on **all 39** shipped defs and
both formations are `offered=false`, so **no player can select either
one**. That is the declared-and-unread family, and this pass walked into
it while auditing for it.

It is already filed — `tests/test_fighting_styles.gd::
test_granted_formations_exist_and_are_not_globally_offered` is one of the
failures in **#215**, at this same commit.

### The suite is red at this commit, and it bears on this table

`just test-unit` at `cc2f4c6` fails 22–24 of 1249 tests
(`docs/playtests/logs/test-unit-full.log`). Filed by another worker as
**#215** (with #212, #211, #203, #202, #209, #208 and the older #152) —
all `#191` roster fallout, plus twelve known native-runtime shell-out
failures that are not defects. Rows rated from a *test* above should be
read with that in mind; every row rated from `obs_formations.gd` was
exercised directly and does not depend on the suite.

**#35's structural note that "A12 is the biggest visual gap and the
cheapest to close" was acted on** — it closed as a client-only change,
exactly as predicted.

**Its second note stands unchanged: B13 and B15 are the same problem.**
No renewable resource exists, so a 1–2 hour match remains economically
impossible regardless of combat tuning.

---

## The original pass criteria

| Criterion | Outcome |
|---|---|
| All six formations visibly differ and are held while marching | shapes are **offered** (6 of 8) and replicate; **"visibly differ" needs the owner** |
| A player's shape on a gathering crew survives the per-tick suggestion | **PASS** — and the suggestion channel no longer exists (A4 above) |
| Shape persists across orders, combat and rally | **PASS** for the gather case measured; combat/rally persistence not separately staged |
| Casualty restamps look orderly, no teleporting | **needs a human** — `soldier_motion.gd` exists and walks survivors in |
| Shape replicated to other clients | **PASS through the wire** |

### The wire round-trip

```
squad  shape srv  shape cli  facing s  facing c  files s  files c
0      line       line       0         0         4        4
1      column     column     1024      1024      9        9
2      wedge      wedge      3072      3072      2        2
every field survived the wire: true
composition_hash server=32507382 client=32507382 agree=true
```

Shape, facing and files all cross real bytes intact, and the two
independently-written `composition_hash()` implementations agree exactly.
D-065's regression is not present, and A8/A9's new replicated fields ride
the same machinery correctly.

**One thing this did NOT prove.** The harness also compared derived
soldier positions and reported "worst disagreement 0.000000" — that
figure is **vacuous**: the client had received `SQUAD_INFO` but no curve,
so `ClientState.soldier_transforms` correctly returned empty for all
three squads and nothing was compared. Recorded rather than quietly
dropped. Full client/server soldier agreement is `just test-load`'s desync
gate, not this.

---

## What still needs the owner

1. **Do the six shapes visibly differ, and hold while marching?** The
   only criterion here that is purely visual.
2. **Casualty restamps** — no soldier teleporting across the formation as
   men die.
3. **Replication to a SECOND client.** `quick-test` is `--players=1`;
   this needs `./tools/just.exe lobby 2` plus a second `run-client`. The
   wire round-trip above proves the bytes are right, not that two GUI
   clients agree on screen.
4. **Re-rating the rows above by FEEL.** #35 says explicitly *"your feel
   on 'wrong' matters more than my grep on 'absent'"*. Everything above
   is a grep-with-evidence and cannot rate `wrong-feel` on any row —
   most usefully on A10 (charge, whose visible half is speed), A12
   (duels) and A1 (wheeling).

---

## Artifacts

| file | what |
|---|---|
| `docs/playtests/logs/obs35-formations.log` | offered census, wire round-trip, shape survival, RTW row survey |
| `playtest_obs/obs_formations.gd` | the harness |

## Filed from this ticket

None directly. #218 (morale under building fire) bears on row A3.
