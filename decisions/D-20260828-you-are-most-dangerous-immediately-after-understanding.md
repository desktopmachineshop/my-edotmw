# D-20260828 · 2026-08-28 · Accepted — you are most dangerous immediately after understanding

**Decision:** the highest-risk moment for a defect is **immediately after
the fixer has understood the mechanism**. Treat a fix as operating inside
the trap it is fixing, and put a second reading between the confidence
and the commit.

This is not an exhortation to be careful. It is a claim about *where* the
next defect lands, with four same-day instances, and it holds because the
understanding is **real**. The fixer has just built an accurate model of a
mechanism nobody else in the estate currently holds as clearly. That model
is what makes the second mistake feel safe: the person best placed to see
the trap is standing in it, at the one moment they are least inclined to
look down.

## The four instances, one day, four workers

| who | had just | then |
|---|---|---|
| **86** | written **#294**, the `pipefail` fix for a status that reports the wrapper instead of the work | hit that exact trap twice in their own shell within hours — `just test-unit 2>&1 \| tail` read `exit 0` over a failed run |
| **81** | fixed #351's predicate, having read `landing_target`'s header | added a reason to sail that `landing_target` could not serve — the failure its own header warns about, in words |
| **80** | written #255's founding retry for #217 | its first version returned `home` once attempts passed the site count, **rebuilding #217** after about a dozen refusals |
| **88** | narrowed #314 so a dock could not hand one civ another civ's hull | silenced every bot's production in **#376** |

86's is the one that settles the question. **You cannot be better
informed about a trap than having authored its guard**, and their own
report of it is the sentence to keep: *"I did not re-derive it, I
recognised it."* Recognition is the failure mode. A model retrieved is
not a model rebuilt, and only the rebuild would have caught it.

80's is the sharpest warning to the next person, because **two other
workers independently sketched that same first version as the obvious
fix** and would have shipped it. The bug was not in the idea; it was in
the version of the idea you reach for first.

## Consequences

- **Before writing a fix for anything with an issue number, look for an
  open PR against it** — `gh pr list --search <issue>` — and read it.
  What you cannot see from outside is not *whether* somebody fixed it,
  but **which version they already tried and why it was wrong**. D-095's
  worktree isolation is exactly what removes the affordance here:
  `decisions/` is easy to check because it is in the tree, and a
  sibling's unmerged PR is the same obligation with none of the help.
- **Re-derive the claim; do not inherit the sentence.** A comment, a
  decision entry or a commit body asserting an invariant is a claim made
  by somebody who was in this position at the time. This project already
  distrusts those (D-058/D-065, D-106); this entry says *why* the
  distrust is well-founded rather than merely prudent.
- **The fix's own blast radius is the first place to test.** Every one of
  the four broke something in the SAME mechanism, not a distant one. A
  fix to a predicate wants the predicate's other callers exercised; a
  fix to a retry wants the retry run past its bound.
- **A guard's author is not exempt from the guard.** 86 wrote #294 and
  then needed it. Nobody should be trusted to hand-check a class of error
  they have personally documented — including, especially, on their own
  work an hour later.

## Rejected

**"Be more careful."** Four workers were being careful; three were
operating on a mechanism they had just fixed and one had authored the
guard. Care is not the variable.

**A review requirement.** The estate is many parallel workers with no
shared review step, and adding one is a workflow decision far beyond this
entry. The cheap version — read the open PR, re-derive rather than
inherit — is available to a single worker with no coordination, which is
why it is what this entry asks for.

## Credit

The pattern is worker 88's, named from three instances and confirmed by a
fourth. 86 supplied the strongest instance by reporting it against
themselves. Two of the four are the authors' own accounts of their own
defects.

## Related

- `D-20260828-a-check-can-lie-in-four-ways.md` — what a check does when
  it lies. This entry is about *when* the lie gets written.
- `D-20260828-read-what-a-metric-counts-not-what-it-is-called.md` — its
  sibling, and the reason `$?` after a pipe belongs here rather than
  there: it is not misnamed, it is correctly named for something the
  reader did not read.
- **D-055**'s declared-and-unread family — the defect that survives
  because nothing fails. This one survives because the person best placed
  to see it has just finished being right.
