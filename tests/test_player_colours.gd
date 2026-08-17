extends GutTest

## Guards D-052 — one colour per player.
##
## Colour used to come from `UnitDef.mesh_color`, so it described the unit
## TYPE: every spearman was the same grey whoever owned him. The first
## thing a player reads off a battle is whose units those are.
##
## The block at the bottom guards the other half of that, and it is the
## half a data test cannot reach: that a VIEW actually asks `colour_of`.
## Every check in this file passed throughout the defect
## D-20260817-minimap-squad-colours fixed — the minimap painting squads
## from a hardcoded own/enemy pair, so a player red everywhere else was
## cyan on the map and their ALLY was painted the enemy colour — because
## `PlayerColours` and `ClientState.colour_of` were both correct and one
## CALLER simply did not call them. Nothing here could see that.
##
## The two below are deliberately the parts that decision's own tests do
## NOT cover, rather than a second copy of them:
##
## - `test_minimap_paint.gd` and `test_ghost_squads_are_not_drawn.gd`
##   pin the squad marks and that `_update_minimap` builds them from
##   `MinimapPaint.squad_marks`. Neither says what COLOUR the marks are
##   then painted in — `_plot_minimap(..., Color.RED)` would satisfy
##   both. The invariant here is that the minimap invents no colour at
##   all;
## - nothing anywhere tied the LOBBY SWATCH to the battlefield, which is
##   the alignment the playtest report was actually about.
##
## Source text for the first, because `client.gd` needs a GPU and a live
## server (D-014), so a rule about what it draws is only real if reading
## the file can break it.


const CLIENT := "res://client.gd"


func _read(path: String) -> String:
	var handle := FileAccess.open(path, FileAccess.READ)
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


## The CODE of `func <name>(`, up to the next top-level `func`, with comment
## lines dropped — `test_ghost_squads_are_not_drawn.gd`'s helper and its
## reasoning: coarse enough to survive things moving inside the function,
## and comment-stripped because a check a COMMENT can satisfy is the
## vacuous check D-022's audit rule exists to prevent. This file's own
## checks name the colours they forbid in their comments, so without the
## stripping they would pass by reading themselves.
func _function_code(text: String, name: String) -> String:
	var start := text.find("func %s(" % name)
	if start < 0:
		return ""
	var end := text.find("\nfunc ", start + 1)
	var body := text.substr(start, -1 if end < 0 else end - start)

	var code := ""
	for line in body.split("\n"):
		if String(line).strip_edges().begins_with("#"):
			continue
		code += String(line) + "\n"
	return code


func test_the_palette_covers_the_target_player_count() -> void:
	# D-018 targets 20 concurrent players. A palette shorter than that
	# would put two players in the same colour in precisely the largest,
	# most confusing match.
	assert_gte(PlayerColours.count(), 20,
		"The palette must cover D-018's 20 players")


func test_every_colour_is_distinct() -> void:
	var seen := {}
	for i in range(PlayerColours.count()):
		var colour := PlayerColours.of_index(i)
		var key := "%.3f,%.3f,%.3f" % [colour.r, colour.g, colour.b]
		assert_false(seen.has(key), "Seats %s and %d share a colour" % [seen.get(key, "?"), i])
		seen[key] = str(i)


func test_colours_are_far_enough_apart_to_tell_apart() -> void:
	# Distinct is not the same as distinguishable. Two colours one bit
	# apart would pass the check above and be useless on a battlefield.
	for i in range(PlayerColours.count()):
		for j in range(i + 1, PlayerColours.count()):
			var a := PlayerColours.of_index(i)
			var b := PlayerColours.of_index(j)
			var separation := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			assert_gt(separation, 0.25,
				"Seats %d and %d are too close to tell apart (%.2f)" % [i, j, separation])


func test_out_of_range_clamps_rather_than_wrapping() -> void:
	# Wrapping would silently hand a twenty-first player somebody else's
	# colour. Clamping at least makes them look wrong rather than look
	# like an existing player.
	var last := PlayerColours.of_index(PlayerColours.count() - 1)
	assert_eq(PlayerColours.of_index(PlayerColours.count()), last,
		"A seat past the palette wrapped onto another player's colour")
	assert_eq(PlayerColours.of_index(PlayerColours.count() + 50), last)
	assert_eq(PlayerColours.of_index(-3), PlayerColours.of_index(0))


