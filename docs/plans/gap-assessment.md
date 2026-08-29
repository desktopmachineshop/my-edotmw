# Gap assessment — a senior game dev's audit

**Written:** 2026-08-28. **Against:** `main` at `cc2f4c6`, plus the 29
open PRs in flight at the time of writing (named where they change an
answer).

**What this is.** An outside-in audit of the whole project against the
goal it has set itself: a 20-player, 1–2 hour, six-civ RTS shipping on
Steam. It looks for the gaps between what is *built* and what is
*required*, not for defects — the defect estate is already well served by
the playtest tickets and the bot-observation passes.

**What this is not.** It is not a criticism of the engineering. The
simulation core is in unusually good shape for a project at this stage,
the decision record is better than most shipped commercial games have,
and the testing discipline (perturb before trusting, quote a number with
its conditions) is genuinely rare. **The gaps below are almost all in the
half of a game that is not the simulation** — content, onboarding,
product, process — which is the normal failure mode of an
engineering-led project and the reason this audit was asked for.

**How to read it.** Five sections. Each gap carries evidence from the
repo or the decision record, a severity, and a **proposed ticket** —
title plus a three-line body — which the orchestrator files or discards.
Nothing here is filed.

**Severity scale**, used consistently:

| | meaning |
|---|---|
| **Blocker** | M8 (Steam-ready) cannot honestly be called done with this open |
| **High** | ships, and the first cohort of players will hit it and say so |
| **Medium** | costs the project time or credibility, not the release |
| **Low** | worth writing down before it is forgotten |

A standing caveat before any number below: **this project's own rule is
that a figure is quoted with its conditions** — squad count, cap, roster,
adapter. Every number here carries them, and where a number is a floor or
a single run I say so rather than rounding it into a fact.

---

## 0. The headline

Three things stand out from the whole survey.

**The simulation is ahead of the game.** The server meets its tick budget
(`test-load 4 120` on 2026-08-28: `VERDICT ok`, 0 desyncs over 476
checks, 0 dropped ticks, 173.86 µs/squad at 33 squads). Squad-level
combat, morale, formations, fog, pathing, walls and the RTW battle
programme are all landed and tested. What is missing is what a *player*
does with that for an hour.

**Nothing has been built for a stranger.** There is no tutorial, no
controls screen, no first-run flow, no build, no download. Every hour of
play so far has been by the one person who knows the codebase. That is
the largest single risk to M8, and it is invisible from inside the repo
because every instrument here is aimed at correctness.

