### D-20260828 · Accepted — the opening says which squad founds, and it says it from the rule the server enforces

**Decision (issue #284, onboarding batch):** a selected squad's **role in
the opening** appears on the selection panel, and a **standing objective**
in the HUD's banner slot names the player's own crew and the building to
found — both derived from `BuildingDef.built_by` through
`opening_brief.gd`, which names no archetype and no building.

**The gap, and why it is worse than it sounds.** Since
`D-20260823-the-opening-is-a-crew-and-a-general` a player opens with a
gatherer crew **and** a general. Only the crew can found a town centre;
the general can build nothing at all, expressed by being listed in no
`built_by`. Nothing on screen said which was which — so the opening is a
coin flip, and **guessing wrong does not fail loudly**. The order is
refused server-side, so a new player clicks, nothing happens, and their
economy has not started while the other player's has.

Five calls:

**1. The hint asks the rule the ORDER GATE asks.**
`OpeningBrief.can_found` is `BuildingSim.can_build(town, archetype)` —
the same call `server.gd` makes when it decides whether to accept the
build. That equivalence is the whole safety argument: a hint derived from
a *second* rule is a hint that eventually lies, and this project has that
defect on file more than once (D-058/D-065, where a decision entry said a
field was on the wire and it was not).

**2. It names nothing.** No archetype, no building id. The founding
building is found by its RULE — the one with `consumes_builder`, which
`tests/test_opening.gd` separately asserts is exactly one — and the
crew by whether `built_by` admits it. So a civ that fields a different
founder, or a roster where the general gains a building, changes what the
player is told with no edit. That is D-046 criterion 3 applied to prose,
and a test scans the file for both (with comments stripped, the
precedent `test_steam_boundary.gd` set — the rule is about code, and
prose explaining why it does not name a thing is not a violation).

**3. Only the two openers get a role line.** An archer does not need to
be told it is an archer. A panel that editorialised about every unit
would be noise a player learns to skip — and it would take the two lines
that matter with it.

**4. The objective is derived from what a player OWNS, not from a
clock.** That is what makes it survive the three cases a timed tutorial
gets wrong: a player who founded late, one who lost their crew, and one
who was razed and is resettling — which D-20260823 explicitly made
possible. It disappears once a founding building stands (including one
still under construction: the player has acted, and nagging them while it
builds is wrong), because a standing hint that never goes away is a hint
a player stops reading — and then does not read the next one either.

**5. One banner, not two.** It shares the notice slot: a server refusal
wins while it is up, and a second permanent strip would cost battlefield
height for a line that is empty after the first minute of a match. It is
drawn dimmer, because a standing instruction at full warning strength
reads as an error the player cannot clear. `modulate` multiplies the
label's own colour rather than replacing it, so this is a muted version
of the same hue — checked in the rendered frame rather than assumed.

**`test-client` could not photograph it, so it was given a way.** The
capture founds within a second or two of being welcomed, and this hint's
whole job is to vanish once a town centre exists — so the first two
attempts photographed an empty banner and a finished town centre.
`just test-client SECONDS BOTS HOLD=1` makes the capture deliberately
**not act**. That is the **fourth** time this instrument's framing has
been unable to show something, after cliffs (D-097 — a spawn is walkable
by construction), forest interiors (D-108 — a spawn is open ground) and
the fog edge (#81). The lesson is the same each time: **when a rendered
check has to see something specific, frame it on purpose.** The frame
reads *"Select your Hill Thralls and build a Town Centre. Your general
cannot."*, with `casualties_applied=0` confirming the crew was never
spent.

**Rejected alternatives:** *a tutorial or a scripted first match* — far
more than the gap needs, and it would have to be maintained against every
roster change. *Naming the gatherer archetype in the UI* — see (2); it
would be correct today and wrong the first time a civ fielded a different
founder. *A separate permanent hint strip* — see (5). *Explaining the
general in the build menu instead* — the build menu is empty for a
general, and an explanation only visible after a player has already
clicked the wrong thing is an explanation arriving too late.

**Consequences:** `--hold-opening=1` exists on the client and is capture-
only; `run-client` never sets it. `OpeningBrief` is also what #282's
controls work reads, rather than computing a second answer to "what
should I do first".

**Revisit trigger:** a roster where more than one building spends its
builder (the founding building stops being unambiguous, and
`founding_building()` becomes a choice rather than a lookup); or a
second standing hint wanting the banner slot, at which point sharing it
with refusals stops being free and the slot needs a queue.