func test_a_client_reads_colour_from_seat_order() -> void:
	# Derived from the seat list every client already holds, so the two
	# sides agree without a message dedicated to colour.
	var state := ClientState.new()
	state.lobby = {"admin": 1, "seats": [
		{"kind": "human", "player": 1, "civ": "x", "team": 0, "name": "Player 1"},
		{"kind": "ai", "player": 1000, "civ": "y", "team": 0, "name": "AI 1000"},
	]}

	assert_eq(state.colour_of(1), PlayerColours.of_index(0))
	assert_eq(state.colour_of(1000), PlayerColours.of_index(1),
		"An AI seat takes the next palette entry, not one keyed off its player id")
	assert_ne(state.colour_of(1), state.colour_of(1000),
		"A human and an AI beside each other must not share a colour")


func test_the_lobby_swatch_and_the_battlefield_are_the_same_colour() -> void:
	# The alignment a player actually checks: the swatch beside your name in
	# the lobby (`_seat_row`, which colours by the seat's index in
	# `lobby.seats`) is the colour your army wears. Stated for the shape the
	# playtest reported — me, an ally, an enemy — because "seat order" and
	# "the swatch I looked at" being the same thing is the claim, and a
	# lobby list that ever sorted or filtered its rows would break it while
	# every other test here stayed green.
	var state := ClientState.new()
	state.player = 1
	state.lobby = {"admin": 1, "seats": [
		{"kind": "human", "player": 1, "civ": "x", "team": 1, "name": "me"},
		{"kind": "human", "player": 2, "civ": "x", "team": 1, "name": "ally"},
		{"kind": "ai", "player": 1000, "civ": "y", "team": 2, "name": "enemy"},
	]}
	var seats: Array = state.lobby["seats"]
	for i in range(seats.size()):
		assert_eq(state.colour_of(int(seats[i]["player"])),
			PlayerColours.of_index(i),
			"seat %d's colour is not the swatch the lobby drew for it" % i)

	# And an ALLY keeps their own colour rather than taking a relationship
	# one. Shared vision (D-050) means allied armies are on screen together,
	# so painting by relationship is what made an ally indistinguishable
	# from an enemy on the minimap.
	assert_true(state.are_allied(1, 2), "the fixture's teams are wrong")
	assert_ne(state.colour_of(1), state.colour_of(2),
		"an ally shares your colour — whose army is that?")
	assert_ne(state.colour_of(2), state.colour_of(1000),
		"an ally and an enemy share a colour")


func test_the_minimap_invents_no_colour_of_its_own() -> void:
	# The general form of the defect a playtest found. `_update_minimap`'s
	# squad pass used to read
	#
	#     Color(0.35, 0.95, 1.0) if _state.owns(squad) else Color(1.0, ...)
	#
	# — own/enemy cyan-and-red, invented on the spot, while the lobby, the
	# 3D view, the scoreboard and (since D-101) the minimap's OWN buildings
	# pass eight lines above all resolved `colour_of`.
	#
	# D-20260817-minimap-squad-colours fixed that pass and pinned its
	# STRUCTURE: squads come from `MinimapPaint.squad_marks` now, and a
	# concealed one has no mark by construction. What no check there says
	# is what colour a mark is painted in — `_plot_minimap(..., Color.RED)`
	# would satisfy every one of them. This is that half, and it is stated
	# as an invariant rather than as the line that was wrong: every colour
	# the minimap paints comes from somewhere shared — `colour_of` for
	# owners, `MinimapPaint.fogged` for ground, `_node_colour` for
	# resources — so a Color literal in here is the minimap inventing
	# meaning no other view of the same match agrees with.
	var code := _function_code(_read(CLIENT), "_update_minimap")
	assert_ne(code, "", "client.gd has no _update_minimap — this test is stale")
	assert_true(code.contains("colour_of("),
		"the minimap must resolve a mark's colour from its OWNER (D-052) — "
		+ "or the same army is two colours in two views of one battle")
	assert_false(code.contains("Color("),
		"_update_minimap builds a colour of its own; every colour it paints "
		+ "must come from a shared definition (D-052, D-083)")


func test_ai_ids_do_not_collide_with_human_ids() -> void:
	# AI players are numbered from 1000 (D-051), so a palette indexed by
	# PLAYER ID would give AI 1000 the same entry as player 1 under any
	# modulo of 20. Indexing by seat is what avoids that.
	var state := ClientState.new()
	state.lobby = {"admin": 1, "seats": [
		{"kind": "human", "player": 1, "civ": "x", "team": 0, "name": "P1"},
		{"kind": "ai", "player": 1000, "civ": "x", "team": 0, "name": "AI"},
		{"kind": "ai", "player": 1020, "civ": "x", "team": 0, "name": "AI"},
	]}
	var colours := {}
	for seat in state.lobby["seats"]:
		var c := state.colour_of(int(seat["player"]))
		var key := "%.3f,%.3f,%.3f" % [c.r, c.g, c.b]
		assert_false(colours.has(key), "Two seats share a colour: %s" % seat["name"])
		colours[key] = true
