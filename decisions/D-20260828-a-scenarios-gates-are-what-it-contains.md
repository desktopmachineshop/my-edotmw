### D-20260828 · 2026-08-28 · Accepted — a scenario's gates are scoped to what that scenario contains

**Decision:** A run's verdict is scoped to what the scenario it is playing
can actually produce, and every scoped-out check is ANNOUNCED. Four
changes:

1. **`military_peak` is no longer gated on the founding crew being
   identified.** `_is_military` already excludes the founder and handles
   `-1` correctly on its own, because no squad has id −1.
2. **The opening guard asks whether there IS an opening.** Both the raid
   path and the patrol asked `_owns_a_building()`; they ask
   `_opening_pending()` — owns no building AND owns a squad that could
   found one.
3. **The bots' buildings gate is asked only of a run that could have
   buildings**, decided from the `ScenarioDef`; a scenario with none must
   instead field the army it was given (`_military_squads() > 0`).
4. **`ScenarioDef.proves_fog_gating`** (default `true`, `false` on
   `clash`) rides the server's `SCENARIO` marker, and `test-scenario`
   skips `gate-check.sh fog-squads` — loudly, with its reason — when it
   is false.

**Rationale.** From #230: `just test-scenario clash 2 60` could not pass,
and the bot's own line said why in one breath —

    BOT player=1 squads=5 military=5 ... military_peak=0

**`military=5` and `military_peak=0` on the same line.** #123 made
`military_peak` a metric precisely so that *"there was nothing to send"*
and *"there was something and it was never sent"* could be told apart, and
on `clash` it reported the first when the second was true. Everything
downstream read zero with it: `raid_orders`, `scouts_peak`,
`patrol_legs`, `first_soldier_at`.

The cause is one guard whose reason expired. `_founding_squad` is set only
at the end of `_found_town_hall`, past an early return that `clash` takes
on every tick forever — it ships no gatherer crew, and `built_by` for a
town centre is `gatherers` since
`D-20260823-the-opening-is-a-crew-and-a-general`. The `if _founding_squad
>= 0` guard was added against a t=0 artefact from an opening in which the
founder was the *only* squad; that opening is gone, and the guard's own
comment already said so.

**And a vacuous FAILURE is as bad as a vacuous pass.** `clash` places no
buildings, so `_verdict_ok`'s `buildings_known > 0` clause was
unsatisfiable there however healthy the run was. It failed identically
every time, which is exactly how the next person learns to ignore the
result — the mirror of the vacuous passes D-022's audit block was written
about. `clash` is not a corner case: it is one of three shipped
scenarios, `just scenarios` calls it the one for combat and morale, and
`docs/status/ai-opponent.md` says outright to pair AI profiles on it
rather than on `siege`.

**The third piece is one this change CAUSED, and that is the interesting
part.** With the bots finally fighting on `clash`, the armies converge —
and `gate-check.sh fog-squads` is a **peak** comparison: even the
most-informed client must know FEWER squads than the server simulates, at
every moment of the run. Once every army meets, somebody has seen
everything. Measured: **10 of 10 at two bots, 20 of 20 at four.**

Before this change that gate passed on `clash` — and only because the
bots sat still. `clash` starts its armies 8 cells apart against a 12-unit
vision range, so nothing ever saw anything. **A gate satisfied by the
harness being broken**, which is the same shape as every vacuous pass in
D-022's audit block and worth recording as its own instance: *a check can
be green because the thing it checks never happened.*

So `clash` declares that it cannot answer that particular question. What
it does NOT do is stop asserting fog: the same run reports
`conceal_events=21 reveal_events=13` (137/86 at four bots), the bots'
verdict gates on both, and `fog-nodes` still runs unconditionally.

**Rejected alternatives:**
- *Give `clash` a crew and a hall* (rejected — that makes it a second
  `siege`. `clash` is deliberately two armies and nothing else, and
  `docs/status/ai-opponent.md` depends on the difference.)
- *Raise `clash`'s separation until fog gates* (rejected on the
  measurement — the comparison is about the PEAK, and any scenario whose
  armies meet has a moment of total knowledge whatever its starting
  separation. It would also contradict "already within reach".)
- *Scope the gate by scenario NAME in the recipe* (rejected — a list of
  names is the exact defect #152 turned out to be, one file over. The
  scenario resource declares it, so a new `.tres` is covered the day it
  is written.)
- *Skip the check quietly* (rejected — `gate-check.sh`'s own header says
  "a comparison that silently skips is the vacuous pass D-022's audit was
  written against". It prints what it skipped and why.)
- *Have the bot INFER that buildings are impossible* (rejected, and this
  one is the trap worth naming: a bot that excuses itself because it saw
  no buildings would also excuse a real regression in which buildings
  stopped replicating. The scenario is told to it explicitly.)

**Consequences:** `run-bots` passes `--scenario` through from
`EDOTMW_SCENARIO`; empty means a real opening, so `test-load` and a bare
`just run-bots` are untouched by construction — the scenario reaches the
VERDICT only and no bot decision reads it. `_opening_pending` also means
a bot whose crew has DIED now raids with what it has left instead of
standing still forever, which is a behaviour change on the real opening
and a strictly better one. The default of `proves_fog_gating` is `true`,
so a scenario has to opt OUT; a test asserts `clash` is the only shipped
one that does, and `test-load`'s own gate block is byte-identical.

**Measured** (docker, 2026-08-28):

- `just test-scenario clash 2 60` — **clean**, where it could not pass at
  all before: `VERDICT ok`, 0 desyncs over 115 checks,
  `casualties_applied=294 conceal_events=21 reveal_events=13
  raid_orders=37 military_peak=10`, `fog-nodes` gated 5,247 of 5,592
  nodes, `fog-squads` SKIPPED with its reason printed.
- `just test-scenario clash 4 60` on the way there: `VERDICT ok`,
  `casualties_applied=760 raid_orders=72 military_peak=20`.
- `just test-unit bot_reports` — 13 tests, **three observed to fail
  before being trusted** (D-022): restoring the `_founding_squad` guard,
  unscoping the buildings gate, and setting `proves_fog_gating = true` on
  `clash` each red their own guard.

**Revisit trigger:** if a second scenario ever wants
`proves_fog_gating = false`, check first whether the reason is the same
one — armies that converge — or whether the fast loop has quietly stopped
proving fog at all. Two is a pattern; the gate exists because D-026
criterion 6's load half has to be asserted by something people actually
run.

---
