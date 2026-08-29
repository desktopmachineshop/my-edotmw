# D-20260828 · An imported doc names the code it is about

**Date:** 2026-08-28
**Status:** Accepted
**Issue:** #291, from the gap assessment (`docs/plans/gap-assessment.md` §5.4)

## Decision

**Every reference an imported doc makes must resolve, enforced by a
test.** `tests/test_status_docs.gd` scans `CLAUDE.md` and all 31 files
under `docs/status/` and fails if any cited decision id, backticked file
path or backticked `Class.member` does not exist. Exemptions live in one
allowlist, each carrying its reason, and a second test fails if an
allowlisted name comes back into existence.

**And a convention, for the class no scan can settle: a status doc's
behavioural claim names the file it is about.** Not enforced
mechanically — see "what was tried and rejected", which has the
measurements.

**Generation is rejected. Universal stamping is rejected.** Both were
#291's suggestions; both were measured before being turned down.

## Rationale

### Why these files are different from every other doc

`CLAUDE.md` `@`-imports every file under `docs/status/` — **3,372 lines
across 31 files** — so they are not documentation a reader may consult.
They are **instruction-grade**: handed to every worker on the project,
before they read a line of code, as though they were the ground rules.
A wrong sentence there is not a stale doc, it is misinformation with the
authority of a specification.

### The defect this was filed for turned out to be the opposite of the one reported

#291 came from the gap assessment, which cited `docs/status/m6.md`
paraphrasing D-107 as *"It retries against a different site now"* — a
claim, said §5.4, that the decision never made and the code did not
implement.

**Checked: the sentence is TRUE, it is in `load-testing.md` rather than
`m6.md`, and it is about `bot_client.gd`.** `_found_town_hall` sites its
retry at `offsets[_build_attempts % offsets.size()]` and has for as long
as D-107 has existed. What the sentence does not do is say *which of the
two actors it means* — the paragraph is about a bot, the surrounding page
is about load tests, and D-107 is about latching on the effect, which
both the AI and the bot do.

**Two readers supplied the wrong actor**: #217's filer, who used it as
evidence that `ai_player.gd` retried at a different site (it did not, and
that was a real bug, fixed separately), and then this project's own gap
assessment, which repeated the claim without re-checking it. Three
documents in a row asserting something none of them had verified is
exactly the failure #291 is about — arriving, as it happens, through
`docs/plans/` rather than `docs/status/`.

So the observed defect is not falsehood. **It is missing attribution**, and
that reframes what a guard should ask for: not *is this true* — which no
scan over English can answer — but *what is this about*.

### What the scan can settle completely, measured

Reference integrity, across the imported set on `main` at `cc2f4c6`:

| reference class | found | unresolved |
|---|---|---|
| decision ids (`D-YYYYMMDD-slug` and legacy `D-NNN`) | 154 | **0** |
| backticked file paths | 87 | **3**, all deliberate |
| backticked `Class.member` | 73 | **0** |

The three are a naming template in `decisions/README.md`'s own rules, and
two files D-20260823 deleted which the docs correctly describe in the
past tense. So the check is adoptable **today**, at the cost of one
three-entry allowlist, and it locks in a state that is currently clean.

That is not nothing: it catches the drift class where code is renamed or
deleted and the imported docs are not — the class that would otherwise
accumulate silently, because nothing else reads these files mechanically.

## What was tried and rejected, with the measurements

Recorded because "we tried the clever thing and here is the number" is
worth more than "this is hard", and because the next person will have the
same three ideas.

**1. Generate the status docs from code or tests. — Rejected.**
They are not derivable. `docs/status/` carries measurements with their
conditions (*"52.1 ms early and 181.1 ms three hours later"*), rejected
alternatives, caveats about hosts and hardware, and the reasoning behind
calls that no longer apply. None of that exists in any source file.
Generation would delete the half of these documents that is worth
importing and keep the half a reader could get from `ls`.

