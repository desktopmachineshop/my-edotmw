# D-20260817-recipe-args-are-positional · 2026-08-17 · Accepted

**A recipe argument `just` cannot use fails LOUDLY, and "is this an
agent's checkout?" is derived once, not pattern-matched.**

## Decision

Two rules, one root cause (#89, found in the P04 sandbox playtest of
#45):

1. **Every numeric recipe parameter is validated before the recipe acts
   on it.** `recipe-arg.sh` is the one checker — `int`, `num`, `enum` —
   and a value it rejects exits the recipe non-zero with a message that
   names the trap. It is a plain shell script, like `instance-id.sh`,
   so a GUT test can execute it and watch it reject a value; a `just`
   recipe is unreachable from the test estate.
2. **`instance-id.sh agent` is the one definition of "is this a
   disposable agent worktree or the human's own checkout?"**, stated as
   a list of what is NOT an agent's (the default branch: `main`,
   `master`), overridable with `EDOTMW_AGENT`. `quick-test` reads it to
   resolve `SANDBOX=auto`; nothing pattern-matches branch names itself.

## Rationale

`just` takes recipe arguments **positionally**. An argument written
`NAME=value` after a recipe name does not set `NAME` — it binds the
whole string to that recipe's FIRST parameter. Every consumer downstream
reads it with `int()`, which is **0** for any string it cannot parse. So
each of these ran, cleanly, doing something other than what it says:

| typed | actually sent | effect |
|---|---|---|
| `just quick-test SANDBOX=1` | `--seed=SANDBOX=1 --sandbox=0` | seed 0, **sandbox off** |
| `just run-server AI=3` | `--ai=AI=3` | **zero AI opponents** |
| `just run-server LOBBY=1` | `--ai=LOBBY=1` | no lobby, no AI |

The first two are invocations **this project's own documentation
prescribed** — `CLAUDE.md`'s multi-agent section ("Pass `SANDBOX=0/1` to
override either way") and `docs/status/m6.md` (`just run-server AI=3`
seats opponents). The third is quoted in D-075, which records a server
found ticking an empty world **for six hours** with no opponent for
exactly this reason.

**The class was known and worked around rather than fixed.** The `lobby`
recipe has carried a comment describing this trap since D-048 and
existed partly *because* of it — a second recipe grown to route around
one instance of a general defect, while every other recipe stayed
exposed. That is the shape this project keeps paying for: the mechanism
was understood, written down, and nothing asserted it.

The second half is the *same* failure in the other direction. `SANDBOX=
auto` resolved through a whitelist of agent branch prefixes
(`claude-*`) living in the justfile. When the agent harness started
branching `ao/<project>/<session>` — sanitising to `ao-my-edotmw-49-root`
— every agent worktree silently resolved to "the human's checkout" and
launched **without** D-077's sandbox and its cheats panel. A whitelist
of naming conventions is a check that goes stale the moment something
upstream is renamed, and its failure is a false NEGATIVE, which is
silent by construction. The set that does *not* change is the other one:
the human's own checkout sits on the default branch.

## Rejected alternatives

- **Add `ao-*` to the `claude-*` case** (the issue's first suggestion).
  Fixes today's harness and re-arms the same trap for the next one; the
  defect is the whitelist, not its contents.
- **A `just` setting that rejects `NAME=value` arguments.** None exists.
  Overrides must precede the recipe name, and even a *declared*
  variable's name binds positionally when written after it — verified.
- **Validate inside the consumers (`server.gd`'s `_parse_args`).** The
  wrong value never reaches a consumer that could name the cause: by
  then it is `"SANDBOX=1"` in a `--seed` slot with no idea what a recipe
  parameter is. Assert the value on the near side of the boundary, where
  the mistake is still legible.
- **Make the check a `just` dependency so it runs before `_import`.**
  It would save ~10 s on a mistyped command, at the cost of a private
  recipe layer and a variadic-argument dance for `enum`. Not worth it:
  the failure is loud either way.
- **Detect an agent worktree structurally** (`git rev-parse --git-dir`
  != `--git-common-dir`, i.e. a linked worktree). Genuinely
  naming-independent, but it makes the negative case untestable from
  within a worktree — every test run by an agent would report "agent"
  whatever the instance name said. A rule whose negative half cannot be
  tested is how this bug survived.

## Consequences

- `recipe-arg.sh` is called by every recipe taking a numeric parameter:
  `quick-test`, `run-server`, `lobby`, `run-client`, `run-bots`,
  `test-load`, `test-scenario`, `test-client`, `ai-ladder`,
  `bench-render`, `lobby-shot`, `gen-terrain-preview`,
  `gen-model-preview`, `gen-cover-preview`, `gen-forest-preview`,
  `gen-terrain-shot`. `tests/test_recipe_args.gd` PARSES the justfile
  and fails if a parameter with a numeric default (or no default at all)
  is not checked in its own recipe body — so a new recipe inherits the
  rule without anyone remembering it. That is the "assert the caller
  exists" test D-106 wrote down.
- **A human on a feature branch in their own checkout now gets the dev
  build** where before only `claude-*` did. That is deliberate: it is
  visible (`quick-test` prints `sandbox ON (dev build)` — it printed
  nothing at all before), and one positional argument turns it off
  (`just quick-test 1337 0`). The old failure was neither.
- **Results measured through a mistyped invocation are suspect.**
  Anything an agent session recorded from `just quick-test SANDBOX=1`
  ran with sandbox OFF and seed 0 — not 1337 — so it is neither the
  build nor the world it claims. Anything from `just run-server AI=3`
  ran with no opponents at all. `just ai-ladder` is unaffected (it
  builds its flags itself, and D-107 already voided its old numbers);
  `test-load`, `test-scenario` and `test-client` are unaffected in
  practice because their arguments have always been typed positionally.
- Amends D-095: `instance-id.sh` gains a third mode, and the justfile no
  longer re-derives any part of instance identity — including the
  agent/human distinction, which it had been re-deriving by hand.

## Revisit trigger

A recipe parameter that is neither numeric nor an enum starts carrying
load (a map id, a scenario name), and a typo in it silently selects a
default instead of failing — `--scenario=` already parses an empty id as
"no scenario". At that point `recipe-arg.sh` grows a `oneof-file` kind,
or those recipes validate against the roster they read.
