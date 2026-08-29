# D-20260828 · 2026-08-28 · Provisional — an AI invests in what it cannot walk to

**Decision:** naval stage 7's DECISION LAYER (`docs/plans/naval.md` §6.1,
§6.3), and an explicit statement of what the rest of stage 7 is blocked
on. Four clauses:

1. **The naval trigger is REACHABILITY, read off what the AI knows.**
   "Does my landmass contain a known enemy building or spawn?" No map
   carries a naval flag; on `continents` the answer is almost always yes,
   so the behaviour costs nothing where it is not wanted.
2. **Knowing of no enemy is not a reason to build a navy.** An AI that
   has scouted nothing says no. "I have seen nothing, so there must be an
   ocean between us" is how an AI on an ordinary land map talks itself
   into a fleet before it has scouted.
3. **An investment is a named, ordered list of steps**
   (`ai_investment.gd`), not a chain of `if`s — dock, transport, embark,
   landing. That shape is the reusable half **#337 (walls-AI) is meant to
   take**, and it is why the harness can say *which* leg broke.
4. **`AiProfileDef.naval_commitment` is a knob, never a bonus.** It
   decides how much of the AI's own army is willing to sail. No profile
   gets a cheaper dock, a faster hull or sight of the far shore
   (D-20260818-ai-profiles-are-data, clause 1).

## Rationale

D-076 shipped walls, gates and a walkable wall-top tier, and its entry
ends: *"no AI behaviour for building or using walls/gates exists yet —
`just ai-ladder` cannot exercise any of this feature until an AI player
is taught to want one."* Sixteen days later that was still true, and it
is exactly why #210 (an auto gate never opened for an ally) sat
undetected: **the estate had no way to run the feature.** #337 is that
gap filed again.

§6 therefore treats the consumers as part of the feature. This entry is
the half of them that can be written and tested **now**, before the
simulation can sail — deliberately, because a decision layer that arrives
after the behaviour is a decision layer nobody reviews.

**Why the trigger is not a map flag.** A flag has to be maintained per
map and is wrong the moment a preset's sea level moves. Reachability is
derived from the same component walk spawn placement already uses, and it
degrades correctly on every map that is not an archipelago.

**Why it is asked of `ClientState`.** D-051's whole argument is that an
AI win means something because the AI is a client. An AI that read the
map would answer sooner and better, and would not look like a bug — it
would look like a good AI.

## What stage 7 does NOT deliver, and why

The cut-list's done-condition is **"a landing happens in a played match,
and the gate fails when it does not"**. The second half is achievable
today; **the first is not**, and it is not a matter of effort:

- **Ships cannot move.** `SquadSim.is_passable` does not dispatch on the
  water domain and no water flow field exists — that is stage 2, which
  was being rebuilt while this was written. `set_navigable`'s own doc
  comment says so: *"nothing paths on it today."*
- **There is no naval map.** `islands` was retired (#280/#299) and
  `maps/isles.tres` is stage 9's. §6.2's gates are specified *on an
  islands map*, and there is not one to run them on.

So an AI could be given the full behaviour and **no landing could
result**, on any map, however committed the profile. Shipping AI naval
behaviour that cannot be run would BE the D-076 mistake rather than the
fix for it, which is the argument §6 opens with. The behaviour, the
`AI_STATS` keys that count it, the bot's crossing and the `beachhead`
scenario therefore land **with stage 2**, when they can be exercised —
and `bot_naval.gd` is written now so that half has no excuse left.

**What stage 4 got right, and it is worth recording**: embark and landing
ride the ORDINARY move order — a squad ordered onto a hull's cell boards
it, a laden hull ordered at land records a landing — so no new opcode is
needed and §2.4's "orders never choose a domain" survives. Nothing in
stage 7 needs a wire change either.

## Rejected alternatives

- **Shipping the AI behaviour anyway, unexercised.** See above. It is
  the defect §6 exists to prevent, wearing this feature's name.
- **A `naval: true` flag on a MapConfig.** Maintained per map, wrong the
  moment a preset's sea level moves, and it would let the AI want ships
  on a map with no water.
- **Triggering on "I know of an enemy across water"** rather than "every
  enemy I know of is across water". An AI that sails off to an island
  while somebody marches on its town hall. Observed to fail.
- **A behaviour tree or goal stack** for `ai_investment.gd`. It answers
  one question — which step is next — from a list the caller supplies,
  and holds no state. A framework would have to be understood before
  either feature could be.
- **Letting `share_of` round to zero.** An investment allowed to take a
  fraction that rounds to nothing reports itself active and never moves.
  It floors at one — except at commitment zero, which is the one case
  that must send nobody, and that guard is in the same function as the
  rule. The first version left it to the caller and
  `AiNaval.sailing_party(8, 8, 0.0)` put a squad to sea on its first
  test.

## Consequences

- **27 tests, every one observed to fail**, including the two that are
  really about this project's habits: an inert knob (every shipped
  profile committing the same fraction — `gather_speed`'s mistake, one
  feature later) and a profile that declines to sail sailing anyway.
- **`#337` has its machinery.** Walls reuse `AiInvestment` with a
  different trigger and different steps; nothing in it names water.
- **Three of the four steps could already succeed** once the behaviour is
  wired — dock (stage 3), transport (stage 6), embark (stage 4 spawns
  hulls at a dock's water side). Only the landing waits on stage 2, so
  the ordered vacuity guards will report *"stuck at landing"*, which is
  the correct and useful state rather than a bare zero.

## Revisit trigger

Stage 2 landing. At that point the behaviour, the `AI_STATS` keys, the
bot's crossing and the crossing fixture are writable and runnable, and this
entry gains an amendment recording the first match in which a landing
actually happened — which is the criterion, and is not met yet.

---

**Amendment, 2026-08-28 — `should_invest` is gone, subsumed by the shared
decision** (`D-20260828-one-ai-investment.md`, #365).

This entry's `ai_investment.gd` and #348's `static_defence.gd` were built
the same day, by two workers who could not see each other's trees, to
answer the same question. They are one file now, and it keeps this
entry's name because "an AI invests in a capability" is the general
question and "static defence" is one instance of it.

What moved:

- `AiInvestment.should_invest(wanted, commitment)` is **deleted**. It is
  `wants_to_invest(1.0 if wanted else 0.0, commitment, 0, 0)`, and a test
  pins that equivalence over the whole truth table so the opponent this
  entry describes decides exactly as it did.
- `step`, `next_step`, `progress` and `share_of` are unchanged, including
  the zero-commitment guard this entry records finding.
- The file gained #348's pressure model, reserve, price and scarcest
  shortfall. **Naval inherits the last of those for free**, which
  matters: the AI had never gathered stone or gold in any match ever
  played, and a dock costs both wood and stone.

The reachability trigger, the landing target, the step list, the bots'
crossing and this entry's Provisional status pending naval stage 2 are
all untouched.
