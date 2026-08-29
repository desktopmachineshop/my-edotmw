### D-20260828 · Accepted — the controls are written down once, and what is written down is what the code does

**Decision (issue #282, onboarding batch; D-094 criterion 10's blocker):**
there is a **Controls screen**, reachable from **both** the main menu and
the in-game menu, built from one list in `controls_reference.gd`. Its
build and train rows are **derived** from `client.gd`'s own `BUILD_KEYS`
and `TRAIN_KEYS`.

**The gap.** A stranger who installed the alpha met a lobby, then a map,
with nothing anywhere telling them that WASD pans, that Q/E turn the
view, or that right-click orders. D-094's criterion 10 — a human playing
end to end through an installed build — cannot be discharged honestly
against a game whose controls are undocumented, which is why the gap
assessment filed this as a **blocker** rather than as polish.

Four calls:

**1. One list, two entry points.** The main menu for a player who has not
connected yet; the in-game menu for one mid-match who will not go back to
the main menu to look up which key builds a barracks. Two hand-written
lists of the same bindings is a pair that comes to disagree, and a test
asserts both buttons exist and that both are built from
`ControlsReference.groups()`.

**2. The build and train rows are DERIVED.** Nine buildings and five
units, edited whenever the roster moves, is exactly where a hand-written
list goes stale — and a stale controls screen is worse than none, because
a player trusts it. `_key_table` reads the constants off `client.gd`, and
tests assert every bound key appears.

**3. It documents BEHAVIOUR, not intent — and writing it found a bug.**
Enumerating every binding is how **#302** was found: `G` is in
`BUILD_KEYS` *and* has a hand-written gather branch below the build
table, so the build wins and **the gather shortcut is unreachable**. The
screen says `G` builds a garrison wall, because that is what pressing it
does. A screen that documented the intent would turn that bug into the
player's fault — they would press G, get a garrison wall, and conclude
they had misread the screen. A test pins that row, and says what to do
if #302 is fixed by moving the key rather than by silently passing.

**4. Train rows name an ARCHETYPE, never one civ's units.** Six civs
share this screen (D-047); "Train levy" is right for all of them and
"Train Hill Thralls" is right for a sixth. A test forbids the civ names.

**The picture found two defects the tests did not, and then the tests
were taught to find them.** `just menu-shot CONTROLS=1` renders it — and
the first frame showed the main menu bleeding legibly through a 0.94
backdrop ("eDotMW", "Join", "Host a match" all readable under the key
list), and the right-hand column running **off the bottom of a 720-high
window with the Close button off-screen entirely**. The backdrop is
opaque now, and the columns are split at the point that leaves the taller
one shortest.

That split took two attempts, both caught by looking: two-groups-each put
sixteen rows under a column that had already spent five, and a greedy
"fill the left until it holds half" was worse — it put *all* of them
left, because fourteen of thirty is still under half until the sixteen-row
group has been added. **`test_the_controls_screen_fits_the_smallest_window_it_is_meant_to`
is what makes looking optional next time**: it builds the real screen in
a real tree (theme fonts do not resolve off-tree, so an off-tree
measurement is a confident wrong answer — `test_lobby_layout.gd`'s own
lesson) and measures. It reported **1162 px against 720** on the broken
split and reports **644** now.

**Rejected alternatives:** *a rebindable-keys settings page* — far more
than the gap needs, and it would make the derived rows a lie. *Printing
the controls into `testers.md` only* — that file ships inside every
package (#183) and does list them, but a player who is already in a match
should not have to find a text file. *A first-run overlay* — it is read
once, by definition, and the player who needs it most is the one who
skipped it.

**Consequences:** `--controls=1` exists on the client, capture-only, so
the one instrument that has to photograph the screen can.
`just menu-shot` gains a `CONTROLS` argument, validated through
`recipe-arg.sh` like every other numeric one.

**The other half of #282 — the in-match first-objective hint — landed in
#284**, which is directly beneath this in the stack:
`OpeningBrief.first_objective` names the player's own crew and the
building to found and vanishes once one stands. Deliberately not
duplicated here; two sources of truth for "what should I do first" is the
pair this decision's first clause exists to prevent.

**Revisit trigger:** rebindable keys (the derived rows become a mapping
rather than a constant); or a fifth control group, at which point the
two-column split should be re-measured rather than assumed — the fit test
will say so.
