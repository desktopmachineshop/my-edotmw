extends GutTest

## Guards D-052 — one colour per player.
##
## Colour used to come from `UnitDef.mesh_color`, so it described the unit
## TYPE: every spearman was the same grey whoever owned him. The first
## thing a player reads off a battle is whose units those are.


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
