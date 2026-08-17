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
3. **And the same check again on the far side of the boundary.**
   `cmd_args.gd` is the one parse of `--key=value` and the one numeric
   check; `server.gd`, `client.gd` and `bot_client.gd` refuse to start
   on an argument that is not the number they are about to read it as.
   Raised by #98, and right: `docs/COMMANDS.md` tells you to launch the
   binary by hand when a recipe does not expose the flag you want, and
   no recipe check covers that path. The three files carried a
   byte-identical private copy of the parser, none of which a GUT test
   could reach.

## Rationale

`just` takes recipe arguments **positionally**. An argument written
`NAME=value` after a recipe name does not set `NAME` — it binds the
whole string to that recipe's FIRST parameter. Every consumer downstream
reads it with `int()`, and **GDScript's string-to-int conversion strips
non-digit characters rather than failing** — measured in the shipping
container, Godot 4.7.1:

```
int("SANDBOX=1") = 1     int("AI=3") = 3     int("LOBBY=1") = 1
```

So each of these ran, cleanly, doing something other than what it says:

| typed | actually sent | effect |
|---|---|---|
| `just quick-test SANDBOX=1` | `--seed=SANDBOX=1 --sandbox=0` | **sandbox off**, and the world is seed **1**, not 1337 |
| `just run-server AI=3` | `--ai=AI=3` | 3 AI seats — right by accident |
| `just run-server LOBBY=1` | `--ai=LOBBY=1` | **no lobby**, and one AI nobody asked for |

The first two are invocations **this project's own documentation
prescribed** — `CLAUDE.md`'s multi-agent section ("Pass `SANDBOX=0/1` to
override either way") and `docs/status/m6.md` (`just run-server AI=3`
seats opponents).

**That `int()` behaviour makes this worse, not better, and it has
already misled a decision entry.** A mistyped argument does not produce
an obviously wrong 0 — it produces a *plausible small number*, which is
exactly the kind of value nobody questions. D-075 records a server found
ticking an empty world for six hours after `just run-server AI=1` and
attributes it to this trap "so `int()` read 0 and it never had an
opponent either". It read **1**: the seat was there, and the reason it
did nothing was D-107's — an AI's founding order sent before the match
was running and dropped. The positional trap is real and was taking the
blame for a bug it did not cause, which is its own argument for making
it fail loudly instead of leaving it to be reasoned about after the
fact.

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
- **Validate ONLY inside the consumers.** Rejected as a replacement, and
  adopted as the second line (clause 3): a consumer cannot name the
  cause — by then it is `"SANDBOX=1"` in a `--seed` slot with no idea
  what a recipe parameter is — so the near-side check has to exist too,
  and `CmdArgs.complaint` carries the recipe hint across for the case
  where the far side is all there is.
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
- **Results measured through a mistyped invocation are suspect, and the
  suspect set is narrower than it first looked.** Anything an agent
  session recorded from `just quick-test SANDBOX=1` ran with sandbox
  **off** and on **seed 1**, not 1337 — a different world, and not the
  build it claims. Every AO worktree (`ao-*`) running plain
  `just quick-test` also ran without sandbox, whatever it typed, for as
  long as that naming convention has been in use. `just run-server AI=3`
  turns out to have seated its 3 opponents after all. `ai-ladder`,
  `test-load`, `test-scenario` and `test-client` are unaffected: the
  first builds its flags itself, and the rest have always been typed
  positionally.
- Amends D-095: `instance-id.sh` gains a third mode, and the justfile no
  longer re-derives any part of instance identity — including the
  agent/human distinction, which it had been re-deriving by hand.
- **A source-scanning test cannot see a script that does not compile.**
  The first version of the far-side guard declared `var bad` where
  `server.gd`'s `_ready` already had one; `test_recipe_args.gd`'s scan
  for `CmdArgs.invalid_integers(` passed on the text while `server.gd`
  failed to parse. `tests/test_scripts_parse.gd` is what caught it —
  worth knowing before writing another scan-shaped test, because the
  scan will happily go green over a file the engine has thrown away.

## Revisit trigger

A recipe parameter that is neither numeric nor an enum starts carrying
load (a map id, a scenario name), and a typo in it silently selects a
default instead of failing — `--scenario=` already parses an empty id as
"no scenario". At that point `recipe-arg.sh` grows a `oneof-file` kind,
or those recipes validate against the roster they read.