**2. Stamp every claim with the test that proves it. — Rejected on cost
and on honesty.** Measured: **168 paragraphs open with a bold headline
claim; 13 name a test.** That is 155 retrofits — and most of the 155 are
*measurements* or *history*, which have no guard to name, so the stamps
would be invented. A false stamp is strictly worse than none, because it
converts "unverified" into "verified" at no cost to the writer. Note
where the concentration is: `m6.md` has 18 headline claims and cites 0
tests, and `rtw-battles.md` has 15 and cites 0.

**3. Require a behavioural claim attributed to a decision to name code or
a test. — Rejected as too noisy.** A conservative pattern (the project's
own tell from D-100 — behaviour in the passive or present tense) matched
**4 paragraphs**, which sounded affordable until they were read: two are
*history* (a past defect, described in the past tense) and one is
*advice* about durations. So even at n = 4 the pattern is mostly false
positives, and a regex over English will not get better with tuning. This
project's own rule applies — *a guessed constant that red-flags a good
model is worse than no check, because the next person raises it until it
passes.*

**4. Verify quoted attributions verbatim. — Rejected, and this was the
most promising one.** If a doc quotes a decision, the quoted words should
appear in that decision. Mechanical, non-fuzzy, and it enforces exactly
the right habit (quote, do not paraphrase). Measured: **42 quoted spans
sit near a decision citation, and 25 do not appear in any decision.**
Reading them, almost all 25 are the extractor's fault — the docs quote
*playtest reports* (*"units all pile on top of each other"*), *bug
reports* (*"the forests arrived all at once"*) and *code comments*
(*"server.gd needs a socket and a scene tree"*) far more often than they
quote decisions, and nothing in the markup distinguishes them. Telling
them apart needs the docs to MARK which quotes are decision quotes —
which is idea 2's retrofit cost wearing a different hat.

## Rejected alternatives (of shape, not of mechanism)

- **Stop importing the status docs.** Would fix the instruction-grade
  problem by deleting the value: these files are why a session starts
  knowing that a green sweep is not a green server, and that a picture
  catches what a counter cannot.
- **Split each file into a guarded "what is true now" block and an
  unguarded history section**, and enforce the block. The right long-term
  shape and the honest answer to #291's ambition. Not taken now: 31 files
  of judgement about which sentences are guarantees, and a half-filled
  block would be worse than none. Named as the revisit trigger.

## Consequences

- **The imported set can no longer name something that does not exist**,
  and the check runs in `just test-unit` like every other.
- **The allowlist cannot rot.** An exemption whose name exists again
  fails, and every entry must carry a reason of more than twenty
  characters — a scan whose exemptions nobody prunes stops scanning.
- **`CLAUDE.md` must import every file in `docs/status/`.** A status doc
  that exists and is not imported is the ground rules silently dropping a
  page, which is the same defect one level up; the test fails on it.
- **This guards references, not truth, and the test says so in its own
  header.** Anybody reading it should not conclude the imported docs are
  verified.
- **One live instance is fixed here**: `load-testing.md`'s D-107
  paragraph now names `bot_client.gd._found_town_hall` and its actual
  expression, and records that the unattributed version misled two
  readers. **`docs/plans/gap-assessment.md` §5.4 carries the same error
  and is on an unmerged branch (PR #265)** — flagged for correction there
  rather than edited from here.

## Revisit trigger

- **A status doc grows a "what this guarantees" block.** If the split in
  the rejected alternatives is ever wanted, this test is where the block
  gets enforced, and idea 4 (verbatim quotes) becomes cheap the moment
  decision quotes are marked as such.
- **The allowlist reaching, say, ten entries.** Three deliberate absences
  is a healthy number; ten would mean the docs describe a project that no
  longer exists, and the answer then is to prune the docs rather than
  grow the list.
- **A second directory becoming instruction-grade.** `docs/plans/` is
  not imported today and the error above lives there, so the scan does
  not cover it. If anything under `docs/plans/` is ever `@`-imported, it
  joins this test's scope on the same day.
