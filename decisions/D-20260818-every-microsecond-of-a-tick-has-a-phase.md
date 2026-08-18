# D-20260818-every-microsecond-of-a-tick-has-a-phase · 2026-08-18 · Accepted

**The tick's phase timers PARTITION the tick, the server reports all of
them, and what they do not account for is printed as a residual. The
rise this was written to explain is the flow-field expansion slice
(D-040), which is a per-TICK cost being divided by a squad count.**

## Decision

Three parts, one root cause (#105, M10 exit criterion 4):

1. **Every region of `SquadSim.tick()` is timed and named**: field
   expansion, curves, vision, combat, buildings (with production as a
   named slice of it) and economy. `phase_usec_per_squad_update()`
   returns them in tick order and ends with **`other`** — the difference
   between the tick's total and the named parts, computed rather than
   assumed small. `server.gd` prints the whole breakdown beside
   `us/squad`, in the periodic status line and in the final summary, and
   the over-budget spike line names the expansion phase too.
2. **`mean_combat_usec_per_squad_update` is combat.** It ran from the
   start of combat to the end of hauling, so the "combat" a run reported
   also carried building advance, production, spawning and the economy;
   the idle-engagement scan, meanwhile, fell between the two timers and
   was in none of them.
3. **The per-squad figure is not all per-squad work, and the breakdown
   is what makes that visible.** `mean_usec_per_squad_update` is total
   tick time over (ticks x squads), so anything with a per-TICK cost
   lands in it divided by the squad count. CLAUDE.md has warned that
   this inflates the number at low squad counts since M1; what was
   missing was any way to see WHICH part was doing it.

## What the number turned out to be

The suspicion in #105 was the flow-field solver, and this project's
standing rule is that a hypothesis formed before instrumenting is wrong.
It was not wrong this time, and the size of it was not guessable.

**A controlled A/B, same scenario, same 16 squads, same seed, same
orders — only the torus changes** (`ScenarioWorld`, 60 s of simulated
time each):

| map | us/squad | fields | curves | vision | combat | buildings | economy | other |
|---|---|---|---|---|---|---|---|---|
| 84x96 (8,064 cells) | 197.33 | **52.53** | 34.44 | 45.79 | 41.60 | 22.62 | 0.19 | 0.17 |
| 168x194 (32,592) | 540.54 | **453.13** | 6.28 | 42.08 | 23.32 | 15.36 | 0.19 | 0.19 |

Every phase except field expansion FELL. Expansion rose 8.6x on 4x the
cells and accounts for **more than the whole difference**. The residual
is 0.17-0.19 µs — 0.03% — so the partition is not hiding anything.

**And the live run says the same thing in one line.** A real server and
four real bots, 300 s on the default map, 48 squads at the end — every
tick that broke D-020's 100 ms budget in the first minutes is field
expansion and nothing else:

```
TICK OVER BUDGET — tick=266 146.0ms squads=4 ... | field_expand=145.4ms
  curves=0.1ms vision=0.0ms combat=0.3ms buildings=0.1ms eco=0.0ms
```

That line could not be printed before this change: the spike report named
curves, vision, combat, buildings and economy, and the phase actually
responsible was not on it.

**Mechanism, and it is D-040 working as designed.** A field is a BFS
over the whole map, amortised at `field_cells_per_tick` (4,096) cells per
TICK. Four times the cells is four times the work per field and four
times as many ticks with a field still expanding — 2,968 of 3,005 in the
run #105 quotes — so the budget is spent on essentially every tick
instead of occasionally. That slice costs what it costs whether one squad
or fifty is waiting on it, and dividing it by 48 squads is what produced
a "per-squad" number nobody could attribute to anything a squad does.

**This is not a fault to fix here.** Trading that latency for a
bounded worst tick is exactly the trade D-040 took, and how to spend it
better is #107. What was broken was that the cost was invisible.

## The divisor, watched moving in a single run

The same live run, printing the breakdown every 100 ticks as the players
produced their first armies — one match, one build, nothing changing but
how many squads the same tick cost is divided between:

| squads | us/squad | of which fields |
|---|---|---|
| 4 | 1294.77 | 1076.59 |
| 14 | 411.60 | 316.57 |
| 25 | 276.44 | 208.54 |
| 48 | 644.60 * | 326.79 |

That is the headline metric falling by a factor of **four and a half**
while the server does strictly more work, because the expansion budget is
per tick and the divisor tripled. (* the 48-squad row is the run's final
figure and is inflated by a 7.1 s stall — see the caveat below.)

## A caveat on the absolute numbers, which is this project's usual one

**Every measurement here was taken on a host running five to ten other
agents' Godot processes and containers**, and it shows: the same
unmodified build measured 202.02 µs/squad at 48 squads in a Linux
container and 644.60 in a native Windows process, and the native run
reported a **7,087 ms worst tick** with zero dropped ticks, which is an
OS stall rather than any phase's cost. Cumulative means absorb a stall
like that whole, which is why the run's `economy` figure climbs to ~160
µs/squad in one 200-tick window and then decays — the shape of one stall
being averaged away, not a cost.

So: **the shares and the A/B deltas are the result here; the absolutes
are not.** That is the same rule D-096's benchmarking session had to
learn, applied before rather than after quoting a number.

Two more conditions worth recording rather than glossing. The live run
was taken through `just run-server` + `just run-bots` on the **native**
runtime, because Docker Desktop's Linux engine went down on this host
mid-session and stayed down (500s on the network API, every recipe that
touches it); the 202.02 µs baseline above was captured in a container
before that happened, and a containerised `test-load` on this branch is
still owed. And the instrumentation itself costs seven
`Time.get_ticks_usec()` calls per tick — tens of nanoseconds against a
tick measured in milliseconds, and it replaces nothing, so no number here
is inflated by the act of taking it.

## M6's 40.8 -> ~77 rise: declared SEPARATE, with the mechanism named

#105 asked for M6's older unexplained rise to be closed here or declared
separate. **Declared separate**, deliberately: those two numbers were
taken before any of this instrumentation existed, on builds that are
several milestones gone, and no breakdown can be recovered from them
after the fact. Retro-attributing them would be a story, not a
measurement.

What can be said with evidence is that **the pair is not comparable in
the first place**: M4's 40.8 µs was measured at **120 squads** and M6's
~77 at **~52**, and the fixed per-tick costs the breakdown now names are
divided by that count. The standing rule ("always quote it with a squad
count") was followed in both cases and still allowed a divisor change to
read as a code regression. The honest closure is the instrument, not a
retrofitted explanation: from now on a rise is attributable when it
happens.

## What this makes visible next, without claiming it here

The breakdown also puts **economy** second on some windows and **curves**
third, both of which were inside the old lumped `combat` figure and
neither of which anyone has ever looked at. Whether the economy phase has
a real per-tick cost at 7,694 nodes, or whether every large reading of it
so far is a stall being averaged, needs a run on a quiet host. Filed as
an observation, not a finding: quoting it as one would be exactly the
mistake this entry exists to stop.

## Rejected alternatives

- **Optimise the flow field now.** Out of scope by the issue's own terms
  and by the milestone's: #105 is measure-and-attribute precisely so
  #107's fix has a before-number that means something.
- **Time only the field expansion, and leave the rest as it was.** It
  would have explained this rise and left the next one exactly as
  unexplainable. The residual is the part that keeps paying.
- **Compute the residual by subtracting vision and combat in the report
  instead of timing regions.** That is what a reader had to do by hand,
  and it is how "combat=32.681" was read as combat for a milestone: an
  overlapping timer subtracts wrongly and silently.
- **Report the phases as a share of the tick rather than in µs/squad.**
  Shares hide the divisor problem this decision exists to expose; the
  parts are in the same unit as the figure they decompose, and sum to it.

## Consequences

- `just test-load`'s final line and the server's status line now carry
  `fields= curves= vision= combat= buildings= production= economy=
  other=`. Nothing greps the old `(vision=... combat=...)` substring —
  both recipes match `server: final` — but a human comparing to an older
  log should know the `combat` figure narrowed and is no longer
  comparable to one printed before this change.
- `tests/test_tick_phases.gd` fails if the residual exceeds 15% of the
  tick, so a phase added to `tick()` and not timed goes red rather than
  quietly enlarging `other`.
- `profile_sweep.gd`'s combat column narrows with the same definition.

## Revisit trigger

If `other` ever needs raising above 15% to keep the suite green, that is
a phase nobody has named, not a tolerance to relax. And if a future
change makes per-tick fixed cost dominate at D-018's full 1,000 squads —
where the divisor is 20x today's — `mean_usec_per_squad_update` stops
being the right headline and the breakdown becomes the headline.
