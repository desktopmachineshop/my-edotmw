### D-20260828-the-host-pays-both-budgets · 2026-08-28 · Accepted — the host breaches the shipping scale, and the tick inside the frame is why

**Decision:** measured, the **host cannot run
`D-20260828-the-shipping-scale`'s 200 squads at the 30 fps that entry
sets**. It holds roughly **100–150**. The cause is not gradual
contention: **the authoritative tick runs inside the render frame**, and
at 200 squads that tick is **46–57 ms** against a 33 ms frame budget, so
at the frame rates measured there roughly one frame in two carries a
whole server tick and cannot fit it.

Issue #339, filed while measuring #287 and answered here.
`just bench-render` in host mode (`--host=1`) is the instrument.

**This gates D-088's architecture**, which is why it is Accepted rather
than Provisional: the finding is a measurement, and the *response* to it
is the open question.

---

#### Why this needed a new measurement at all

D-088 makes the host a **player**: it runs the authoritative simulation
**in-process** inside its own client, with the loopback peer D-051's AI
seats already use. So a hosting machine pays the tick budget and the
frame budget out of the same second.

Every figure this project has is one **or** the other, taken alone, in
its own process. `bench_render.gd`'s own header says so in as many words
— *"the simulation is ticked before measurement and then stopped … a real
client never runs `SquadSim`"* — which is correct for measuring a client
and is exactly why it could not answer this.

`--host=1` does the thing that header forbids, deliberately: it ticks the
simulation **inside** the measured frames at `SquadSim.TICK_HZ`, on the
world a server builds (teams, civs, economy, buildings, research), and
reports what the two halves consume out of each wall-clock second. The
client-only rows are untouched and remain the default.

#### The measurement

**Intel(R) Iris(R) Xe Graphics**, Godot 4.7.1-stable, Vulkan 1.3.286
Forward+, **`islands` preset** — the worst honest case, since it is the
naval map and ~68% sea — 90 measured frames per count, **two passes, both
quoted**.

| squads | soldiers | fps | client ms/frame | **sim ms/tick** | sim ms/s | client ms/s | **TOTAL ms/s** |
|---|---|---|---|---|---|---|---|
| 0 | 0 | 129.6 / 152.2 | 0.08 / 0.06 | — | 0 | 11 / 9 | **11 / 9** |
| 100 | 844 | **56.7 / 55.5** | 9.4 / 9.8 | 34.3 / 37.6 | 345 / 370 | 534 / 546 | **879 / 916** |
| 150 | 1,179 | **44.3 / 31.7** | 11.3 / 10.9 | 42.8 / 38.5 | 442 / 380 | 498 / 345 | **940 / 725** |
| 200 | 1,596 | **19.9 / 35.6** | 13.7 / 12.6 | **46.3 / 46.7** | 460 / 461 | 274 / 447 | **734 / 908** |

**The breach:** at 200 squads the host runs at **19.9 and 35.6 fps**,
straddling the 30 fps budget `D-20260828-the-shipping-scale` set and
missing it in one of two passes. At 100 squads it is comfortably above in
both. **The host's ceiling is 100–150 squads, not 200.**

**And the host is saturated at every count above zero**: 725–940 ms of
CPU per wall-clock second, on a machine whose entire budget is 1,000.

#### The attribution: a tick inside a frame is not contention, it is a dropped frame

The suggestive column is `client ms/frame`: only **9–14 ms**, at every
count. The client's own per-frame work is *not* what makes these frames
slow. The frame is 17–60 ms while the client spends 14 of it.

The rest is the **simulation tick landing inside the frame**. At 200
squads a tick costs **46 ms**, and D-020 runs ten of them a second: at
20 fps, **one frame in two carries a whole server tick**, and a 46 ms
tick cannot fit in a 33 ms budget by any scheduling. That is also why the
two passes disagree so widely at 150 and 200 while agreeing at 100 — the
frame rate depends on *how ticks happen to land*, which is the signature
of this failure rather than noise in it.

**The same tick is 40–70% more expensive here than headless** — 46 ms
against the ~38 ms mean `just profile scale` measures at the same count
on the same preset. Running beside a renderer costs the simulation
something too, and that is the smaller half of the problem.

**D-023 is not violated and is not the cause.** The sim is ticked by an
explicit accumulator, exactly as that entry requires; the accumulator
simply runs on the main thread, which is the only thread there is.

