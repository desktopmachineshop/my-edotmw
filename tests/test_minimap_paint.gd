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


# --- three fog tones (D-20260817) --------------------------------------------
#
# The minimap drew TWO states while `TerrainFog` (D-106) computed three, so
# remembered ground and ground under a scout's eyes stayed the same pixel
# here after the 3D view had learned to tell them apart. Observed to fail
# before the fix: collapsing `fogged`'s EXPLORED branch to return `colour`
# — exactly what the client did — reddens the first three tests below.


func _tones(colour: Color) -> Array[Color]:
	return [
		MinimapPaint.fogged(colour, TerrainFog.UNEXPLORED),
		MinimapPaint.fogged(colour, TerrainFog.EXPLORED),
		MinimapPaint.fogged(colour, TerrainFog.VISIBLE),
	]


## Perceptual-ish brightness, spelled out rather than `get_luminance` so the
## ordering assertion below reads.
func _luma(colour: Color) -> float:
	return 0.2126 * colour.r + 0.7152 * colour.g + 0.0722 * colour.b


## Distance between two tones as the largest single-channel difference —
## channel-wise rather than luma, so a pair differing only in hue still
## counts as separated.
func _gap(a: Color, b: Color) -> float:
	return maxf(maxf(absf(a.r - b.r), absf(a.g - b.g)), absf(a.b - b.b))


func test_the_three_fog_levels_are_three_distinct_tones() -> void:
	# The whole defect in one assertion: EXPLORED and VISIBLE were equal.
	for biome in TerrainGen.Biome.values():
		var tone := _tones(TerrainGen.color_of(biome))
		assert_ne(tone[1], tone[2],
			"biome %d: remembered ground is not drawn as live vision" % biome)
		assert_ne(tone[1], tone[0],
			"biome %d: remembered ground is not drawn as never-seen" % biome)
		assert_ne(tone[0], tone[2], "biome %d: never-seen is not live" % biome)


func test_the_three_tones_are_separated_enough_to_read() -> void:
	# Distinct is not the same as legible, and "isn't distinct enough" was
	# the original report. A one-per-255 step satisfies the test above and
	# changes nothing on screen — the D-066 failure mode.
	for biome in TerrainGen.Biome.values():
		var tone := _tones(TerrainGen.color_of(biome))
		assert_gt(_gap(tone[1], tone[2]), 0.08,
			"biome %d: remembered reads as dimmer than live" % biome)
		assert_gt(_gap(tone[0], tone[1]), 0.08,
			"biome %d: never-seen reads as darker than remembered" % biome)


func test_remembered_ground_sits_between_the_other_two() -> void:
	# The three tones are one line, not three unrelated colours. If EXPLORED
	# were ever brighter than VISIBLE the minimap would be advertising the
	# ground the player knows least about.
	for biome in TerrainGen.Biome.values():
		var tone := _tones(TerrainGen.color_of(biome))
		assert_lt(_luma(tone[0]), _luma(tone[1]),
			"biome %d: never-seen is the darkest" % biome)
		assert_lt(_luma(tone[1]), _luma(tone[2]),
			"biome %d: live vision is the brightest" % biome)


func test_live_vision_is_the_biome_colour_untouched() -> void:
	# Fog only ever SUBTRACTS. `biome_color` is the single source of truth
	# for this map's look (D-083) — a minimap that brightened live cells
	# would show a palette no other view of the same map has.
	for biome in TerrainGen.Biome.values():
		var colour := TerrainGen.color_of(biome)
		assert_eq(MinimapPaint.fogged(colour, TerrainFog.VISIBLE), colour,
			"biome %d is drawn exactly as biome_color says when in sight" % biome)


func test_unexplored_ignores_the_terrain_under_it() -> void:
	# Ground nobody has scouted must not leak its biome through the fog.
	var tones := {}
	for biome in TerrainGen.Biome.values():
		tones[MinimapPaint.fogged(TerrainGen.color_of(biome),
			TerrainFog.UNEXPLORED)] = true
	assert_eq(tones.size(), 1, "unexplored ground is one tone, not a dimmed map")


func test_the_minimap_and_the_ground_read_one_fog_field() -> void:
	# The resolution that matters more than the tones: `TerrainFog` is the
	# ONE definition of what this player can see, and the minimap asks it
	# rather than keeping a second explored/visible set of its own. Two
	# derivations of one player's sight would drift silently, and the
	# symptom would be a minimap disagreeing with the ground it sits beside.
	var handle := FileAccess.open(CLIENT_SCRIPT, FileAccess.READ)
	assert_not_null(handle, "client.gd is readable")
	var source := handle.get_as_text()
	handle.close()

	var start := source.find("func _update_minimap")
	assert_gt(start, -1, "_update_minimap still exists")
	var end := source.find("\nfunc ", start + 1)
	var body := source.substr(start, end - start if end > start else -1)

	assert_true(body.contains("_fog.level_at"),
		"the minimap reads TerrainFog's three levels, not just is_explored")
	assert_true(body.contains("MinimapPaint.fogged"),
		"and shades its pixels through MinimapPaint.fogged")
	assert_false(source.contains("MinimapFog"),
		"no second fog module survives beside TerrainFog")
	assert_false(source.contains("HudTheme.BG_VOID.darkened(0.5)"),
		"the client no longer hand-rolls the unexplored tone")


func test_buildings_are_painted_unfogged() -> void:
	# The deliberate exception, and the one place the two features could
	# have silently eaten each other: D-101 draws a building from
	# KNOWLEDGE, so fading one because nobody is watching it would re-gate
	# it on vision through the back door. The building pass must not run
	# its colour through `fogged`.
	var handle := FileAccess.open(CLIENT_SCRIPT, FileAccess.READ)
	assert_not_null(handle, "client.gd is readable")
	var source := handle.get_as_text()
	handle.close()

	var start := source.find("MinimapPaint.building_marks")
	assert_gt(start, -1, "the building pass still exists")
	var end := source.find("\n\n", start)
	var pass_body := source.substr(start, end - start if end > start else 240)
	assert_false(pass_body.contains("fogged"),
		"a known building is drawn at full strength wherever it stands")
