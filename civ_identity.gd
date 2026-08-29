class_name CivIdentity
extends RefCounted

## What a player is told about a civilisation before they pick it (#283).
##
## All-static and pure, the same split as `hud_layout.gd`, `main_menu.gd`
## and `scoreboard.gd`, and for the same reason (D-061): the lobby needs
## a GPU and a window, and "what does this civ say about itself" needs
## neither. It is also the half that can be WRONG — a signature naming a
## unit the civ does not field, a summary nobody can read — and wrong
## here is invisible until somebody is staring at a lobby.
##
## ## Why this exists at all
##
## Six civs, each a distinct mechanical axis (quality, quantity, ranged
## attrition, mobility, economy, fortification), and the lobby showed
## **names only**. `CivDef.summary`'s own doc comment has said "a one-line
## pitch for the lobby, so the player knows what they are picking" since
## the field existed, and nothing read it — the declared-and-unread family
## again, and #214 found the strings were cp1252-corrupted the whole time
## precisely because no eye had ever been on them.
##
## Everything here is DERIVED from the `.tres`, so a seventh civ is a
## file (D-046 criterion 3) and no script learns a name.


## Everything the lobby shows about one civ: its own words, and the one
## unit it is known for.
##
## Returns `{display_name, summary, signature}` — `signature` empty when
## the civ names no signature or names one it does not field. Empty is a
## real answer, and the caller shows nothing rather than an apology: a
## civ added tomorrow has no signature until somebody decides one, and a
## lobby that said "unknown" would be worse than a lobby that said
## nothing.
static func describe(civ: CivDef) -> Dictionary:
	if civ == null:
		return {"display_name": "", "summary": "", "signature": ""}
	return {
		"display_name": civ.display_name,
		"summary": readable(civ.summary),
		"signature": signature_name(civ),
	}


## The display name of this civ's signature unit, or "" if it has none.
##
## Resolved through `UnitRoster.for_civ_archetype`, which is how every
## other part of the game turns "this civ, this archetype" into a unit
## (D-047). A civ naming an archetype it does not field therefore shows
## NOTHING rather than a unit belonging to somebody else — the failure
## mode a raw def id would have had.
static func signature_name(civ: CivDef) -> String:
	if civ == null or civ.signature_unit == &"":
		return ""
	var def := UnitRoster.for_civ_archetype(civ.id, civ.signature_unit)
	if def == null:
		return ""
	return def.display_name


## A summary safe to put on screen.
##
## `.tres` text reaches this having survived Godot's UTF-8 decode, and
## #214 is the standing proof that it does not always: all six civs
## carried a cp1252 em dash (`0x97`), which is not a legal UTF-8 leading
## byte, so every load printed a parse error and the string arrived with
## **U+FFFD** where the dash should be. The files are repaired, and this
## exists because the failure was invisible for as long as nothing read
## the field — a replacement character in a lobby is a bug report from a
## stranger, and one that costs them their good will before they have
## played.
##
## It does not "fix" anything: it strips, so a corrupted file shows a
## slightly clipped sentence instead of a mojibake box, and
## `tests/test_civ_identity.gd` fails on the shipped data if any civ ever
## needs it.
static func readable(text: String) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text[i]
		# U+FFFD REPLACEMENT CHARACTER — what Godot substitutes for a byte
		# it could not decode.
		if c.unicode_at(0) != 0xFFFD:
			out += c
	return out.strip_edges()


## The one-line form for a narrow lobby row: the first sentence, or the
## whole thing if it is already short.
##
## The summaries are two or three sentences of flavour; a seat row has
## one line. Cut at a sentence end rather than at a character count,
## because a summary truncated mid-word reads as a bug and a summary cut
## at its first full stop reads as a headline.
static func headline(summary: String, limit: int = 96) -> String:
	var clean := readable(summary)
	if clean.length() <= limit:
		return clean
	var stop := clean.find(". ")
	if stop > 0 and stop + 1 <= limit:
		return clean.substr(0, stop + 1)
	# No sentence break inside the limit: cut at the last space before it,
	# so a word is never split.
	var cut := clean.rfind(" ", limit)
	if cut <= 0:
		cut = limit
	return clean.substr(0, cut).strip_edges() + "…"
