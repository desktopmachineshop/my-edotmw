### D-20260828 · 2026-08-28 · Accepted — the soldier clamp stays PER MAN

**Decision:** `Formation.grounded_offset` keeps pulling each drawn man
back along his own offset ray until he stands on ground his squad could
walk on. The per-SQUAD footprint test
`D-20260818-a-soldier-stands-where-his-squad-could-walk` named as "the
lever if M10 wants it back" is **not taken**, and the reason is a
measurement rather than a preference: after #245 the clamp is no longer
the cost that lever was proposed against.

The only change made here is one **exactly-equivalent** removal: a man
the caller has already found to be over blocked ground is no longer
re-tested by the pull. Nothing moves.

## The premise moved, and that is the whole entry

#244 was filed on this measurement
(`D-20260828-every-microsecond-of-a-frame-has-a-phase`, 1,000 squads,
4,385 drawn men, Intel Iris Xe, interleaved):

| | derivation ms/frame | share |
|---|---|---|
| clamp on | 82.53 / 78.51 | — |
| clamp off | 57.87 / 53.09 | **the clamp was 30-32%** |

Re-measured on this branch, after #245 gave every man ONE cell
derivation instead of two, three interleaved pairs, same host, same
`--decorate=0` isolation:

| pass | clamp on | clamp off | |
|---|---|---|---|
| 1 | 77.49 ms | 70.84 ms | −8.6% |
| 2 | 74.48 ms | 62.87 ms | −15.6% |
| 3 | 71.31 ms | 54.74 ms | −23.2% |

Mean **74.4 → 62.8 ms: the clamp is 15.6% of derivation now**, about
2.6 µs per drawn man — and derivation is itself ~19% of the client's
real frame once the render passes it was missing are included (#240). So
**the clamp is roughly 3% of a frame**, against the 30% of a phase it was
filed as.

Most of what #244 measured was never the clamp. It was the clamp and the
height sampler each converting the same world position to the same hex,
one line apart — which is #245, which is done, and which cost nothing
visible because it moved nobody.

## What the remaining 3% is made of

The fast path is now a single array read: the cell was derived for the
height anyway, so "is this man on walkable ground" is `passable[index]`.
Everything left is the men who are ACTUALLY over water or rock, each
paying up to four pull-back probes.

Measured on the shipped 168×194 map, 36-man lines placed on walkable
cells: **23.1% of cells are blocked and 9.0% of drawn men are clamped.**
That is the assumption this decision rests on, stated so the next person
can check it rather than inherit it: **the clamp's cost is proportional
to how many drawn men stand over blocked ground**, and on the shipped map
that is about one man in eleven.

## Rejected alternatives

- **The per-squad footprint test** (`disk_offsets` over the formation's
  radius, skip the per-man work when the whole footprint is clear). It
  buys at most the 15.6% above and it can LOSE: under render LOD a
  distant squad draws 5 or 12 men while its footprint may be 61 cells, so
  the test would cost more than the work it skips on exactly the squads
  that are cheapest. And it does not answer the same question — a
  formation half over water still needs every man placed, so this is an
  early-out for the easy case, not a replacement.
- **Clamping the whole formation by its worst slot.** Cheaper, and it
  changes the picture: the block SHIFTS rather than compressing against
  the shoreline. That compression is the behaviour #97 chose on purpose
  ("a nearest-passable-cell walk moves each man his own way, so
  neighbours separate and the formation tears along the shoreline"), and
  3% of a frame is not a reason to re-open a rule a player can see.
- **Skipping the clamp for distant squads.** It would make a drawn man's
  POSITION depend on the camera. D-012 permits camera-keyed LOD and D-045
  applies it to how MANY men are drawn — deliberately "thinner, never
  smaller" — but where a man stands is not a detail level, and a squad
  that popped along the shoreline as the camera approached would be the
  #97 defect wearing a new hat.
- **Deleting the clamp.** It exists because men stood on ground their
  squad could not path onto and popped **2.0 world units** onto the drawn
  cliff top, reported from a playtest. The cost is real; so is the defect.

## What IS taken, and the honest size of it

`Formation.pulled_onto_passable` is the pull, split from the test.
`grounded_offset` is that test plus that pull and behaves exactly as
before for every existing caller; the bulk derivation path, which has
just established that the man is blocked, calls the pull directly instead
of asking again. That removes one `world_to_axial` + `round_axial` +
`index` per clamped man — one man in eleven.

**It could not be measured, and it is kept anyway.** Four interleaved
pairs of a headless micro-benchmark (140,400 men per run, real shipped
map, real fields) came back 3.211 → 3.441, 3.495 → 4.126, 4.049 → 4.036
and 4.039 → 4.179 µs per man, on a host whose figures drifted upward
across the whole series — three of the four pairs are "slower", which for
strictly less work is a statement about the machine, not the change. The
`bench-render` pairs said the same thing louder: 100.54 → 80.00 ms and
63.15 → 60.97 ms of derivation, where the same build measured 100.54 and
63.15.

So: **no claimed saving.** It is kept because it is provably equivalent
(21,096 drawn men compared bit for bit, 4,162 of them over blocked
ground), because it is strictly less work on a path that already knows
the answer, and because it makes the code say what it means. If a number
is ever wanted for it, take it on an idle machine — this project's own
standing rule about wall clocks and hosts applies to its own
micro-optimisations too.

The rest is deliberately not done. The honest reading of #244 after #245 is that
its 30% is gone, and **the biggest remaining number in the client's frame
is #262's quadratic jostle gather at 152 ms** — 39% of the frame against
the clamp's 3%. Spending a rule a player can see to chase 3% while that
sits there would be the wrong trade twice over.

## Revisit trigger

A map preset where far more men stand over blocked ground — `islands`
(~71% water) is the obvious one and is not measured here — or a change to
the LOD tiers that makes distant squads draw many men again. Either moves
the 9% this rests on, and the number to re-take is the interleaved
`--clamp` pair above.
