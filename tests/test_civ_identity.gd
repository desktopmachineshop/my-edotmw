extends GutTest

## Guards #283: the lobby tells a player what a civilisation IS, not just
## what it is called — and #214's corruption cannot come back unseen.
##
## Six civs, each a distinct mechanical axis (quality, quantity, ranged
## attrition, mobility, economy, fortification), and the lobby showed
## names only. `CivDef.summary`'s doc comment has promised "a one-line
## pitch for the lobby" since the field existed and nothing read it — the
## declared-and-unread family, and the reason the strings sat cp1252-
## corrupted through six milestones without anyone noticing.


func _civs() -> Array:
	var out := []
	for id in CivRoster.ids():
		out.append(CivRoster.by_id(id))
	return out


# --- the data is readable, and stays readable -------------------------

func test_no_shipped_summary_contains_a_replacement_character() -> void:
	# THE #214 regression. A cp1252 byte in a `.tres` is not a legal UTF-8
	# leading byte, so Godot substitutes U+FFFD and prints a parse error —
	# twelve of them on `CivRoster.load_all()` alone. Nothing failed,
	# because nothing read the field. This is what makes that impossible
	# to reintroduce quietly, and it asserts the SHIPPED data rather than
	# a fixture.
	for civ in _civs():
		assert_false(civ.summary.is_empty(),
			"%s must say what it is — the lobby shows this" % civ.id)
		assert_eq(CivIdentity.readable(civ.summary), civ.summary.strip_edges(),
			("%s's summary contains a character Godot could not decode. A cp1252 "
			+ "byte in the .tres is the usual cause (#214) — the file needs to be "
			+ "written as UTF-8, not repaired here.") % civ.id)


func test_a_corrupted_summary_is_stripped_rather_than_shown() -> void:
	# The belt to the braces above. If a file ever regresses, a player
	# sees a slightly clipped sentence rather than a mojibake box — and
	# the test above still goes red so somebody fixes the file.
	var mangled := "Holds a line %s and cannot be everywhere." % char(0xFFFD)
	assert_false(CivIdentity.readable(mangled).contains(char(0xFFFD)),
		"a replacement character must never reach the screen")
	assert_true(CivIdentity.readable(mangled).begins_with("Holds a line"))


# --- every civ's signature is a unit it actually fields ---------------

func test_every_civ_names_a_signature_unit_it_actually_fields() -> void:
	# The field is an ARCHETYPE, resolved per civ (D-047) — so a civ
	# cannot accidentally advertise somebody else's troops, which a raw
	# def id would have allowed. And it cannot rot: rename an archetype
	# and this goes red rather than the lobby quietly showing nothing.
	for civ in _civs():
		assert_ne(civ.signature_unit, &"",
			"%s should name the one unit a player picking it is told about" % civ.id)
		var def := UnitRoster.for_civ_archetype(civ.id, civ.signature_unit)
		assert_not_null(def,
			("%s's signature archetype '%s' resolves to no unit of that civ — "
			+ "either the archetype was renamed or the civ does not field it")
			% [civ.id, civ.signature_unit])
		if def != null:
			assert_eq(CivIdentity.signature_name(civ), def.display_name,
				"and the lobby must show that unit's own name")


func test_no_two_civs_share_a_signature() -> void:
	# Not a rule the schema enforces, and worth asserting because the
	# whole point is that six civs read as six DIFFERENT things. Two civs
	# advertising the same unit would be a copy-paste nobody would catch
	# by reading one file.
	var seen := {}
	for civ in _civs():
		var name := CivIdentity.signature_name(civ)
		if name.is_empty():
			continue
		assert_false(seen.has(name),
			"%s and %s both advertise '%s'" % [civ.id, seen.get(name, ""), name])
		seen[name] = civ.id


func test_a_civ_with_no_signature_shows_nothing_rather_than_an_apology() -> void:
	# A civ added tomorrow has no signature until somebody decides one,
	# and the lobby should be quiet about it rather than printing
	# "unknown" at a player who is choosing.
	var blank := CivDef.new()
	blank.id = &"nameless"
	assert_eq(CivIdentity.signature_name(blank), "")
	assert_eq(String(CivIdentity.describe(blank)["signature"]), "")

	# The same for an archetype this civ does not field: it must resolve
	# to NOTHING rather than to another civ's unit.
	var wrong := CivDef.new()
	wrong.id = &"nameless"
	wrong.signature_unit = &"bombard"
	assert_eq(CivIdentity.signature_name(wrong), "",
		"a civ must never advertise a unit belonging to somebody else")


# --- what the lobby is handed -----------------------------------------

func test_describe_carries_the_three_things_a_chooser_needs() -> void:
	for civ in _civs():
		var shown := CivIdentity.describe(civ)
		assert_eq(String(shown["display_name"]), civ.display_name)
		assert_false(String(shown["summary"]).is_empty(),
			"%s must have something to say" % civ.id)
		assert_false(String(shown["signature"]).is_empty(),
			"%s must name its signature unit" % civ.id)


func test_describe_survives_a_null_civ() -> void:
	# "Random" is a real lobby choice (D-048) and resolves to no CivDef
	# until the match starts, so the caller hands this null routinely.
	var shown := CivIdentity.describe(null)
	assert_eq(String(shown["display_name"]), "")
	assert_eq(String(shown["summary"]), "")
	assert_eq(String(shown["signature"]), "")


func test_a_headline_is_cut_at_a_sentence_not_mid_word() -> void:
	# A seat row has one line and the summaries are two or three
	# sentences. A summary truncated mid-word reads as a bug; one cut at
	# its first full stop reads as a headline.
	var two := "Quality over everything. Few, mighty foot who win any fight they are allowed to stand in."
	assert_eq(CivIdentity.headline(two, 40), "Quality over everything.",
		"cut at the sentence end when there is one inside the limit")

	var one_long := "A single very long sentence about a civilisation that simply keeps going and going without any full stop at all"
	var cut := CivIdentity.headline(one_long, 40)
	assert_lt(cut.length(), one_long.length(), "a long line must actually be shortened")
	assert_true(cut.ends_with("…"), "and say that it was: %s" % cut)
	assert_false(cut.contains("goin…"), "never mid-word: %s" % cut)

	var short := "Short enough already."
	assert_eq(CivIdentity.headline(short, 40), short, "a short summary is left alone")


func test_every_shipped_summary_has_a_usable_headline() -> void:
	# The shipped data, not a fixture: a summary whose first sentence is
	# longer than a lobby row is a real possibility, and the answer is to
	# know rather than to find out in a screenshot.
	for civ in _civs():
		var line := CivIdentity.headline(civ.summary)
		assert_false(line.is_empty(), "%s's headline is empty" % civ.id)
		assert_lt(line.length(), 130,
			"%s's headline is too long for a seat row: %s" % [civ.id, line])


# --- and the lobby actually reads it ----------------------------------

func test_the_lobby_shows_what_this_file_computes() -> void:
	# The caller-exists check (D-106's rule as a test), and the exact
	# defect this ticket is about: `CivDef.summary` was correct, loaded
	# and read by NOBODY for six milestones while its own doc comment
	# said the lobby showed it.
	var client := _read("res://client.gd")
	assert_true(client.contains("CivIdentity."),
		("client.gd must show a civ's identity in the lobby. A summary nothing "
		+ "reads is the declared-and-unread defect this ticket exists to fix — "
		+ "adding a second one would be a joke at the project's expense."))


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	assert_not_null(handle, "%s must exist and be readable" % path)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text
