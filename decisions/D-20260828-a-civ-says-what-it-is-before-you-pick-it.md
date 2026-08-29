### D-20260828 · Accepted — a civ says what it is before you pick it, and the string it says it with was unreadable

**Decision (issue #283, onboarding batch):** the lobby shows each
civilisation's **one-line identity and its signature unit**, both derived
from the `.tres`. `CivDef` gains `signature_unit` (an ARCHETYPE);
`civ_identity.gd` is the pure module that decides what is shown; the
lobby draws it under the seat list for the player's own seat and on every
seat's picker as a tooltip.

**The gap, in one sentence:** six civs sit on six distinct mechanical
axes — quality, quantity, ranged attrition, mobility, economy,
fortification — and the lobby showed **names only**, so a stranger
choosing one was choosing a word.

**And the field meant to fix it was declared-and-unread.**
`CivDef.summary`'s own doc comment has said *"a one-line pitch for the
lobby, so the player knows what they are picking"* since the field
existed, and nothing read it. That is this project's most-repeated defect
(D-055, D-106, the civ knobs at #158) — and it had the usual second
consequence: because no eye was ever on the strings, **all six carried a
cp1252 em dash (`0x97`)**, which is not a legal UTF-8 leading byte, so
every load printed a parse error and the text arrived with **U+FFFD**
where the dash should be. Twelve errors on `CivRoster.load_all()` alone
(#214). The files are rewritten as UTF-8 here, because surfacing a
corrupted string to a player is worse than not surfacing it at all.

Four calls:

**1. `signature_unit` is an ARCHETYPE, never a def id.** D-047's whole
shape is that `barracks.produces` lists archetypes and the roster
resolves one per civ; a def id here would be a second way of saying which
unit a civ fields, free to disagree with the first. It also makes the
failure mode safe: a civ naming an archetype it does not field resolves
to **nothing** and shows nothing, where a def id would have advertised
somebody else's troops.

**2. The six values are the design plan's own, not invented.**
`docs/plans/fantasy-civs.md`'s Signature row already named them —
Gatebreakers, the Barrow Shades, Dawnfletch Sentinels, Bowriders, Gilded
Sellswords, the Ember Bombard — and every one maps onto a real archetype
in the shipped roster (`breaker`, `shades`, `greatbow`, `bowriders`,
`sellswords`, `bombard`). A test asserts each resolves for its own civ,
so a renamed archetype goes red here rather than leaving the lobby
quietly showing nothing.

**3. The player's OWN seat gets a line; every other seat gets a
tooltip.** A line under all twenty-four seats would cost the seat list
the height `LobbyLayout` gives it — and the choice a player is making is
their own. Measured after: lobby content 784 + 64 margin against
`DESIGN_HEIGHT` 1000, so `test_lobby_layout`'s guard is satisfied with
room, which is the check that exists for exactly this kind of addition.

**4. Random says so rather than saying nothing.** Random is a real lobby
choice (D-048) that resolves to no `CivDef` until the match starts. A
blank line there would read as a missing feature; *"your civilisation is
drawn when the match starts"* reads as an answer.

**Rejected alternatives:** *a `summary` shown verbatim in every seat row*
— see (3). *Deriving the signature from stats* (highest damage, longest
range) — it would be a guess dressed as data, and it would change when
balance changed, which is not what a civ's identity should do.
*Sanitising the corruption at read time and leaving the files alone* —
`CivIdentity.readable` does strip U+FFFD, but as a backstop: the test
asserts the SHIPPED data needs no stripping, because a repair that hides
a broken file is how the file stays broken.

**Consequences:** `just lobby-shot`'s capture now picks a real civ for
its own seat instead of staying on Random — Random is the one state where
the identity line has least to say, so a screenshot left on it
photographs the least informative version of the screen. That is the same
"aim the instrument at the thing" rule `gen-terrain-shot` and
`gen-forest-preview` exist under, and the picture in
`artifacts/lobby.png` is what confirmed both the identity line and the
em dash rendering correctly.

**Revisit trigger:** a seventh civ with no signature (the schema allows
it and the lobby stays quiet, which is deliberate — but if it becomes
common the field should become required); or the lobby gaining a proper
civ-detail panel, at which point the full summary belongs there and the
seat line becomes the headline `CivIdentity.headline` already computes.
