**Onboarding — what a stranger is told, and when.** The gap assessment
(#265, `docs/plans/gap-assessment.md` §2.2–2.3) found that a stranger
installing the alpha meets a lobby, then a map, with no explanation of
anything. D-094 criterion 10 — a human playing end to end through an
installed build — cannot be discharged honestly without it. Three
tickets; this file collects what landed and the rules that came out.

---

## A civ says what it is before you pick it (#283)

`D-20260828-a-civ-says-what-it-is-before-you-pick-it`, 2026-08-28. Six
civs on six distinct mechanical axes — quality, quantity, ranged
attrition, mobility, economy, fortification — and the lobby showed
**names only**, so a stranger choosing one was choosing a word. The
lobby now shows each civ's one-line identity and its **signature unit**,
both derived from the `.tres`.

Five things to know:

- **`CivDef.summary` was declared-and-unread**, and its own doc comment
  had promised "a one-line pitch for the lobby" since the field existed.
  That is this project's most-repeated defect (D-055, D-106, #158) — and
  it came with the usual second consequence: because no eye was ever on
  the strings, **all six carried a cp1252 em dash (`0x97`)**, illegal as
  a UTF-8 leading byte, so every load printed a parse error and the text
  arrived with **U+FFFD** (#214). Twelve errors on `CivRoster.load_all()`
  alone. The files are rewritten as UTF-8 here; **0 parse errors now**.
- **`signature_unit` is an ARCHETYPE, never a def id** (D-047). A def id
  would be a second way of saying which unit a civ fields, free to
  disagree with the first — and a civ naming an archetype it does not
  field now shows NOTHING rather than advertising somebody else's
  troops.
- **The six values are the design plan's own**, from
  `docs/plans/fantasy-civs.md`'s Signature row, and every one maps onto a
  real archetype in the shipped roster. A test asserts each resolves for
  its own civ, so a renamed archetype goes red rather than leaving the
  lobby quietly blank.
- **Own seat gets a line, every other seat gets a tooltip.** A line under
  all twenty-four seats would cost the seat list the height
  `LobbyLayout` gives it. Measured after: content **784 + 64 margin
  against `DESIGN_HEIGHT` 1000**, so `test_lobby_layout`'s guard — which
  exists for exactly this kind of addition — is satisfied with room.
- **`just lobby-shot` now picks a real civ for its own seat.** Random is
  the one state where the identity line has least to say, so a screenshot
  left on it photographed the least informative version of the screen —
  the same "aim the instrument at the thing" rule `gen-terrain-shot` and
  `gen-forest-preview` exist under. The picture is what confirmed both
  the identity line and the em dash rendering correctly.

---

## The opening coin-flip (#284)

`D-20260828-the-opening-says-which-squad-founds`, 2026-08-28. Since
`D-20260823-the-opening-is-a-crew-and-a-general` a player opens with a
**gatherer crew and a general**; only the crew can found, and the general
can build nothing. Nothing on screen said which was which — and guessing
wrong does not fail loudly. Ordering the general to build is simply
refused server-side, so a new player clicks, nothing happens, and their
economy has not started while the other player's has.

Now: a **role line** on the selection panel, and a **standing objective**
in the HUD's banner slot that names the player's own crew and the
building, and disappears once one stands.

Five things to know:

- **`opening_brief.gd` names no archetype and no building.** "Can this
  squad found" is `BuildingSim.can_build` against the shipped
  `BuildingDef.built_by` — **the same call the order gate makes**, so the
  panel cannot promise something the server will refuse. The founding
  building is found by its RULE (`consumes_builder`), not its id. A test
  scans the file for both, comments stripped.
- **Only the two openers get a line.** An archer does not need to be told
  it is an archer, and a panel that editorialised about everything would
  be noise a player learns to skip — taking the two lines that matter
  with it.
- **The objective is derived from what a player OWNS**, not from a match
  clock. That is what makes it survive the three cases a timed tutorial
  gets wrong: founding late, losing the crew, and resettling after being
  razed (which D-20260823 made possible).
- **One banner, not two.** It shares the notice slot: a server refusal
  wins while it is up, and a second permanent strip would cost
  battlefield height for a line that is empty after the first minute.
  It is dimmer than a refusal, because a standing instruction at full
  warning strength reads as an error the player cannot clear.
- **`test-client` could not photograph it, so it was given a way.** The
  capture founds within a second or two of being welcomed, and the hint's
  whole job is to vanish once a town centre exists — so
  `just test-client SECONDS BOTS HOLD=1` makes it deliberately not act.
  That is the **fourth** time this instrument's framing could not show
  something, after cliffs (a spawn is walkable by construction), forest
  interiors (a spawn is open ground) and the fog edge. The frame reads
  *"Select your Hill Thralls and build a Town Centre. Your general
  cannot."*

---

## The controls are written down (#282)

`D-20260828-the-controls-are-written-down-once`, 2026-08-28. **D-094
criterion 10's blocker.** A stranger who installed the alpha met a lobby,
then a map, with nothing anywhere telling them that WASD pans, that Q/E
turn the view, or that right-click orders.

There is a **Controls screen** now, reachable from **both** menus and
built from one list — `controls_reference.gd`.

```
just menu-shot 4 1280x720 1     # -> artifacts/controls.png
```

Five things to know:

- **One list, two entry points.** The main menu for a player who has not
  connected; the in-game menu for one mid-match who will not go back to
  look up a build key. Two hand-written lists of the same bindings is a
  pair that comes to disagree.
- **The build and train rows are DERIVED** from `client.gd`'s own
  `BUILD_KEYS` and `TRAIN_KEYS`. Nine buildings and five units, edited
  whenever the roster moves, is exactly where a hand-written list goes
  stale — and a stale controls screen is worse than none, because a
  player trusts it.
- **It documents BEHAVIOUR, and writing it found a bug (#302).**
  Enumerating every binding is how it came out: `G` is in `BUILD_KEYS`
  *and* has a hand-written gather branch below the table, so the build
  wins and **the gather shortcut is unreachable**. The screen says `G`
  builds a garrison wall. A screen documenting the intent would turn that
  bug into the player's fault.
- **Train rows name an ARCHETYPE**, never one civ's units — six civs
  share the screen (D-047), and a test forbids the civ names.
- **The picture found two defects, then the tests were taught to find
  them.** The first frame showed the main menu bleeding legibly through a
  0.94 backdrop, and the right column running off a 720-high window with
  the **Close button off-screen**. The split took two attempts, both
  caught by looking. The fit test builds the real screen in a real tree
  (theme fonts do not resolve off-tree — `test_lobby_layout.gd`'s lesson)
  and reported **1162 px against 720** on the broken split, **644** now.

**The in-match first-objective hint — #282's other half — landed in
#284**, immediately beneath this in the stack. Deliberately not
duplicated: two sources of truth for "what should I do first" is the pair
the one-list rule exists to prevent.

---

## The manual is generated, or it is stamped (#305)

`D-20260828-the-manual-is-generated-or-it-is-stamped`, 2026-08-28. The
owner's directive: an in-game instructions manual at **menu → Help**,
with the full civ rosters and each civ's specific advantages and
disadvantages — and the rule that **any future gameplay change keeps it
up to date**.

```
just build-manual                       # re-stamp the prose pages
just build-manual verify                # report, change nothing
just menu-shot 5 1280x720 0 troops      # -> artifacts/manual-troops.png
```

Twelve pages. **F1** opens it in a match; both menus have a Help button
beside Controls.

Seven things to know:

- **Every page is derived or stamped, and there is no third kind.**
  Rosters, stats, counters, costs, buildings, formations and each civ's
  advantages are computed from the shipped `.tres` **when the page is
  opened**, so there is no copy for the data to disagree with and nothing
  to rebuild. Prose — what fog is, how morale works, what wins a match —
  is `/manual/*.tres`, each page naming the files it describes and
  carrying a sha256 over them. A gameplay PR that moves a rule and
  forgets the page goes RED in `just test-unit`.
- **The stamp is PER PAGE.** `generated/manifest.json` holds one hash
  over all of `art/`, and that is right for a bake — one atomic
  operation, one run. A manual is not: the fog page is not invalidated by
  a unit stat change. One hash would red every page on any gameplay PR,
  and **a guard that fires on things it has nothing to say about is a
  guard people learn to silence** (#204). A per-page stamp names the page
  to re-read. It is also the D-095 lesson — a central manifest is a file
  every parallel branch edits.
- **A civ's advantages are MEASURED.** `civ_standing.gd` computes every
  claim as a comparison: "Trains 15% faster than standard" from
  `production_speed` against the schema default; "The only civ that
  fields bombard and ram" from a count over `/units`; quality/quantity
  from D-072's V and V/RP against the roster median; "Its troops never
  rout" from the morale fields. **No `.gd` names a civ** and the existing
  D-046 criterion 3 test is what keeps that honest — six sentences keyed
  by id would have made a seventh civ a code change. A claim clears an 8%
  **margin** rather than merely differing, or the page trains its reader
  to skip it.
- **Prose that quotes a number quotes the real one.** A page writes
  `{Combat.CHAIN_ROUT_MORALE_LOSS}` and gets whatever `combat.gd` says —
  the same constant-map lookup `controls_reference.gd` uses for its build
  rows. The stamp would catch that drift; this makes the common case
  unable to drift.
- **Prose is `.tres`, not `.md`, and that was measured.**
  `export_presets.cfg` excludes `*.md` from every shipping build, so a
  Markdown manual would be in the checkout and **absent from the game**.
- **Adding a page is a file.** A prose page is a `.tres` dropped in
  `/manual`; a generated page is one registry entry and one function.
  Naval (#301) and the tech tree (#206) each land as one of those.
- **Writing it found #309, which is the third defect this batch found by
  writing something down.** `shield_wall` and `testudo` ship with full
  directional stats, are implemented and tested, and **no player can
  order either**: both are `offered = false` and no shipped unit grants
  them. The grants lived on `legion_heavy` and `northmen_spearmen`, and
  `af9c3f4` (#191) replaced all 43 unit files. The formations page says
  *"Not granted to any troops"*, because it reports what a player can DO
  rather than what exists — omitting the rows would have hidden the one
  fact that makes it useful. Filed, not fixed: which civ should have them
  is a design call. After #302 (found enumerating the controls) and #214
  (found putting `CivDef.summary` on screen).

**And #282's fit guard fired on the very next change.** A fifth control
group for the manual's key took the controls screen to **731 px against a
720-high window**; rebuilding the split put it at **705**.

**The prediction that came with that number is measured false, and it is
worth saying so.** It read: 705 is the OPTIMUM, two contiguous columns
over 31 rows cannot balance better than 15/16, so the next row reds it.
#363 then put `farm` on `O` and freed the gather key — two more rows —
and the screen went **705 -> 684**. Adding a row can MOVE the split
point, and the better balance on the far side of it more than pays for
the row. The 15/16 bound was true of 31 rows and said nothing about 33.

The narrower, true statement: it fits with room, **the test measures that
rather than anyone predicting it**, and if it ever does red the fix is to
let a group break across columns rather than raise the budget. Corrected
in `client.gd` at the split as well, so the code does not keep asserting
the wrong thing.
