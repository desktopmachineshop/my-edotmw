### D-20260828 · Accepted — one mechanism by which an AI invests, and the half neither design had

**Decision:** `ai_investment.gd` is THE mechanism by which an AI decides
to spend on a capability it has not got. It carries both halves of the
question and both features call it:

| | comes from | what it answers |
|---|---|---|
| `threat_pressure` | #348 | how much of a case is there, from a threat report |
| `wants_to_invest` | **both, reshaped** | is that case enough for this opponent, and is it capped |
| `can_afford_with_reserve`, `cost_of`, `scarcest_shortfall` | #348 | can I pay for it without starving the economy, and what am I short of |
| `step`, `next_step`, `progress` | #342 | what is the next unmet step of getting it |
| `share_of` | #342 | how much of the army this claims |

`static_defence.gd` (#348) is **deleted**, its whole contents preserved
here. `AiInvestment.should_invest` (#342) is **deleted**, subsumed by
`wants_to_invest` and pinned by a test over its entire truth table.

Filed as gap **I4** of `docs/plans/gap-assessment-2.md`, ticket #365, and
written by a third party with no stake in either.

---

## What actually happened, because it is not what the ticket says

The ticket says two workers "built it twice against instruction". They
did not. Both were told to share the machinery, **and there is no
mechanism by which either could have seen the other's tree** — the only
shared surface is `main`, and neither chain reaches it. Session 79
checked for stage 7's machinery, found none, built the seam and posted
its interface on the naval PR; by then stage 7 was already written. The
assessment says exactly this, and it is worth repeating at the top of the
reconciliation because **the fix for the process is not "read more
carefully"** — it is landing decision entries ahead of their code, which
is that document's own proposed ticket 3.

## The two designs had answered different halves

This is the finding, and it is why the merge is not a coin flip.

| | #348 `StaticDefence` | #342 `AiInvestment` |
|---|---|---|
| is now the moment? | a **measured** pressure model — contact, hostiles near, a horizon, losses survived, army in the field | a boolean trigger the caller supplies |
| how readily? | appetite as a **threshold on the case** | `commitment > 0.0` |
| can I pay? | reserve share, price from the def, **scarcest shortfall** | — |
| what is next? | — | ordered **steps**, progress, share of the army |
| domain-free? | yes, scan-enforced | yes, by construction |

Each had assumed the other's half was the easy part. #348's pressure
model is the half that turns "the AI should defend" into decisions a
ladder can show; #342's step list is the half that turns "the AI should
have a navy" into a plan whose failure says **which leg broke** rather
than reporting a bare zero. Neither is redundant and neither subsumes the
other.

## The reconciliation is one signature

```gdscript
# before, #348 — computes the case itself, so it can only gate a defence
static func wants_to_invest(threat: Dictionary, economy: Dictionary,
        appetite: float, standing: int, cap: int) -> bool

# before, #342 — takes a boolean, so it can gate anything and express nothing
static func should_invest(wanted: bool, commitment: float) -> bool

# now
static func wants_to_invest(case: float, appetite: float,
        standing: int, cap: int) -> bool
```

**Splitting the CASE from the THRESHOLD is what lets one mechanism serve
both, and neither original had it.** #348 fused them, so a naval caller
would have had to describe "there is a known enemy I cannot walk to" as a
*threat*, which it is not. #342 had only a boolean, so it could express
no degrees, no cap, and forced one knob to mean "never/always" at the
same time as meaning "how much".

Two smaller consequences of the split, both load-bearing:

- **`cap = 0` means the investment is not counted in standing things.**
  A wall is bounded by a number of segments; a navy is a *plan* (dock,
  hull, embark, landing) finished by its last step. `next_step` ends the
  second kind, and `wants_to_invest` must not.
- **The old behaviour is asserted, not assumed.**
  `should_invest(wanted, commitment)` is exactly `wants_to_invest(1.0 if
  wanted else 0.0, commitment, 0, 0)`, checked over the whole truth
  table — because "the old behaviour is a special case of the new one" is
  a claim, and an unchecked claim is how a reconciliation quietly changes
  an opponent.

## The two knobs stay two knobs, and that is not the duplication

`AiProfileDef.defence_appetite` (#348) and `naval_commitment` (#342) both
survive, and a reconciliation that merged them would be wrong. **They are
different traits, and the shipped profiles want them to disagree:** a
cautious opponent should fortify sooner *and* sail less. One knob would
make a defensive profile an eager invader by construction.

What was duplicated was the MECHANISM, not the dials on it. Both are read
through the same function now, so a third capability adds a knob and no
code.

## Consequences

- **`ai_player.gd` has one decision call shape**, used three times: the
  build plan's "what would I buy next", the fortify step, and the sea.
  A source scan asserts all three go through `AiInvestment` and that
  nothing names the superseded class.
- **Naval inherits the economy fix for free, which was #348's own
  argument.** `scarcest_shortfall` exists because the AI's resource
  priorities were a fixed food/wood list, so it had never gathered stone
  or gold in any match ever played, and every wall, gate and tower costs
  stone — the feature was unaffordable *by construction*. A dock costs
  wood and stone. The same line makes both reachable.
- **Every test either design wrote still runs.** `tests/test_static_defence.gd`
  is `tests/test_ai_investment.gd` with its assertions intact; the naval
  suite's decision test now asserts the naval *reading* of the shared
  function rather than a naval copy of it. Four tests are new, and three
  of them exist only because of the split.
- **The domain-freedom scan got wider.** #348's scanned for wall words;
  it scans for `dock`, `ship` and `shore` too, since the file is now
  shared in fact rather than in intent.
- **`gate-check.sh` and the stats line are UNIONS**, not choices: a seat
  that ran only one investment still reports the other's zeros, which is
  how a harness tells "did not do it" from "was never asked".

## What this does NOT decide

The two features' own designs stand. `D-20260828-an-ai-that-fortifies`
keeps its geometry, its gate-sealing rule and its measurements;
`D-20260828-an-ai-invests-in-what-it-cannot-walk-to` keeps its
reachability trigger, its step list and its Provisional status pending
naval stage 2. Both gain an amendment naming this entry as the mechanism
they now share. **Superseded here is the duplication, not either
feature.**

## Revisit trigger

A third capability that wants to invest — an economy expansion, a tech
line — and finds the three questions do not fit. That is the point at
which "is there a case, can I pay, what is next" stops being the shape of
the problem, and it should be a re-decision rather than a fourth private
copy.
