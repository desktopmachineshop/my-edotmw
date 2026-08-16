### D-095 · 2026-08-14 · Accepted — parallel dev instances are isolated by construction

**Decision:** every checkout of this repo — the owner's main clone and
each Claude Code agent worktree — is its own **dev instance**, and an
instance can only ever start, see, and stop its own servers and
clients. The identity has ONE definition, `instance-id.sh` at the repo
root, which derives:

- **instance name** from the git branch (agent worktrees:
  `claude-<session>`; the main clone: `main`), sanitised into a docker
  project fragment;
- **UDP port** as a stable hash of that name into 20000–29999 —
  deliberately far from the historical shared 4433, so a hardcoded 4433
  that sneaks back in fails to connect rather than connecting to the
  *wrong* server;
- **compose project** `edotmw-<instance>`.

The justfile evaluates the script for its `instance`/`port` variables
and threads them everywhere the old shared literals were: every
`docker compose -p`, every `--name`d container, the `down` recipe's
stray-container label sweep, and every client/bot `--port`. The compose
file publishes `${EDOTMW_HOST_PORT}:4433/udp` — **in-container the
server still listens on 4433**, so the bots and `client-test` services
(in-network, reaching `server:4433`) needed no change, and per-project
compose networks keep them scoped for free. The GUI client accepts
`--instance` and puts it in its **title bar** with the endpoint
(`eDotMW — claude-foo  [127.0.0.1:24817]`), so several clients on one
desktop are tellable apart before clicking anything. `just instance`
prints a worktree's identity. `just quick-test` resolves a new
`SANDBOX=auto` parameter to **on** for agent instances (`claude-*`) —
an agent going straight into quick launch is always dev-testing, so it
gets D-077's sandbox by default — and off for the main clone.

**Why:** parallel agents kept killing each other's test sessions. Both
halves were structural: `just down` (and every recipe's teardown trap)
removed containers in the one pinned `edotmw` project regardless of who
started them, and with one shared port a client connected to whichever
instance's server held 4433 — CLAUDE.md already records a load-test
failure mis-diagnosed for a session because of exactly that stray-server
shape. Fixing it by convention ("agents, be careful") is the
declared-but-unenforced pattern this project keeps paying for, so the
isolation is derived, not remembered, and
`tests/test_multi_agent_isolation.gd` fails if a shared literal
(`-p edotmw`, a fixed `--name`, a hardcoded host port or `--port=4433`)
reappears in the justfile or compose file.

**Sharing is explicit, never accidental:** `EDOTMW_INSTANCE` /
`EDOTMW_PORT` override the derivation when the owner deliberately wants
two checkouts talking to one server; nothing else crosses instances.

**Rejected alternatives:** a lock file or registry of running instances
(state to leak, and D-014's teardown discipline says nothing may
outlive its recipe); letting agents share one server with per-agent
match ids (the server is authoritative per-process — one agent's
restart still kills everyone); random free-port allocation at launch
(a client started later could no longer find its server — the port must
be a pure function of the identity).

> **D-087 through D-094 are the M8 planning session, 2026-08-14.** Run
> the way the M9 session (D-068–D-074) was: everything in them is design,
> no code was written, and the owner made the four calls that shape the
> rest in the same session (scope, hosting, whether 20 players is a
> design target, saves). They close Q3, Q5, Q10, Q11, Q13 and Q14 — the
> entire "Blocking M7 / product-level" block of section 2, which dates
> from when Steam was numbered M7. IDs were checked free against `main`
> at fd4ee6e immediately before writing, per the renumbering lesson in
> the editorial note below.
