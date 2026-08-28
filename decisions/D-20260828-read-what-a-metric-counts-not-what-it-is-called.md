# D-20260828 · 2026-08-28 · Accepted — read what a metric counts, not what it is called

**Decision:** a metric's NAME is not evidence of what it counts. Before a
number is used to decide anything — a gate, a verdict, a diagnosis, a
comparison between branches — **read the line that produces it.**

This is the companion to
`D-20260828-a-check-can-lie-in-four-ways.md`, and it is deliberately a
SEPARATE entry, because the remedy is different in kind. Those four modes
are each fixed by perturbing something: the arguments, the code, the
environment, the input type. **This one is not perturbable at all.** The
metric is correct, self-consistent, and green against every test anybody
can write about it. It is wrong only against its own name, and the only
instrument that sees it is somebody reading the definition.

A check built on such a metric inherits the lie while doing nothing wrong
itself, which is why this family survives review: there is no defect at
the site of the failure.

## The five instances, all from one day

| the number | the name says | it actually counts |
|---|---|---|
| `grep -c` on a seating warning | occurrences | **events × 2** — `server.gd:526-527` emits `push_warning` AND `print` for one firing |
| `buildings=` | buildings owned | buildings **known**, which for a fogged client is a different set (D-030) |
| `wood_peak` | wood gathered | wood **held at a peak**, which understates any bot that spent before the sample |
| `squads_peak == 1` | a dead seat | the **opening itself** — one crew and one general (`the-opening.md`) |
| `_scout_leg` | how far it has searched | how many legs it walked **while hungry**, stopping when the economy was satisfied |

The last one is the expensive one. #351 stayed shut for hours because
"have I looked" was keyed on a counter that stopped counting when the AI
stopped needing a resource — so a thriving AI with 3 buildings and 29
squads reported `scout_legs=2` after ten simulated minutes and never
concluded it had run out of world. The predicate above it was correct.
**The number under it did not mean what its name said.**

The first is the subtlest, because it is off by a constant and therefore
always plausible: two workers independently reported a warning "twice",
and it had fired once. A count that is silently doubled looks exactly
like a count.

## Consequences

- **A metric that crosses a boundary is read at the far side.** Same rule
  the art pipeline already learned for colour (D-100: "a colour that
  crosses an asset pipeline is not the colour that comes out"). A number
  that crosses from emission to log to grep to comparison has three
  places to change meaning.
- **Grep counts LINES. Say which you mean.** If a marker is emitted more
  than once per event, either count events explicitly or divide, and
  write down which. `gate-check.sh` reads per-event markers with
  `marker_max` and per-match markers with `marker`, because the two ask
  different questions.
- **A metric's name is a claim, and this project already distrusts
  claims.** D-058/D-065's rule is that a decision entry asserting a field
  is replicated is not evidence that it is; D-106's is that a doc comment
  describing behaviour is not evidence the behaviour exists. This is the
  same rule pointed at an identifier.
- **Two numbers that disagree are worth more than either alone.** The
  stalled seat was diagnosed by `squads_peak=2` AND `buildings=0` AND
  `scout_legs=0` agreeing on a shape no single one of them could have
  established — and each of the three had a plausible innocent reading on
  its own.
- **When quoting a number, quote its frame.** The estate already requires
  a µs figure with its squad count and a ladder result with its cap. Add:
  a log's numbers with the duration that log claims, and a pid with the
  tool that printed it (`ps -W` and `tasklist` number the same process
  differently, which nearly sent two workers hunting a fifth that did not
  exist).

## Rejected

**Renaming the offenders.** Tempting and mostly wrong: `buildings` really
is what the AI knows, and `wood_peak` really is a peak. The names are
defensible; the failure was reading them without checking. A rename would
fix five instances and teach nothing.

**A test.** Nothing can assert that a future reader checked a definition.
Same reason the companion entry rejects one.

## Credit

The observation and the pattern are worker 88's, from the naval chain's
round-2 review — five numbers noticed to have gone wrong the same way in
a single day, across three workers. The `_scout_leg` instance is mine and
was the costly one.
