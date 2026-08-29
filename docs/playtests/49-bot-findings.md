# Playtest #49 — performance feel on real player hardware: bot findings

**Ticket:** [#49](https://github.com/desktopmachineshop/my-edotmw/issues/49) — stays OPEN.
**Run:** 2026-08-27, worktree `ao/my-edotmw-85/playtest-visual-infra`, base `cc2f4c6`.

## The agent half is discharged

The ticket's setup line is *"agent runs `just bench-render` first on this machine
and records the numbers + GPU name as the baseline (never quote a frame time
without the hardware)."* Done, twice, interleaved.

**GPU: Intel(R) Iris(R) Xe Graphics** (integrated — this machine has no discrete
GPU). Vulkan 1.3.286, Forward+, Godot 4.7.1-stable. Map 168x194 = 32,592 cells,
terrain on, 120 measured frames per count.

```
run 1: squads soldiers  ms_mean  ms_worst  fps  draws  cpu_ms  drawn
          0        0      7.51     8.33   133.2   51    0.07     0
        100     1588     16.37    21.04    61.1   69   15.46    63
        250     3919     35.25    44.38    28.4   88   32.88   155
        500     7868     79.62   101.29    12.6  145   76.30   321
       1000    15756    168.30   591.32     5.9  228  150.89   630

run 2:    0        0      8.09     8.33   123.6   51    0.08     0
        250     3919     31.55    34.06    31.7   88   29.79   155
       1000    15756    184.61   750.95     5.4  228  159.26   630
```

Reproducible within ~12%. Both are quoted because one run is not a measurement —
and because `docs/status/terrain.md` records an unchanged build measuring 52.1 ms
and then 181.1 ms three hours into a benchmarking session. These are two short
runs, not a long session, but the caveat stands: **check any absolute from here
against a fresh one.**

Note the host was carrying three to six other agents' gated jobs throughout the
day. The gate admitted `bench-render` as `gpu` class (exclusive) in 1 s on both
runs, so nothing else of this kind was running alongside — but the machine was
not idle.

## What the numbers say

- **Terrain is not the problem.** 0 squads on the 4x map: 7.5–8.1 ms, ~130 fps,
  51 draw calls. The map ladder did not break the renderer.
- **It is CPU, and it is derivation.** 150.9 of 168.3 ms at 1,000 squads is CPU —
  90%, matching M5's finding that per-soldier derivation was ~96% of the frame.
  Draw calls stay trivial (228 at full scale), so batching would still buy
  nothing, exactly as M5 concluded.
- **It is linear in squads.** 16.4 / 35.3 / 79.6 / 168.3 ms at 100/250/500/1000 —
  nothing accidentally quadratic.
- **The worst-frame column is the one to worry about**: 591 ms and 751 ms against
  a 168–185 ms mean at 1,000 squads. That is a freeze, not a slow frame, and it
  is 4x the mean. Criterion 3 ("big battles degrade gracefully, never to a
  freeze") is at risk on this hardware and the owner should look for it
  deliberately.

## Against the record — filed as [#229](https://github.com/desktopmachineshop/my-edotmw/issues/229)

| when | what | squads | soldiers | ms mean | fps |
|---|---|---|---|---|---|
| M5 (D-045) | primitives, old map | 1000 | 26,644 | 35.66 | 28.0 |
| D-086 | authored VAT models, old map | 1000 | 27,300 | 53.93 | 18.5 |
| **today** | shipped map + roster | 1000 | **15,756** | **168.3–184.6** | **5.4–5.9** |

Roughly **5x D-086's cost per soldier** — today's 1,000 squads hold *fewer* men
and cost three times the frame. Four changes could account for it and this
measurement separates none of them: the 4x map, entities drawn at every visible
lattice copy, the RTW programme's three new per-soldier render passes (duels,
corpses, `soldier_motion`), and the passability clamp whose own entry says a
clean idle-machine A/B *"is still owed"*. The gatherer's 4,824-triangle
placeholder is a separately named, pre-existing debt.

The issue asks for an **attribution**, not a fix — in the style of
`D-20260818-every-microsecond-of-a-tick-has-a-phase`, which attributed the
server's per-squad rise and explicitly refused to invent one for M6's older
number.

## Checklist, classified

| # | criterion | class | status |
|---|---|---|---|
| 1 | normal play holds a playable framerate (subjective verdict AND bench numbers) | **mixed** | **bench numbers taken**; subjective verdict is the owner's |
| 2 | no hitch on mass orders or seam crossings | **human** | untouched |
| 3 | big battles degrade gracefully, never to a freeze | **mixed** | worst-frame data suggests looking hard; a staged battle is the owner's |
| 4 | no degradation over a long session | **human** | untouched — needs 20+ minutes of play |
| 5 | report GPU, resolution, worst moment, budget attribution | **partly** | GPU and numbers above; attribution is #229 |

## What remains for the owner

Everything the ticket calls "played like a player, not a benchmark":

1. **The subjective verdict at a normal squad count.** The bench says 61 fps at
   100 squads and 28 at 250 on this hardware. A real match sits somewhere in
   there for most of its length, and whether that *feels* right is the thing no
   number reports.
2. **Hitches on mass orders** (the D-040 class) and on seam crossings. Both are
   transients; the bench measures steady state at a fixed camera.
3. **Stage the biggest battle you can and hold the camera on it** — the worst-frame
   figures above (591 / 751 ms) say this is where the ticket will find something.
4. **Alt-tab out and back, resize, and leave it running 20+ minutes.** Memory
   creep and recovery are both outside anything measured here.
5. **A discrete GPU.** Every number in this family — M5's, D-086's and these — is
   Intel Iris Xe. D-085's discrete-GPU re-run trigger has been armed since M7 and
   has never fired, and D-094 criterion 9 is still waiting on it. If the owner has
   any other machine, one `just bench-render` on it is the single most valuable
   number this ticket can produce.

## Bugs filed

- [#229](https://github.com/desktopmachineshop/my-edotmw/issues/229) — client
  render at 1,000 squads is 3x D-086's last measurement, unattributed.
