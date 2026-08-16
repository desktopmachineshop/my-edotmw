extends GutTest

## Guards the minimap's overlay (D-101): that buildings are on it at all,
## that they stay on it while out of vision, and that a razed one leaves.
##
## Pure, the same split as `test_render_cull.gd`, `test_selection_pick.gd`
## and `test_ground_cover.gd`: the client needs a GPU (D-014), and every
## decision that was wrong here — which entities get painted, and how big
## — is arithmetic over plain dictionaries.
##
## The bug this file exists for is an ABSENCE, not a miscalculation.
## `_update_minimap` painted terrain, squad dots and resource nodes and
## made no pass over `_state.buildings` whatsoever, so persistent-explored
## building fog (D-030) had no minimap representation and a playtest could
## not judge "buildings once seen stay, squads do not" — there was nothing
## to watch persist. That is the declared-and-unread family CLAUDE.md
## warns about wearing yet another disguise: `ClientState.buildings` was
## correct, replicated, hashed and read by four other views, and the
## minimap simply never looked at it. Nothing failed.
##
## So the last test in here is structural rather than arithmetic: it reads
## `client.gd` and fails if the pass is ever dropped again. A pure module
## cannot notice that its only caller stopped calling it.

const CLIENT_SCRIPT := "res://client.gd"


func _building(cell: int, owner: int, def_id: String,
		destroyed: bool = false) -> Dictionary:
	return {"cell": cell, "owner": owner, "def_id": def_id,
		"destroyed": destroyed}


# --- the reported bug -------------------------------------------------

func test_a_known_building_is_painted() -> void:
	# THE case. One town centre in `ClientState.buildings` produces one
	# mark to paint. Before the fix there was no function to ask and no
	# pass in the client that asked it, so the answer was structurally
	# empty however many buildings a player owned.
	var marks := MinimapPaint.building_marks({
		1001: _building(500, 2, "town_centre"),
	})
	assert_eq(marks.size(), 1, "the town centre is painted")
	assert_eq(int(marks[0]["cell"]), 500)
	assert_eq(int(marks[0]["owner"]), 2, "in its owner's colour, not the viewer's")


func test_a_building_out_of_current_vision_is_still_painted() -> void:
	# The point of criterion 3 of the fog playtest, and the reason this is
	# not gated on `_explored` or on vision: a client holds a building
	# only because the server showed it once (D-030), and it must keep
	# showing it after the scout walks home. `building_marks` is given no
	# vision state at all, which is how that is enforced rather than
	# remembered — there is nothing here to gate on.
	var scouted := {
		2001: _building(120, 3, "barracks"),
		2002: _building(121, 3, "tower"),
	}
	assert_eq(MinimapPaint.building_marks(scouted).size(), 2,
		"a scouted enemy base stays on the minimap")


func test_a_destroyed_building_is_not_painted() -> void:
	# Tombstones stay in `ClientState.buildings` — the client is told a
	# building died, not that it should forget it existed — so a razed
	# base that kept its footprint would report an enemy that is gone.
	var marks := MinimapPaint.building_marks({
		3001: _building(10, 1, "town_centre"),
		3002: _building(11, 1, "barracks", true),
	})
	assert_eq(marks.size(), 1, "only the standing building is painted")
	assert_eq(int(marks[0]["cell"]), 10)


func test_marks_come_out_in_a_stable_order() -> void:
	# Two buildings on the same cell (a wall and the tower upgrading it,
	# mid-swap) must not swap which is on top between repaints, or the
	# minimap flickers at 4 Hz.
	var buildings := {7: _building(64, 1, "wall"), 3: _building(64, 2, "tower")}
	var first := MinimapPaint.building_marks(buildings)
	assert_eq(int(first[0]["owner"]), 2, "lowest wire id paints first")
	assert_eq(int(first[1]["owner"]), 1)


# --- how big, and from what -------------------------------------------

func test_a_settlement_reads_bigger_than_a_wall() -> void:
	# Against the SHIPPED defs, not a fixture: the hierarchy exists so a
	# player can find their base at a glance, and a mechanism that works
	# on invented numbers while the shipped ones are all equal is D-066's
	# failure wearing a green verdict.
	var town := MinimapPaint.building_size(&"town_centre")
	var wall := MinimapPaint.building_size(&"wall")
	var barracks := MinimapPaint.building_size(&"barracks")
	assert_gt(town, wall, "the town centre outranks a wall segment")
	assert_gt(town, barracks, "and outranks a barracks")
	assert_gt(town, MinimapPaint.SQUAD_CELLS,
		"and is bigger than a squad dot, which is the question a minimap is asked")
	assert_eq(wall, MinimapPaint.BUILDING_CELLS,
		"a wall chain reads as a line, not a blob")


func test_an_unknown_def_still_paints() -> void:
	# A def this build does not ship — what a mixed-version match produces
	# (D-094 names the handshake that does not exist yet). Falling back is
	# better than a building silently vanishing from the map.
	assert_eq(MinimapPaint.building_size(&"not_a_real_building"),
		MinimapPaint.BUILDING_CELLS)


# --- the torus tax ----------------------------------------------------

func test_a_two_cell_mark_starts_at_its_own_cell() -> void:
	# What the squad dot has always done, pinned because `_plot_minimap`
	# now delegates to this: an even blob starts at the cell rather than
	# straddling it, so a mark still lands where its owner stands.
	var pixels := MinimapPaint.footprint(Vector2i(4, 5), 2, 84, 96)
	assert_eq(pixels.size(), 4)
	assert_true(pixels.has(Vector2i(4, 5)), "covers its own cell")
	assert_true(pixels.has(Vector2i(5, 6)))


func test_an_odd_mark_centres_on_its_cell() -> void:
	var pixels := MinimapPaint.footprint(Vector2i(10, 10), 3, 84, 96)
	assert_eq(pixels.size(), 9)
	assert_true(pixels.has(Vector2i(9, 9)), "extends up and left")
	assert_true(pixels.has(Vector2i(11, 11)), "and down and right")


func test_a_mark_at_the_seam_wraps() -> void:
	# D-008's recurring tax. A town centre founded on the last column
	# belongs on the first one too, or half of it is simply not drawn.
	var pixels := MinimapPaint.footprint(Vector2i(83, 95), 3, 84, 96)
	assert_true(pixels.has(Vector2i(0, 0)), "wraps in x and y together")
	assert_true(pixels.has(Vector2i(82, 94)), "and still covers its own side")
	for pixel in pixels:
		assert_true(pixel.x >= 0 and pixel.x < 84 and pixel.y >= 0 and pixel.y < 96,
			"every pixel is inside the image: %s" % pixel)


# --- and that the client still asks ------------------------------------

func test_the_client_paints_buildings_on_the_minimap() -> void:
	# The check that would have caught the reported bug, and the only one
	# in this file that could: everything above passes with `client.gd`
	# never calling any of it, which is exactly the state the game shipped
	# in. Same idiom as `test_civs.gd`'s no-civ-names scan and
	# `world_look.gd`'s stray-light scan — a source-level guard, because
	# the client cannot be run headless (D-014).
	var handle := FileAccess.open(CLIENT_SCRIPT, FileAccess.READ)
	assert_not_null(handle, "client.gd is readable")
	var source := handle.get_as_text()
	handle.close()

	var start := source.find("func _update_minimap")
	assert_gt(start, -1, "_update_minimap still exists")
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start if end > start else -1)
	assert_true(body.contains("MinimapPaint.building_marks"),
		"_update_minimap makes a pass over the buildings the client knows")
	assert_true(body.contains("_state.buildings"),
		"and paints them from replicated building state")