**The process gap is the one that compounds.** There is no CI. **Eleven
separate "main is red" or "the recipes are broken" incidents have been
filed** (#152, #154, #160, #202, #203, #204, #208, #209, #211, #212,
#215, #223), every one found by a human running a recipe by hand, on a
tree where 29 PRs are open simultaneously. Everything else in this
document gets slower while that is true.

---

## 1. Content depth against D-056's 1–2 hour target

**D-056** sets the target at **1–2 hours** and records matches deciding
at **~200–230 s**. It also does the important half: it names the
structural cause rather than tuning the symptom — *"there is no
progression at all… don't try to reach an hour by tuning health."*

### 1.1 What actually exists on `main`

| | count | note |
|---|---|---|
| unit defs | 39 | 27 combat + per-civ gatherers and generals |
| buildings | 9 | barracks, storehouse, town centre, tower, gate, wall, wall tower, garrison wall, garrison gate |
| civs | 6 | the fantasy roster (`docs/status/fantasy-civs.md`) |
| formations | 8 | line, column, ring, wedge, sparse, tight, shield wall, testudo |
| **epochs** | **0** | `/epochs` does not exist; D-069's ladder is design-only |
| **techs / upgrades** | **0** | no research anywhere |
| **renewable resources** | **0** | every resource is a finite node (#159) |
| **upkeep** | **0** | `ai_player.gd:1069` — *"There is no upkeep in this game"* |
| **victory conditions** | **1** | elimination (D-033) |

Two of these are addressed by PRs in flight — **#225** (the tech tree,
issue #206) and **#246** (the farm, issue #159) — and neither is merged.
This section assesses `main`; where a PR would change the answer I say
so.

### 1.2 Gap C1 — the economy has a hard ceiling, so an hour is arithmetically impossible

**Severity: Blocker** (for the 1–2 hour target; not for shipping an
alpha).

Evidence: **#159**. Every resource comes from a finite node; `TREE_STOCK`
is 105 and one shipped gatherer crew works a tree out in ~60 s, pinned by
a test (D-087). The map's total economy is fixed at generation. D-068
then makes an army a *running cost* (upkeep), which makes a finite
economy strictly worse — you would be paying a per-tick bill out of a
bank that only ever shrinks.

This is the cleanest example in the project of a **target and a mechanism
pointing in opposite directions**, and it is worth stating plainly: no
amount of node density fixes it, because density changes when the ceiling
is hit and not whether. PR #246 (farms) is the right shape of answer and
is the single highest-value unmerged PR for the stated goal.

What #246 does **not** close, and should be tracked separately: the
**metals**. Gold and stone remain strictly finite with no trade, market,
or conversion, so a long match still ends with everybody unable to build
the things that cost them. D-068's own brief flagged this
(*"an hour-long match at 40 squads/player may exhaust the map, which is
either a designed pressure or a bug depending on the answer"*) and
`OPEN-QUESTIONS.md` records it as **the one part of Q15 that D-068–D-074
did not close**. It is still not closed.

> **Proposed ticket — "Metals have no renewable source, and D-068's
> exhaustion question is still open"**
> Farms (#159/#246) close food; gold and stone remain finite with no
> trade, market or conversion, so a long match still ends unable to
> build. `OPEN-QUESTIONS.md` records this as the one part of Q15 that
> D-068–D-074 left open, and D-068's upkeep makes a shrinking bank worse.
> Decide it as a design question — trade, deep deposits, or accepted
> scarcity — and attach a consumption rate to D-068's phase table so the
> answer is computed rather than argued.

### 1.3 Gap C2 — the epoch ladder is design-only, and the tech tree redefines it

**Severity: High.**

D-069 specifies five epochs; `D-20260823-fantasy-civs-on-a-four-epoch-ladder`
supersedes that with four (medieval → imperial → modern → futuristic).
**Neither exists in code or data** — there is no `/epochs` directory, and
`docs/status/m9-plan.md` says so explicitly. Issue **#206** then
*redefines the mechanism* — the age-up becomes completing a defining line
in the tech tree rather than a button with a cost — which is a better
design and means D-069's `EpochDef` gate as written is already
superseded before being built.

The risk here is not that it is unbuilt. It is that **three decision
entries now describe three different ladders** (D-069's five historical
rungs, D-20260823's four fantasy rungs, #206's tech-line transition) and
the newest of the three is an *issue*, not a decision. This project's own
rule is that a decision is a file; the ladder's current shape is not one.

> **Proposed ticket — "The epoch ladder has three descriptions and no
> decision entry for the current one"**
> D-069 (five rungs, EpochDef gate), D-20260823 (four fantasy rungs) and
> #206 (age-up IS completing a tech line) describe three different
> ladders; the newest is an issue rather than a decision file, so
> `decisions/` does not record what is being built.
> Write the superseding entry before #225 merges, so the tree that lands
> has a decision behind it rather than a ticket.

### 1.4 Gap C3 — elimination is the only way a match can end

**Severity: High.**

`MatchState` has one terminal condition: a player with no living squads
**and** no living buildings is eliminated (D-033), and the match ends
when one player or team is left. There is **no time limit in a real
match** — `--run-seconds` is a harness flag (`server.gd:168`), not a
player-facing rule — **no surrender**, and no score, wonder, territory or
objective victory. Grep finds "surrender" only in a chat-sanitising test.

Three consequences, in increasing order of seriousness:

- **A losing player must be hunted down.** With no resign, the last five
  minutes of every match are the winner walking across a 32,592-cell map
  finding the loser's last wall segment. At the 1–2 hour target that is
  not a rounding error.
- **A stalemate has no exit.** This is not hypothetical — it is the
  failure mode two of my own recent tickets describe (#128: an isolated
  spawn cannot be attacked, so the match cannot be decided; #217: a seat
  that never founds is eliminated and the harness reports a *decisive
  win*). Both were only visible because somebody read a log.
- **20 players makes it worse.** D-089 makes 20 a design target. A
  20-seat free-for-all with elimination-only victory and no surrender
  means nineteen players wait for the twentieth. **This is the single
  biggest untested assumption in the product**, and it is untested
  because the 20-seat match is D-094 criterion 8 and has never been run.

> **Proposed ticket — "A match can only end by elimination: no surrender,
> no time limit, no alternative victory"**
> `MatchState` ends a match only when one player or team has no living
> squads AND no living buildings (D-033); `--run-seconds` is a harness
> flag, and grep finds no resign path anywhere.
> At D-056's 1–2 hours and D-089's 20 seats this means nineteen players
> wait while a winner hunts a last wall segment. Add surrender first (it
> is small and unblocks playtesting), then decide whether a second
> victory condition is wanted before M8's 20-seat match.

### 1.5 Gap C4 — map variety is one generator, and one of its four presets is unplayable

**Severity: Medium.**

The lobby offers 4 terrain presets (`continents`, `plains`, `highlands`,
`islands`) × 4 sizes × a seed × sea/mountain sliders. That is real
variety and it is generated honestly. But:

- **There are no authored maps and no map features.** No rivers, no
  chokepoints, no bridges, no ramps between plateaus except
  `D-20260826`'s carved ones, no starting-position asymmetry with a
  fairness guarantee. Every match is the same *kind* of ground.
- **`islands` is effectively unplayable and this is now measured.**
  `D-20260827-every-start-shares-one-landmass` swept 96 worlds: on
  `islands` the mainland is **8–67% of walkable ground**, and starts are
  now confined to it, so a 20-seat `islands` match short-seats (8–17 of
  20). The underlying reason is that **there is no naval movement, no
  transport, and no way to cross water at all** — so an archipelago map
  is a map most of which no army can reach. That entry's own revisit
  trigger names exactly this.

So of four presets, one is a decoration. That is worth knowing before it
appears in a Steam screenshot.

> **Proposed ticket — "The `islands` preset has no game in it: no naval
> movement, so most of the map is unreachable"**
> `D-20260827` measured `islands`' mainland at 8–67% of walkable ground;
> starts are confined to it, so 20 seats short-seat to 8–17 and the rest
> of the map is scenery no army can reach.
> Decide: cut it from the lobby, gate it behind a seat count it can
> actually hold, or accept the cost of transports. Shipping it as-is
> means a player picks it once and concludes the game is broken.

### 1.6 Gap C5 — no progression *pacing* target exists to design against

**Severity: Medium.**

D-068's six-phase table is the derivation base for every timing in M9,
and it is **prose in a decision entry with no consumption rate attached**
(`OPEN-QUESTIONS.md` says so). So when #225's tech tree lands, there is
nothing to check its costs *against* — the same trap D-056 named for
health tuning, one layer up. The AI's pacing has the same hole: D-054's
own status page records *"a pacing target derived from D-056's 1–2 hour
match length rather than emerging from a cooldown"* as still not built.

> **Proposed ticket — "D-068's phase table has no numbers, so tech and
> upkeep costs cannot be derived from it"**
> D-068 is the stated derivation base for M9's timings, and
> `OPEN-QUESTIONS.md` records that the consumption rate it needs was
> never attached. #225's tech costs and D-068's upkeep therefore have
> nothing to be checked against.
> Attach resource-per-minute and squad-count figures to each of the six
> phases so a tech tree can be priced rather than tuned.

---

## 2. Onboarding — a new player's first ten minutes

**This is the weakest area in the project, and by a wide margin.**

### 2.1 What a stranger actually meets

I traced the path on `main`. In order:

1. **There is no build.** No `export_presets.cfg`, no `just export`
   (PR #205 adds both). The only way to play is to clone the repo, run
   `bootstrap.ps1`, fetch a portable Godot, and run a `just` recipe.
2. **The client launches straight into a connection attempt.** There is
   no main menu (PR #239 adds one), so a client with no server is a
   window that does nothing (#162, PR #232).
3. **The lobby's entire instructional text is two sentences**
   (`client.gd:9449`): *"Click a civilisation to change it. Only you can
   seat AI players and start the match."* and *"Choose your
   civilisation. The host starts the match."* Nothing says what a
   civilisation *does* — and since
   `D-20260823-a-civs-knobs-are-read-by-the-simulation` they now differ
   mechanically, so the one choice a new player is asked to make is the
   one the game explains least.
4. **The match starts and there is no tutorial.** Grep for
   `tutorial`/`How to play` across the project returns only GUT's own
   addon files.
5. **The controls are undiscoverable.** The client binds ~14 keys —
   WASD pan, wheel zoom, Q/E and Ctrl+wheel rotate, Ctrl+1–9 groups,
   right-click order, **right-drag to form a battle line**, **Alt+right-click
   to face**, ESC menu — and the ESC menu offers Resume / Players /
   Settings / Save game (disabled) / Leave match / Exit game. **There is
   no Controls screen and no key list anywhere in the game.**
   `docs/COMMANDS.md` is a developer recipe reference, not player help.
6. **The opening is a crew and a general, and nothing says what to do
   with them.** Under `D-20260823-the-opening-is-a-crew-and-a-general` a
   player starts with one gatherer crew and one general and **no base**.
   The single most important action in the first minute — found a town
   hall with the crew, which consumes it — is discoverable only by
   selecting the right squad and finding the right button. A new player
   who picks the general instead gets a refusal.

### 2.2 Gap O1 — no tutorial, no controls screen, no first-run flow

**Severity: Blocker** for M8. D-094 criterion 10 is *"a human plays
end-to-end through the Steam build"*, and the D-085-criterion-14 lesson
it cites is precisely that this criterion is the one nothing automates.
A tester who cannot work out how to place a building will discharge that
criterion as "unplayable" and be right.

The cheapest thing that would move this a long way is **not** a scripted
tutorial. It is, in rough order of value per hour:

1. A **Controls** panel in the ESC menu — a static list, half a day.
2. A **first-objective prompt**: "Select your gatherers and build a Town
   Hall" until one exists. The server already knows whether a player has
   a town centre.
3. Civ descriptions in the lobby — `CivDef` already carries the knobs
   (`squad_cap_bonus`, `production_speed`, `gather_speed`); one
   `description` field and a panel makes the choice meaningful.
4. A skirmish-vs-AI entry point that does not require understanding the
   lobby.

> **Proposed ticket — "No player-facing help exists anywhere: no
> controls screen, no tutorial, no first objective"**
> The client binds ~14 keys including two non-obvious gestures
> (right-drag forms a battle line, Alt+right-click faces a squad) and
> lists none of them; the ESC menu has no Controls entry and grep finds
> no tutorial anywhere in the project.
> D-094 criterion 10 is a human playing end-to-end through the Steam
> build, and this is what that criterion will fail on. Start with a
> static Controls panel and a "build your Town Hall" first objective.

> **Proposed ticket — "The lobby asks a player to choose a civ and never
> says what one does"**
> The lobby's whole instructional text is two sentences about *how* to
> pick a civ; since `D-20260823-a-civs-knobs-are-read-by-the-simulation`
> the six civs differ in squad cap, production and gather rate as well as
> roster, and none of that is shown.
> Add a `description` (and the knob summary, derived not retyped) to
> `CivDef` and show it on selection — the data is already there and
> read by the simulation.

### 2.3 Gap O2 — the opening teaches nothing and punishes the obvious guess

**Severity: High.**

`docs/status/the-opening.md` records that *two callers* in this
repository picked `state.squads[0]` as their builder and were wrong half
the time once the opening became a crew *and* a general — the load-test
bot and the capture client, both written by people who know the codebase.
A new player makes exactly the same guess with the same odds, and the
feedback is a server refusal message.

> **Proposed ticket — "A new player's first action is a coin flip: the
> opening is two squads and only one may build"**
> Under `D-20260823-the-opening-is-a-crew-and-a-general` a player opens
> with a crew and a general; only the crew may found, and the general's
> build order is refused. Two callers *inside this repo* made that
> mistake before a test caught it.
> Pre-select the crew at match start, or grey the build action with the
> reason, so the first sixty seconds do not turn on a guess.

---

## 3. Performance debts

The server is in good shape; **the client is not**, and the honest
summary is that *nobody knows what this game runs like on a player's
machine.*

### 3.1 Gap P1 — every rendering number in the project is from one integrated GPU

**Severity: Blocker** for M8 (it is **D-094 criterion 9**, and Q15's
trigger has been armed and re-armed since 2026-08-02).

`OPEN-QUESTIONS.md` Q15 was deferred, met in M5, and then **re-armed**
with a sharpened trigger: run `bench-render` on a **discrete GPU** before
M7. M7 shipped. M8 is being planned. It has still not been run — D-085's
own status page carries it as the one surviving caveat, and PR #250's
attribution table is again headed *"Intel(R) Iris(R) Xe Graphics
(integrated; D-085's discrete-GPU trigger still armed)"*.

The specific unknown is well posed, which is why this is worth doing
rather than worrying about: the frame is **CPU-bound on derivation**
(PR #250: 82.5 ms of a 112.5 ms CPU frame), which *predicts* a discrete
GPU changes little. That prediction has never been checked, and if it is
wrong in either direction it changes M8's scope.

> **Proposed ticket — "Q15's discrete-GPU trigger has been armed since
> M5 and never fired"**
> Every client-render figure this project has — D-045, D-086, #229,
> PR #250 — is from Intel Iris Xe integrated. Q15 was re-armed in M5 with
> a "before M7" trigger; M7 shipped and M8 is being planned.
> It is D-094 criterion 9. Run `just bench-render` on a discrete GPU at
> the ship map and squad count, adapter name in the output, and record
> whether the CPU-bound prediction holds.

### 3.2 Gap P2 — the client misses its own target by 17x, and #229 is a class not an incident

**Severity: High.**

**#229**: on the shipped map, D-018's 1,000-squad target renders at
**5.4–5.9 fps** (168–185 ms mean, worst frame 591–751 ms) against
D-086's last recorded 53.93 ms / 18.5 fps on the same class of hardware.
PR #250 attributes it properly and finds the causes are **features, not
a regression**: the #97 soldier clamp is 30–32%, the terrain sampler
22–29%, and — importantly — **the 4x map is not the cause**; per drawn
man it costs the same as the old map.

Two things make this a *class* rather than one number:

- **Nothing was watching.** The map ladder moved on 2026-08-17 and
  client render cost was not re-measured until a playtest noticed.
  `docs/status/m10-plan.md`'s client section names only the start-up
  freeze.
- **The benchmark is a floor and now says so.** #240 (filed from PR #250)
  records that `bench_render.gd` claims to do what `client.gd` does and
  since the RTW programme does not — duels, corpses, easing, jostle,
  building and tree push-outs are all per drawn man and none are in the
  benchmark. **So the real client is slower than the number, by an
  unmeasured amount**, and #229's third candidate cannot be measured by
  the instrument #229 came from.

The server has the mirror of this and it is already recorded: the
1,000-squad sweep is **204.5 ms against D-020's 100 ms tick** after
#107's fix, open as **#105**, and `docs/status/civ-knobs.md` notes the
lobby's 24-seat ceiling worst-cases at **1,056 squads** — past the top
rung the sweep measures.

> **Proposed ticket — "`bench_render.gd` measures a client that no longer
> ships, so every client number is an unquantified floor"**
> #240, filed from PR #250: the benchmark omits duels, corpses, easing,
> jostle and the building/tree push-outs the RTW programme added, all of
> which are per drawn man in the real client.
> Bring it back onto `client.gd`'s own path (or delete the claim and
> measure the client directly), because #229's remaining candidate cannot
> be measured with it as it stands.

> **Proposed ticket — "Nothing re-measures client render cost when the
> map, roster or render path changes"**
> #229 was found by a playtest, months after the map ladder moved; the
> RTW programme added five per-man render costs with no frame number
> taken. There is no trigger and no recorded budget.
> Add a render-cost line to the release checklist (or the nightly, per
> the CI proposal) with the standing rule that a figure carries its
> adapter, map and squad count.

### 3.3 Gap P3 — the sampler is measured now, but the tick budget is still over at scale

**Severity: Medium.**

`CLAUDE.md` and `docs/status/world-look.md` have carried *"its cost on
real hardware is unmeasured"* about `TerrainChunk.height_at` since M5.
PR #250 measures it (22–29% of the frame, ~4.5 µs per drawn man) — so
**that specific debt is discharged the moment #250 merges**, and the docs
should stop saying it is unmeasured.

What is *not* discharged is the server side at full scale: **#105**'s
1,000-squad worst tick of 204.5 ms against a 100 ms budget. That is not a
regression and not this audit's finding — it is recorded in
`m10-plan.md` — but it is the thing that decides whether D-018's 20
players survives contact with M9's extra content, and the RTW programme
already said the successor number would be **measured at programme end
and has not been** (its exit criterion 8).

> **Proposed ticket — "D-018's 20-player target has no successor number,
> and its exit criterion is unfulfilled"**
> `D-20260818-battle-quality-outranks-player-count` traded player count
> for battle quality and said the replacement would be MEASURED at
> programme end (criterion 8). All twelve workstreams landed; the
> measurement was not taken, and #105 has the 1,000-squad tick at 204.5 ms
> against D-020's 100 ms.
> Take it before M9 adds load, on named hardware, and supersede D-018's
> number rather than letting 20 be re-quoted by default.

---

## 4. Product gaps toward M8 / Steam

D-094 lists ten exit criteria. Measured against `main`, **none is
complete**; measured against `main` plus the open PR stack, roughly half
are in flight. The gap is not that the work is unstarted — it is that
**the work is all in parallel and none of it has met a stranger.**

| D-094 criterion | on `main` | in flight |
|---|---|---|
| 1. `just export` produces a runnable build | ✗ (no `export_presets.cfg`) | PR #205 |
| 2. Upload to a Steam depot | ✗ | — |
| 3. Protocol version handshake | ✗ | PR #213 |
| 4. Host starts a match from inside the game | ✗ | PR #256, #239 |
| 5. Steam sockets transport | ✗ | — (#184) |
| 6. Reconnection (D-090), each leg observed to fail | ✗ | — |
| 7. Platform boundary grep-test (D-093) | ✗ | PR #242 |
| 8. A 20-seat match with ≥3 remote humans | ✗ | — |
| 9. Discrete-GPU number | ✗ | — (gap P1) |
| 10. A human plays end-to-end through the Steam build | ✗ | — (gap O1) |

### 4.1 Gap M1 — what a stranger hits first, in order

Walking it as a tester who has been sent a link:

1. **There is nothing to download.** PR #258 (alpha zip + runbook + the
   page a tester reads, issue #183) is the fix and is unmerged. Until it
   lands, "playtest" means "clone a repo and install a toolchain", which
   selects for developers and therefore for feedback that is not about
   the game.
2. **The build has no version anyone can quote.** Without #213's
   handshake a mismatched pair fails as a desync or a silent hang, and a
   tester's bug report cannot be tied to a build. This is the criterion
   D-094 itself flags as load-bearing early *because Steam's rolling
   updates make mixed versions routine*.
3. **There is no way to find a game.** No lobby browser, no invites, no
   server list. D-089 makes 20 players a design target and names Steam's
   lobby browser + invites as the mechanism; nothing exists.
4. **If the host quits, the match dies.** Accepted with eyes open in
   D-088, with dedicated servers as the eventual fix. Worth restating as
   a *product* fact and not just an architectural one: an alpha tester
   whose host rage-quits at minute 50 of a 1–2 hour match loses the
   match, and D-092 says there are **no saves**.
5. **There is no crash/telemetry path.** Nothing collects a log from a
   tester's machine. Every diagnosis in this project so far has depended
   on reading a server log the developer had; a remote tester has one and
   no way to send it.

Numbers 4 and 5 are the ones I would raise loudest, because they are the
two that make *remote alpha feedback* worth less than the effort of
gathering it.

> **Proposed ticket — "An alpha tester has no way to send back what
> happened"**
> Every diagnosis in this project has come from a server log on the
> developer's machine (D-043's filesystem walk, #217's founding spin,
> #229's frame times). A remote tester produces the same logs and has no
> path for them.
> Before the first external build: write the log somewhere findable, put
> the build version in it (#213), and tell the tester in the runbook
> (#258) which file to attach.

> **Proposed ticket — "Host-quit ends a 1–2 hour match with no save and
> no recovery"**
> D-088 accepts host-trust and host-quit knowingly, with dedicated
> servers as the later fix; D-092 rules out saves; D-056 targets 1–2 hour
> matches. Those three are individually reasonable and jointly mean an
> alpha tester can lose an hour to somebody else's alt-F4.
> Not asking to reverse any of them — asking for the product decision to
> be recorded, and for host migration or a session-length expectation to
> be set before external testing.

### 4.2 Gap M2 — 29 open PRs against a tree with no CI

**Severity: High**, and it belongs in this section as much as in the next
one, because it is what stands between the work being *done* and the work
being *shipped*.

At the time of writing there are **29 open PRs**, and they overlap
heavily: **12 of them touch `client.gd`** — counted, not estimated —
against a `main` that is red. Every one was individually verified by its author running
recipes by hand. Nothing verifies them *together* until they merge, and
the merge order is currently a human judgement.

That is the mechanism by which "main is red" happens eleven times, and it
will not improve by being more careful.

---

## 5. Process gaps

### 5.1 Gap PR1 — there is no CI, and the evidence that this costs real money is unusually direct

**Severity: High.**

There is no `.github` directory. Every check this project has — and it
has excellent ones — runs only when a human types a recipe.

The evidence is not speculative. **Eleven filed incidents** of `main`
being red or the recipes being broken: #152, #154, #160, #202, #203,
#204, #208, #209, #211, #212, #215, #223. The pattern is identical each
time — a change lands, the suite is red for days, and a *different*
worker discovers it while doing unrelated work and stops to file it. I
did exactly that twice in the last two days, and lost time baselining 22
failures file-by-file at the branch point to prove they were not mine.
**That baselining is pure waste and CI eliminates it entirely**: if
`main` is known-green, a red PR is the PR's fault.

### 5.2 The proposed pipeline

Designed against this project's actual constraints rather than a generic
template. Three of those constraints matter:

- **Runtime.** `EDOTMW_RUNTIME=native` needs no docker and is what I have
  used all week; docker is currently broken host-wide (#223). CI should
  run **native** and pin Godot from `.godot-version` (4.7.1), which both
  the container build and `just bootstrap` already read.
- **Cost.** Measured on this machine, native: `test-unit` **322–515 s**
  (95 scripts, 1,264 tests). `test-scenario siege 4 15` ~25 s warm.
  `test-load 4 120` ~4 min including container bring-up; `4 300` ~5 min.
  So a per-PR gate of unit tests plus the fast scenario loop is roughly
  **6–10 minutes**, which is the right budget for a PR.
- **The host gate.** `host-gate.sh` exists because agents share one
  laptop. A CI runner is not that machine — set `EDOTMW_NO_GATE=1` in CI
  and let `just doctor` report it, exactly as it is designed to.

**On pull request** (target: under 10 minutes, required to merge)

| step | recipe | why |
|---|---|---|
| 1 | `./bootstrap.ps1` + `just bootstrap` | pinned `just` and Godot; cache `tools/` |
| 2 | `just doctor` | preflight, and it prints the runtime and gate state into the log |
| 3 | `just test-unit` | the whole suite; **this is the step that closes eleven tickets' worth of incidents** |
| 4 | `just test-scenario siege 4 15` | the fast integration loop — and since `D-20260818-the-fast-loop-carries-the-gate` it makes the same log comparisons the full gate does |
| 5 | line-ending check: `git diff --exit-code` after step 3 | `D-20260818-every-file-has-a-line-ending-rule` — a Godot recipe leaving the tree dirty is a real, already-paid-for failure |

**On merge to `main`** (same as PR, plus)

| step | recipe | why |
|---|---|---|
| 6 | `just test-load 4 300` | the gate. D-031's trap is shortening it; 300 s is the floor that reaches contact |
| 7 | publish the verdict line as a build artifact | so `µs/squad` with its squad count is recorded per merge instead of pasted into PR bodies by hand |

**Nightly** (cost is irrelevant; catches what a PR budget cannot)

| step | recipe | why |
|---|---|---|
| 8 | `just profile` | the scaling sweep — the authority on #105's tick budget, which no PR-sized run reaches |
| 9 | `just ai-ladder 3 600` | a strength number, and it is currently the only thing that would notice a civ that cannot found (#247) |
| 10 | `just test-ai-teams` | the one exercise of an ALLIED AI (#119); it would have caught #210's gate omission had a bot built walls |
| 11 | `just test-client` + upload `artifacts/client-frame.png` | this project's own repeated lesson is that numbers stay green while the picture is wrong; a nightly image a human glances at is cheap |
| 12 | `just gen-terrain-shot`, `gen-forest-preview`, `gen-model-preview` | same argument — the preview recipes exist *because* the failures they catch are invisible to counters |

**Two things the pipeline must NOT do**, both from this project's own
record:

- **It must not gate on wall-clock timings.** `D-106`'s amendment records
  a "cost does not scale with map size" test going red on a loaded host
  with nothing wrong, two commits after the warning was written.
  Publish milliseconds, gate on *counts*.
- **It must not become the only instrument.** Every one of the last three
  milestones' worst defects — soldiers rendering inside terrain, forests
  drawn as ranks and files, tools rendering bright red, the minimap crop
  — was invisible to every counter and visible in a picture. Steps 11–12
  are there so the pictures keep being produced, not so a robot can
  assert about them.

> **Proposed ticket — "No CI: eleven `main is red` incidents, every one
> found by hand"**
> #152, #154, #160, #202, #203, #204, #208, #209, #211, #212, #215, #223
> are all the same incident — a change lands, the suite is red for days,
> an unrelated worker finds it. With 29 PRs open (12 of them touching
> `client.gd`) this will not improve by being more careful.
> Add a GitHub Actions workflow: on PR run `test-unit` + `test-scenario`
> native with `EDOTMW_NO_GATE=1` (~6–10 min); on merge add
> `test-load 4 300`; nightly run `profile`, `ai-ladder`, `test-ai-teams`
> and the picture recipes as artifacts.

### 5.3 Gap PR2 — a green run is not a run that happened, and CI will make that easier to forget

**Severity: Medium**, and it is a warning attached to my own proposal
above.

This project's foundational testing lesson (D-022's audit block) is that
`test-load` once reported clean while every bot had exited non-zero, and
that its desync scan passed vacuously for a whole milestone. Automation
multiplies that: a green badge is read by more people, less carefully,
than a recipe somebody typed.

Two concrete instances from this week, both mine, both caught only by
deliberate perturbation: a two-continent test fixture laid against the
map edges is *one* continent on a torus and passed vacuously; a
production test derived each hall from the squad's own owner and stayed
green when production was made to report a fixed building. Neither would
have been caught by running more tests more often.

> **Proposed ticket — "CI needs the perturbation rule written into it, or
> it will grow vacuous checks faster than a human can"**
> D-022's audit block, and two fixtures caught vacuous this week, say a
> green check is worth nothing until it has been observed to fail.
> Automation makes green cheaper to trust and no cheaper to earn.
> Add the rule to the PR template ("which check did you watch fail, and
> how?") rather than to the pipeline — it is a review question, not
> something a runner can assert.

### 5.4 Gap PR3 — the decision record is drifting from the code in a way it warns about

**Severity: Medium.**

160 decision files, and the project's own most-repeated lesson is that
**a decision entry asserting an invariant is not evidence the invariant
holds** (D-058/D-065, D-097's amendment, D-106). It has been paid for at
least five times.

It is happening now, in the direction of *status docs* rather than
decision entries: `docs/status/m6.md` paraphrased D-107 as *"It retries
against a different site now"* — the decision never claimed it and the
code did not do it, which is #217. I only found that because I was fixing
#217. The paraphrase was in a status doc that is imported into `CLAUDE.md`
and therefore into every session's context, so **the wrong fact was being
handed to every worker on the project.**

> **Proposed ticket — "Status docs are imported into every session and
> can assert things the code does not do"**
> `docs/status/m6.md` paraphrased D-107 as "it retries against a
> different site now"; D-107 never claimed it and the code did not do it
> (#217). Those files are `@`-imported by `CLAUDE.md`, so a wrong
> sentence is handed to every worker.
> Sweep the status docs for behavioural claims in the passive voice —
> the project's own tell — and either cite the code that implements each
> or demote it to "planned".

---

## 6. If I could only fix five things

In order, judged by risk-to-the-project per hour of work:

1. **CI on PR** (gap PR1). It is the cheapest item here and it retires
   eleven tickets' worth of a recurring incident, permanently.
2. **A Controls panel and a first objective** (gap O1). Half a week, and
   without it D-094 criterion 10 cannot be discharged honestly.
3. **Merge the farm** (#246, gap C1). The 1–2 hour target is
   arithmetically impossible until food renews, and everything in M9 is
   priced against a match length that cannot happen.
4. **Run `bench-render` on a discrete GPU** (gap P1). One afternoon and a
   borrowed machine, and it is a hard M8 exit criterion that has been
   armed since M5.
5. **Surrender** (gap C3). Small, and it makes every subsequent playtest
   cheaper — including the 20-seat match nobody has run.

Everything else in this document is real and none of it is as urgent as
those five.

---

## Appendix — proposed tickets, collected

For the orchestrator's convenience. Bodies are in the sections above.

| # | title | gap | severity |
|---|---|---|---|
| 1 | Metals have no renewable source, and D-068's exhaustion question is still open | C1 | Blocker (target) |
| 2 | The epoch ladder has three descriptions and no decision entry for the current one | C2 | High |
| 3 | A match can only end by elimination: no surrender, no time limit, no alternative victory | C3 | High |
| 4 | The `islands` preset has no game in it: no naval movement, so most of the map is unreachable | C4 | Medium |
| 5 | D-068's phase table has no numbers, so tech and upkeep costs cannot be derived from it | C5 | Medium |
| 6 | No player-facing help exists anywhere: no controls screen, no tutorial, no first objective | O1 | Blocker |
| 7 | The lobby asks a player to choose a civ and never says what one does | O1 | High |
| 8 | A new player's first action is a coin flip: the opening is two squads and only one may build | O2 | High |
| 9 | Q15's discrete-GPU trigger has been armed since M5 and never fired | P1 | Blocker |
| 10 | `bench_render.gd` measures a client that no longer ships, so every client number is an unquantified floor | P2 | High |
| 11 | Nothing re-measures client render cost when the map, roster or render path changes | P2 | High |
| 12 | D-018's 20-player target has no successor number, and its exit criterion is unfulfilled | P3 | Medium |
| 13 | An alpha tester has no way to send back what happened | M1 | High |
| 14 | Host-quit ends a 1–2 hour match with no save and no recovery | M1 | Medium |
| 15 | No CI: eleven `main is red` incidents, every one found by hand | PR1 | High |
| 16 | CI needs the perturbation rule written into it, or it will grow vacuous checks faster than a human can | PR2 | Medium |
| 17 | Status docs are imported into every session and can assert things the code does not do | PR3 | Medium |

**Deliberately not proposed**, so the omissions are visible rather than
forgotten: sound and music (no audio system exists anywhere, and it is a
known, ordinary piece of work rather than a gap in reasoning); UI
localisation; controller support; replays as a *player* feature (D-016
built the format, nothing plays one back for a human); and per-civ
buildings or walls, which `docs/status/fantasy-civs.md` already records
as deliberately not done.
