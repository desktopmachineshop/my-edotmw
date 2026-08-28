extends GutTest

## Guards D-20260828-melee-does-not-cross-a-shoreline (naval plan §2.5,
## cut-list stage 5).
##
## `Combat._can_reach_domain` generalises D-076's `_can_reach_tier`. The
## whole of stage 5 is that predicate, because ships are squads: same
## bucket map, same disk scan, same D-024 arithmetic, and `combat.gd` is
## otherwise untouched.
##
## ## Two rules, and they are NOT the same rule
##
## The naval plan describes the new one as "the same sentence D-076
## already enforces between ground and wall-top". It is not, and this
## file exists partly to pin the difference:
##
##   - a SHORELINE stops melee in BOTH directions;
##   - a WALL stops melee in ONE — you cannot melee up onto a wall, and a
##     wall-top squad can melee the attackers at its foot.
##
## Implementing the plan as written would have taken that second
## behaviour away. It is shipped, and **no test covered it**, so nothing
## would have failed. It is covered here now.
##
## ## What this stage cannot test yet
##
## Nothing puts a squad in `DOMAIN_WATER` until stage 2 lands, so these
## drive the predicate directly rather than through a played tick. The
## live half arrives with stage 2 and belongs to it; what stage 5 owes is
## a rule that is right before anything depends on it.


const GROUND := SquadSim.DOMAIN_GROUND
const WALL := SquadSim.DOMAIN_WALL_TOP
const WATER := SquadSim.DOMAIN_WATER

const MELEE := "shock"
const RANGED := "missile"


func _reach(attacker_domain: int, attacker_class: String, target_domain: int) -> bool:
	return Combat._can_reach_domain(attacker_domain, attacker_class, target_domain)


# --- the shoreline, which is what stage 5 adds --------------------------

func test_land_melee_cannot_reach_a_ship() -> void:
	# The rule that makes a beach mean something: an army caught on one by
	# a warship is shot and cannot shoot back unless it brought archers.
	assert_false(_reach(GROUND, MELEE, WATER),
		"a swordsman cannot reach a hull out on the water")


func test_a_ram_cannot_reach_the_shore() -> void:
	# The other direction, and the half that is NOT true of walls. A ship
	# whose attack_range is short is a ship that can only fight other
	# ships — a data consequence of the roster, not a rule about rams.
	assert_false(_reach(WATER, MELEE, GROUND),
		"a ram cannot reach troops standing on land")


func test_ranged_crosses_the_shoreline_both_ways() -> void:
	assert_true(_reach(GROUND, RANGED, WATER), "archers on a beach can shoot a ship")
	assert_true(_reach(WATER, RANGED, GROUND), "and a gun-ship can shoot the beach")


func test_ships_fight_each_other() -> void:
	assert_true(_reach(WATER, MELEE, WATER), "a ram is for other ships")
	assert_true(_reach(WATER, RANGED, WATER))


# --- D-076, preserved exactly -------------------------------------------

func test_melee_still_cannot_reach_a_wall_top() -> void:
	# D-076's own sentence. Generalising the predicate must not soften it.
	assert_false(_reach(GROUND, MELEE, WALL),
		"you cannot melee somebody on top of a wall from the ground")


func test_ranged_still_reaches_a_wall_top() -> void:
	assert_true(_reach(GROUND, RANGED, WALL), "an archer's fire arcs up")


func test_a_wall_top_squad_can_still_melee_the_ground() -> void:
	# THE test this stage exists to write, and the reason the naval plan's
	# "same sentence" reading is wrong. A wall stops melee in ONE
	# direction; a shoreline stops it in both. This behaviour shipped with
	# D-076 and nothing covered it — so implementing the plan as written
	# would have removed it silently, and a defender on a wall would have
	# become unable to fight the attackers at its foot.
	assert_true(_reach(WALL, MELEE, GROUND),
		"a wall-top squad fights the attackers at its foot — that asymmetry is what "
		+ "makes climbing a defensive choice rather than a stalemate")


func test_a_wall_top_squad_reaches_another_wall_top_squad() -> void:
	assert_true(_reach(WALL, MELEE, WALL), "the fight on top of the wall is an ordinary one")


# --- the shape of the rule ----------------------------------------------

func test_the_same_domain_is_always_reachable() -> void:
	# Every rule here is about CROSSING. Nothing about a domain makes its
	# own occupants unreachable, and a future domain added without this
	# property would be one where an army cannot fight itself.
	for domain in [GROUND, WALL, WATER]:
		assert_true(_reach(domain, MELEE, domain),
			"domain %d must be able to fight within itself" % domain)
		assert_true(_reach(domain, RANGED, domain))


func test_ranged_crosses_every_boundary() -> void:
	# Stated once over the whole matrix rather than case by case, because
	# it is the half of the rule with no exceptions — and a future domain
	# that quietly acquired one should fail here.
	for attacker in [GROUND, WALL, WATER]:
		for target in [GROUND, WALL, WATER]:
			assert_true(_reach(attacker, RANGED, target),
				"ranged must reach %d from %d" % [target, attacker])


func test_the_three_domains_are_distinct_values() -> void:
	# A vacuity guard. Every assertion above compares domains, so two
	# constants that collided would make most of this file pass by
	# meaning the same thing.
	var seen := {}
	for domain in [GROUND, WALL, WATER]:
		assert_false(seen.has(domain), "two domains share the value %d" % domain)
		seen[domain] = true
	assert_eq(seen.size(), 3)


func test_water_is_declared_where_the_field_lives() -> void:
	# The constants belong to `SquadSim` because `_tier` does, and stage 2
	# will dispatch on them. A bare `2` in combat.gd would be a second
	# definition of the same fact — the shape this project spends most of
	# its decision entries avoiding.
	var combat := FileAccess.get_file_as_string("res://combat.gd")
	assert_false(combat.is_empty(), "could not read combat.gd to scan it")
	assert_true(combat.contains("SquadSim.DOMAIN_WATER"),
		"combat.gd must name the domain rather than compare against a literal")


func test_the_old_predicate_name_is_gone() -> void:
	# Renamed rather than wrapped, so there is one predicate. A
	# `_can_reach_tier` left forwarding would be a second name for the
	# same rule and the next reader would not know which was current.
	var combat := FileAccess.get_file_as_string("res://combat.gd")
	assert_false(combat.contains("_can_reach_tier("),
		"combat.gd still has the pre-naval predicate — there must be exactly one")
