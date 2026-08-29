<!--
This template exists because CI arrived (#290), and CI makes the one
thing it cannot check cheaper to forget.

A green badge is read by more people, less carefully, than a recipe
somebody typed. D-022's audit block is this project's foundational
testing lesson: `test-load` once reported clean while every bot had
exited non-zero, and its desync scan passed vacuously for a whole
milestone while hiding a live bug.

So the perturbation question is asked HERE, of a human, rather than in a
workflow — a runner cannot assert that you watched your own check fail.
-->

## What and why

<!-- What changed, and which issue or decision it answers. -->

## Which check did you watch fail, and how?

<!--
REQUIRED for anything that adds or changes a check. Name the perturbation
and what it printed. "Observed to fail before being trusted" is the
project's standing rule (D-022, CLAUDE.md) and it has caught vacuous
guards repeatedly — including twice in the week CI was added, one of them
in the CI author's own test.

Example:
  - reverted the fix -> `test_x` red with "two squads of thornwood_levy
    could not take a town centre (36 HP left)"; restored -> green.

If this PR adds no check, say "no new checks".
-->

## Decisions

<!--
A new decision is a NEW file, `decisions/D-YYYYMMDD-slug.md` — never an
append, never a renumber (decisions/README.md). If this changes an
architectural rule and there is no entry, say why not.

If it touches something a `docs/status/` file describes, edit THAT file —
never recreate a shared monolith (D-20260816-decision-docs-split). Status
docs are `@`-imported into every session, so a wrong sentence there is
handed to every worker on the project.
-->

## Measurements

<!--
Quote figures with their conditions, per CLAUDE.md's standing rules:
  - µs/squad ALWAYS with its squad count
  - an ai-ladder result ALWAYS with its cap, and now with which roster
  - a memory figure with players, squads and cells
  - a frame time with the hardware it was taken on

A single green run is not a measurement. If a number was taken on a
loaded host, say so — this repo has thrown away three milestones' worth
of figures to host contention.
-->

## Risks and what is not claimed

<!-- What you deliberately did not do, and what a reviewer should doubt. -->