#### What was recovered: nothing, and that is the report

There is no free recovery here. The tick is already amortised (D-040);
its cost is combat, which is a priced design trade
(`D-20260819-only-men-in-contact-fight`); and the separation over-scan
that *was* free was taken in `D-20260828-the-m6-rise-has-a-name`. What
remains is architectural, and architecture is filed rather than fixed
inside a measurement.

#### The design part, filed: #349

Three responses exist and this entry deliberately does not choose between
them — that is D-088's call, not a measurement's:

1. **Take the tick off the render thread.** The largest change and the
   only one that keeps one number for hosted and dedicated play. It
   collides with nothing in D-002 (the server is already authoritative
   and already has its own accumulator), but Godot's threading and
   GDScript's constraints make it a real piece of work rather than a
   flag.
2. **Hosted matches run at a lower scale than dedicated ones.** Cheap,
   honest, and it means the shipping scale becomes two numbers — which
   is a thing a lobby has to explain to a player.
3. **Slice the tick**, the way D-040 slices a field and #106 slices
   terrain meshing. Fits this project's established habit; whether a
   combat round can be split across frames without changing outcomes is
   an open question and probably a "no" (D-024 resolves a round against a
   snapshot).

**M8 needs this before a real 20-seat playtest**, which is what makes it
urgent rather than interesting: D-094's headline criterion is a hosted
20-seat match, and at 10 squads a seat that is 200 squads on one player's
machine — precisely the count that breaches here.

---

#### Rejected alternatives

- **Add the isolated figures together and call it measured.** Rejected,
  and it is worth naming because it is what #339 was filed with: 366 ms
  of server plus 882 ms of client is 1,248 ms and predicts a hard
  breach at 200 squads. The truth is worse in a different way — the
  totals come to 734–940 because the frame rate *collapses to make
  room*, which an addition cannot show. **A sum of two isolated
  measurements is not a measurement of the combination.**
- **Report only the total CPU per second.** Rejected — 734 ms/s at 200
  squads looks like 27% headroom, and the frame rate at that moment is
  19.9 fps. The denominators differ (ticks per second vs frames per
  second) and only reporting both makes the collapse visible.
- **Measure on the default preset.** Rejected — the orchestrator asked
  for the worst honest case and naval is landing; `islands` is the map
  the water layer exists for.
- **Blame the water layer.** Rejected on measurement:
  `D-20260828-the-shipping-scale`'s amendment shows the water field layer
  flat at ~20 µs/squad whether there are 0 or 40 hulls, and hulls make
  the tick slightly *cheaper* by replacing infantry. The breach is
  present with no hulls at all.

#### Consequences

- **`D-20260828-the-shipping-scale`'s 200 squads stands for a DEDICATED
  server and does not stand for a host.** That entry named this as its
  own revisit trigger and it has fired; its amendment now points here.
- **D-088's "player-hosted first, official dedicated later" is now a
  measured trade rather than a preference.** Dedicated is not merely
  nicer; at the shipping scale it is the only configuration measured to
  work.
- **`just bench-render`'s host mode (`--host=1`) exists** and takes
  `PRESET` and `HULLS`. Every knob defaults to the client-only
  behaviour, so a bare `just bench-render` measures exactly what it
  always did.
- **The flag is written `--host=1`, never `HOST=1`.** just binds a
  bare `NAME=value` after a recipe name to that recipe's FIRST
  parameter (D-20260817-recipe-args-are-positional), so `HOST=1`
  would land in `COUNTS` and measure a squad count nobody chose.
  Positionally the recipe is `COUNTS FRAMES HEIGHT HOST PRESET HULLS
  ARGS`. **`ARGS` stays LAST**, which is #229's own rule and is pinned
  by `tests/test_bench_knobs.gd`: it is the free-form passthrough, so a
  parameter added after it could never be reached. The three host flags
  therefore go before it, and `COUNTS`/`FRAMES`/`HEIGHT` keep slots 1-3
  so nothing recorded against them moves.

#### Revisit trigger

**Any of the three responses landing** re-takes this table. And the
standing one from D-085: this is integrated graphics, and a discrete GPU
moves the client column — but note it moves the *smaller* half. The tick
is 46 ms on any GPU.

---
