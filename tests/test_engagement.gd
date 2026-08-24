extends GutTest

## Guards D-20260819-only-men-in-contact-fight (Tier 2 of the RTW
## formations decision): the contact set is a pure function of derived
## positions, frontage decides the exchange, seam battles still resolve,
## and the three-tier decision's collapse trigger stays untripped — no
## pairing is ever remembered across ticks.

const W := 32
const H := 16


func _space() -> TorusSpace:
	return TorusSpace.new(W, H, 1.0)


func _sim() -> SquadSim:
	return SquadSim.new(_space(), CurveReplicator.new())


func _line(points: Array) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for p in points:
		out.append(Transform3D(Basis(), p))
	return out


## A real melee def from the roster (the D-066 rule: shipped numbers, not
## caricatures, for anything a player is supposed to FEEL).
##
## Generals are skipped BY FIELD. This scan used to land on the old
## founding party purely because `founders` sorted first; with that def
## removed (D-20260823-the-opening-is-a-crew-and-a-general) it landed on a
## GENERAL instead, whose morale aura and death shock apply to both sides
## of a frontage experiment and are not what this file measures. A fixture
## that takes "whatever sorts first" is picking a roster ORDERING, not a
## unit.
func _melee_def() -> UnitDef:
	for candidate in UnitRoster.load_all():
		if candidate.damage > 0.0 and candidate.armour_class != "missile" \
				and candidate.carry_capacity == 0 and not candidate.is_general:
			return candidate
	return null


# --- the contact set itself -------------------------------------------

func test_contact_counts_only_men_in_reach() -> void:
	var attackers := _line([
		Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, -8),
	])
	var defenders := _line([Vector3(0, 0, 2), Vector3(1, 0, 2)])
	var count := Engagement.contact_count(attackers, defenders, 3.0)
	assert_eq(count, 2,
		"the two front men reach; the straggler eight units back does not")
	assert_eq(Engagement.contact_count(attackers, defenders, 3.0), count,
		"pure: the same inputs count the same men, with nothing remembered")


func test_a_line_against_a_columns_flank_lands_more_men() -> void:
	# A defender column, deep and narrow, marching axis +z.
	var column_points: Array = []
	for rank in range(8):
		column_points.append(Vector3(0.0, 0.0, float(rank) * 1.15))
	var column := _line(column_points)

	# The same eight attackers as a line ACROSS its narrow front...
	var frontal_points: Array = []
	for file in range(8):
		frontal_points.append(Vector3(float(file) - 3.5, 0.0, -2.6))
	var frontal := _line(frontal_points)

	# ...and alongside its long flank.
	var flank_points: Array = []
	for file in range(8):
		flank_points.append(Vector3(2.6, 0.0, float(file) * 1.15))
	var flank := _line(flank_points)

	var reach := Engagement.contact_reach(1.5)
	var frontal_contact := Engagement.contact_count(frontal, column, reach)
	var flank_contact := Engagement.contact_count(flank, column, reach)
	assert_gt(flank_contact, frontal_contact,
		"envelopment is geometry now: a line on the column's long side "
		+ "lands more men than one across its narrow front "
		+ "(%d vs %d)" % [flank_contact, frontal_contact])


func test_the_reach_slack_keeps_engaged_front_ranks_in_contact() -> void:
	# Two front ranks a full cell apart — farther than a melee
	# attack_range of 1.5 on its own. Without the 2×MAX_STEP slack this
	# is the zero-contact stand-off the decision's second detail is
	# about: engagement saying "fight" while contact says "cannot".
	var a := _line([Vector3(0, 0, 0)])
	var b := _line([Vector3(0, 0, 1.74)])
	assert_eq(Engagement.contact_count(a, b, Engagement.contact_reach(1.5)), 1,
		"a man a cell from his opponent fights — he is drawn stepping in, "
		+ "so he counts as fighting")


func test_the_torus_tax_is_paid() -> void:
	var space := _space()
	var offsets := space.lattice_offsets()
	# Two men adjacent ACROSS the x seam: canonical coordinates put them
	# nearly a whole map apart.
	var here := space.to_world(Vector2i(0, 4))
	var there := space.to_world(Vector2i(W - 1, 4))
	var align := Engagement.aligning_offset(here, there, offsets)
	assert_ne(align, Vector3.ZERO,
		"the defender's nearest copy is across the seam, not the canonical one")
	var moved := Engagement.shifted(_line([there]), align)
	assert_lt(here.distance_to(moved[0].origin), 3.0,
		"aligned, the neighbours are neighbours again")
	# And mid-map, alignment is the no-op fast path returning the SAME
	# array object, so the common case costs one comparison.
	var mid := _line([Vector3(10, 0, 5)])
	assert_true(Engagement.shifted(mid, Vector3.ZERO) == mid,
		"the zero offset must not copy the array")


func test_engagement_is_all_static() -> void:
	var handle := FileAccess.open("res://engagement.gd", FileAccess.READ)
	assert_not_null(handle)
	var text := handle.get_as_text()
	handle.close()
	for line in text.split("\n"):
		assert_false(line.begins_with("var "),
			"Engagement may hold no state — a remembered pairing is the "
			+ "three-tier decision's collapse trigger, and the answer is a "
			+ "re-decision, not a cache: '%s'" % line)


# --- what combat does with it -----------------------------------------

func test_a_wide_line_beats_a_deep_column_of_the_same_troops() -> void:
	# THE frontage exit criterion, played as a whole encounter with a
	# real def (the D-066 rule). Same troops, same strength, same ground;
	# the only difference is formation. The line lands more men per
	# exchange, so when the dust settles it has more men standing.
	var def := _melee_def()
	assert_not_null(def, "the roster must ship a melee def to test with")
	var sim := _sim()
	var line_squad := sim.add_squad(def, 1, Vector2i(8, 8))
	var column_squad := sim.add_squad(def, 2, Vector2i(9, 8))
	sim.set_shape(line_squad, "line")
	sim.set_shape(column_squad, "column")

	for _i in range(600):
		sim.tick()
		if sim.alive_of(line_squad) <= 0 or sim.alive_of(column_squad) <= 0:
			break

	assert_gt(sim.alive_of(line_squad), sim.alive_of(column_squad),
		"frontage decides: the line keeps more men standing (%d vs %d)"
		% [sim.alive_of(line_squad), sim.alive_of(column_squad)])


func test_an_engagement_across_the_seam_still_kills() -> void:
	# The same fight, straddling the x seam. Before the aligning offset,
	# contact measured canonical coordinates, counted zero men, and a
	# seam battle resolved no damage forever while the (wrap-aware) cell
	# scan said the squads were engaged.
	var def := _melee_def()
	var sim := _sim()
	var a := sim.add_squad(def, 1, Vector2i(0, 8))
	var b := sim.add_squad(def, 2, Vector2i(W - 1, 8))
	var before := sim.alive_of(a) + sim.alive_of(b)
	for _i in range(200):
		sim.tick()
		if sim.alive_of(a) + sim.alive_of(b) < before:
			break
	assert_lt(sim.alive_of(a) + sim.alive_of(b), before,
		"squads adjacent across the seam must fight, not stare at "
		+ "phantoms a map away")
