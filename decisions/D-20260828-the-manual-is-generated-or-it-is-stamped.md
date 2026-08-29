### D-20260828 · Accepted — the manual is generated, or it is stamped, and there is no third kind of page

**Decision (issue #305, owner directive):** there is an in-game
**instructions manual**, reachable from **menu → Help** in both menus and
from **F1** in a match. Every page in it is one of exactly two things:

- **GENERATED** — rosters, stats, counters, costs, buildings, formations,
  and **each civ's advantages and disadvantages** — computed from the
  shipped `.tres` at the moment the player opens the page;
- **STAMPED** — prose that cannot be derived (what fog is, how morale
  works, what wins a match), each page naming the files it describes and
  carrying a **sha256 over them**, checked by `tests/test_manual.gd`.

There is no third kind, and a page that tried to be one would be a page
that could quietly stop being true.

---

## Why the split is the whole design

The owner's requirement came with its own rule attached — *any future
gameplay change keeps the manual up to date* — and a hand-maintained
manual cannot satisfy it. This project has watched prose stop being true
four times: `BuildingSim.damage()` uncalled for two milestones under a
correct doc comment (D-055); D-058's decision entry asserting a field was
on the wire when it was not (D-065); `_explored` documented as fog and
read by nothing but the minimap (D-106); three `CivDef` knobs shipped
non-default and read by nothing (#158). Every one had prose describing
what it did not do. A player-facing manual is the same defect with a
worse victim, because a player has no way to check.

So the generated half is not "generated for convenience" — it is
generated because **derivation is the only form of documentation that
cannot rot**. `Manual.troop_sections()` reads `UnitRoster.load_all()`
when the page opens; change a unit's damage and the manual has already
changed. That is `TerrainGen.biome_color()`'s rule (the minimap and the
3D view cannot drift because there is one definition) applied to text.

**The staleness guard therefore points at the half that can actually
rot.** #305 asked for a source-hash manifest on the `generated/` pattern,
and this is that mechanism aimed one layer over: there is no
`generated/manual/` to be stale, because nothing is stored. What IS
stored is seven prose pages, and those are stamped.

---

## Five calls worth reviewing

**1. The stamp is PER PAGE, not one manifest.** `generated/manifest.json`
holds one hash over all of `art/`, and that is right there: a bake is one
atomic operation and every output comes from one run.

A manual page is not. Pages are stamped against different sources on
purpose — the fog page is not invalidated by a unit stat change, and the
roster page is not invalidated by a fog decision. **A single hash would
red EVERY page on any gameplay PR**, and a guard that fires on things it
has nothing to say about is a guard people learn to silence rather than
obey (#204 records this repo already having one of those). A per-page
stamp names the page to re-read.

The other half is mechanical: several agents develop this repo in
parallel (D-095), and a central manifest is a file every one of their
branches edits. `decisions/README.md` exists because a shared monolith
made every parallel merge conflict; one file per page is that lesson
applied.

**2. Prose lives in `.tres`, not `.md`.** `export_presets.cfg` excludes
`*.md` from every shipping build, so a Markdown manual would be present
in the checkout and **absent from the game** — the works-here,
missing-on-a-player's-machine failure the export work already paid for
once (#178's `all_resources` note). A `.tres` ships by construction, is
plain text, and is directly editable by Claude Code without the Godot
GUI, which is D-001's premise.

**3. A civ's advantages are MEASURED, and no `.gd` names a civ.**
`civ_standing.gd` computes every claim as a comparison against the other
shipped civs: *"Trains 15% faster than standard"* is arithmetic on
`CivDef.production_speed` against the schema default; *"The only civ that
fields bombard and ram"* is a count over `/units`; *"Quality"* and
*"Quantity"* are D-072's V and V/RP against the roster median; *"Its
troops never rout"* is `rout_threshold` and `morale_loss_per_casualty`
over every fighting unit.

Six sentences keyed by civ id would have been quicker and are wrong
twice: they would be a lie within two milestones, and **D-046 criterion
3's test forbids any `.gd` naming a civ** — so a seventh civ would have
been a code change, which is exactly what D-047 exists to prevent. The
existing test is what keeps this honest; it needed no extension.

A claim has to clear a **margin** (8%) rather than merely differ. Two
civs whose median troop speed differs by 1% are the same civ for this
purpose, and a page that said otherwise would train its reader to skip
it.

**4. Prose that quotes a number quotes the REAL one.** A page may write
`{Combat.CHAIN_ROUT_MORALE_LOSS}` and gets whatever `combat.gd` says
today — a lookup into a script's constant map, the same technique
`controls_reference.gd` uses to derive its build rows from `client.gd`'s
own `BUILD_KEYS`. No expression language, three registered owners, and an
unresolved token is left **visible** so a broken page is obvious to
anyone who opens it as well as to the test.

The stamp would CATCH that drift; this makes the common case unable to
drift at all, which is strictly better — a guard tells you to go and fix
something, and this is already fixed. Deliberately **not** extended to
`.tres` values: those have generated pages, and a second way to quote a
unit's damage is a second thing to keep in step.

**5. Adding a page is cheap, which #305 asked for explicitly.** A prose
page is a `.tres` dropped in `/manual` — discovered, sorted, validated
and stamped with no code touched. A generated page is one entry in
`Manual._generated_pages()` and one function. The two interleave by
`order` rather than being two lists, because the reading order a player
wants alternates between "what is this" and "what are the numbers".
Naval (#301) and the tech tree (#206) each land as one file or one
function.

---

## Rejected

- **A manual built to committed files by a recipe**, mirroring
  `generated/`. It is the shape #305 named, and it is strictly worse than
  runtime derivation for the derived half: it adds a build step, a
  committed artefact, and a window in which the artefact is stale.
  Runtime derivation is the same idea taken to its limit.
- **An external `manual.md` shipped beside the binary.** #305 says
  in-game readable, and it is right: `docs/alpha/testers.md` already
  travels inside every package (#183) and a player mid-match will not
  alt-tab to a text file.
- **Asserting the manual's CONTENT in tests** — "Hearth Levy has 85
  health". That is a second copy of the roster, which is the defect the
  generated half exists to remove, moved into the test suite. The tests
  assert the page and the data AGREE, and drive the derivation with
  synthetic defs to prove the claims follow the numbers.
- **A rich markup language.** The renderer has two cases — text and table
  — and the markup is `## ` for a heading, `- ` for a list item and a
  blank line for a break. A manual that needed a parser would be a manual
  whose fit nobody could check, and the fit is measured
  (`test_the_manual_fits_the_smallest_window_it_is_meant_to`).

---

## What writing it found, which is the third time on this stack

**#309: `shield_wall` and `testudo` are unreachable.** Both ship as
`/formations/*.tres` with full directional stats, both are implemented
and tested, and **no player can order either** — they are `offered =
false` and no shipped unit grants them. `D-20260819-a-formation-is-a-
fighting-style` shipped them WITH grants on `legion_heavy` and
`northmen_spearmen`; `af9c3f4` (#191, the six fantasy civs) replaced all
43 unit files and the grants went out with the civs that owned them.

The formations page says *"Not granted to any troops"* in the "Who may
use it" column, because the page reports what the player can DO rather
than what exists. Filed, not fixed: which civ should have them is a
design call. **A manual that quietly omitted them would have hidden the
one fact that makes it useful.**

That follows #302 (found by enumerating the controls for #282) and #214
(found by putting `CivDef.summary` on screen for #283). Three defects in
three tickets, each found by writing something down — which is the
argument for this ticket that has nothing to do with players.

**And the #282 fit guard fired on the very next change.** Adding a fifth
control group for the manual's key took the controls screen to **731 px
against a 720-high window**; rebuilding the split put it at **705**.

**Amended 2026-08-28.** That number came with a prediction — 705 is the
OPTIMUM, two contiguous columns over 31 rows cannot balance better than
15/16, so the next row reds it — and **the prediction is measured
false**. #363's key re-allocation put `farm` on `O` and freed the gather
key, adding two rows, and the screen went **705 -> 684**: adding a row
can MOVE the split point, and the better balance on the far side of it
more than pays for the row. The bound was true of 31 rows and said
nothing about 33. The narrower true statement is that it fits with room,
the TEST measures that rather than anyone predicting it, and the fix if
it ever reds is to let a group break across columns rather than raise the
budget. Corrected in `client.gd` at the split, so the code does not keep
asserting the wrong thing.

---

## Consequences

- `just build-manual` re-stamps; `just build-manual verify` reports and
  changes nothing. `medium` host class, the same as the gen-* previews.
- `just menu-shot SECONDS RESOLUTION CONTROLS MANUAL=<page>` photographs
  one page. The page id is NOT validated against a list in the justfile —
  a second copy of the registry is the pair that comes to disagree — so
  the client refuses an unknown page and the recipe reads the marker it
  prints. `--menu` as a bare flag silently photographed the wrong screen
  once (#180); this is that lesson applied to an argument that can name a
  page which does not exist.
- **F1** opens and closes it, from `client.gd`'s `MANUAL_KEY` — one
  definition, read by the handler, by `controls_reference.gd` and by the
  opening objective. A function key rather than a letter because every
  letter is in `BUILD_KEYS`/`TRAIN_KEYS` or one commit from being taken
  by one, and **H, the obvious key for Help, has built a storehouse since
  M3**.
- The **opening objective points at it** (#284's banner gains
  `(F1: manual)`), which closes the onboarding loop #282 opened: the one
  moment this game knows a player is new is while they still have no
  town, and it is already speaking to them. Appended in `client.gd`
  rather than in `OpeningBrief`, which is about the opening and has no
  business naming a keybind.
- D-072's V and RP are now **read by shipping code** rather than only by
  a decision entry. It stays Provisional and its own caveat travels with
  it onto the page: V ignores reach, speed, sight, bonuses and morale, so
  it undervalues archers and scouts, and the page says so.

## Revisit trigger

A page that is neither derivable nor stampable — content that depends on
something outside the repo. Or a second *reader* of `CivStanding` (the
lobby is the obvious one, #283's natural sequel), at which point the
margin and the claim wording become UI decisions rather than this file's.
