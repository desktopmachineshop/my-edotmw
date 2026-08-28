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
