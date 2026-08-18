**Use `just test-load 4 300`** on the current default map.

**The `reveal_events` gate was unreachable on `main` for a day and is
fixed** (D-20260817-load-test-bots-must-manoeuvre, #69/#84). If you are
reading an old branch's failure, or an older copy of this file, the short
version is: the gate was never wrong — **the bots had stopped manoeuvring
at all**, so there was no return leg for it to count.

Both of `bot_client.gd`'s movement mechanisms were dead at once. The
rally/recall pair was a ONE-SHOT at t=0 s and t=8 s, written when a player
started with twelve squads; under D-031's opening a bot owns exactly one
squad then — the founding party, which is at that moment walking off to
plant a town hall and being consumed by it. And the raid alternation is
unreachable: a bot only ever builds a town centre, a town centre
`produces` gatherers only, and the haul loop claimed every crew, so
`raid_pool` was empty on every tick. Four bases quietly chopping wood. The
server log said so plainly and nobody had read it that way — four squads,
eight flow fields and a byte-identical packet count from 20 s to 50 s.

**The map doubling of 2026-08-17 (84×96 → 168×194) makes the gate pass
without fixing any of that, and that is worth being explicit about.** A
`4 300` run on the new map reported `reveal_events=63` where the old map
reported 0 or 1 — because more of a bigger map goes unseen, so hauling
crews wander in and out of each other's vision by accident far more often.
That is the gate satisfied by luck at a larger scale, not by a squad
deliberately breaking contact and returning, and a criterion met by
accident is the shape D-022's audit block was written about. The
manoeuvre is performed now rather than hoped for.

**Read the PER-BOT lines the verdict prints before reading any of the
sums.** Every counter in the VERDICT line is a total across four bots, and
a total cannot say "one of them is not doing the thing" — which is what
three of the five defects behind #69/#84 turned out to be. One run of
`BOT player=…` answered what four runs of aggregates had not.

**Three standing rules come out of it, all already written down here or in
`decisions/`, all paid for again:**

- **When the opening changes, every timing tuned against the old one is
  stale.** Third instance, after `test-load 4 40` and `test-client`'s 15 s
  default. Leg boundaries in `bot_patrol.gd` are events now — the scout
  arrived — with a timeout only as a backstop.
- **A single green run is not a measurement.** This file once said
  "`4 150` is clean" on the strength of one run reporting
  `reveal_events=10`; four subsequent runs across two trees reported 0. If
  you are about to write a duration here, run it more than once.
- **Latch on the effect, not the send** (D-107). A bot's town hall order
  used to set a "done" flag the instant the packet left, so a REFUSED
  opening — a forest on the start, which D-087's 1,920 nodes make likely —
  left that bot with no hall, no crews and no scouts for the whole run
  while its own flag said the opening was handled. It retries against a
  different site now, until a building it owns actually appears. Two of
  four bots were failing to found before this was noticed.

What the bots do now: a share of each one's army (at most one squad in
two, at most two) is held out of the economy and walks in on a neighbour
until they can see it and back out until they cannot, over and over. It
starts from a bot's SECOND hauling crew, so a run that ends before
production has delivered two produces no reveals by construction. The
geometry — 8 cells in, 20 cells out, against a town centre that sees 11
and shoots 6 — is in the decision and asserted against the shipped
resources by `tests/test_bot_patrol.gd`.

- **Duration follows the MAP, and the map doubled on 2026-08-17.**
  Marching time scales with LINEAR size, not area, so the ~150 s that was
  marginal before is roughly 300 s of equivalent marching now. The gates
  that get harder are the contact-dependent ones —
  `casualties_applied`, `conceal_events`, `reveal_events`; the fog
  coverage gates get *easier*, because more of a bigger map goes unseen.
  Re-measure before writing a number here.
- **A reveal needs a conceal AND a return.** `reveal_events` counts a
  squad re-entering vision after leaving it, so it is the LAST of the fog
  criteria to be satisfied and the first to fail.
- **A town hall takes 40 seconds and the founding party is spent on it
  (D-031), so a player owns no soldiers until production finishes.** Any
  run shorter than ~90 s reports `soldiers=0` and fails, and that is the
  check working, not a bug.
- Spawns are scattered at a minimum spacing (D-039) and the load test's
  server generates the map file's 20 starts, not one per bot — it has no
  lobby, so D-20260817-starting-positions-follow-the-seats does not apply
  to it. The four bots take seats 0–3, and how far apart those land is a
  property of the map and seed rather than of the bot count. That spread
  is why the patrol's boundaries are stated in the WATCHER's terms rather
  than as "am I home yet": on a tight pair, home is inside the
  neighbour's vision.
- **The bots still field no ARMY.** Nothing they build produces a soldier,
  so `raid_pool` is empty on every tick and the raid alternation is dead
  code until that changes. `test-load` therefore exercises the economy,
  buildings, fog and incidental combat — not military production, and not
  an engagement between two real armies. Tracked separately as **#123**.
