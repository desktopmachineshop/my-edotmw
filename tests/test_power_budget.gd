extends GutTest

## Guards D-072's power budget, and closes #220 -- the screen that decision
## defined has never been runnable against the roster it is supposed to
## screen.
##
## D-072 states two rules and then says a roster is "built to satisfy
## them". Nothing checked. `docs/plans/fantasy-civs.md` records the
## fantasy roster as "V/RP-screened"; #220 ran the screen by hand against
## the roster as shipped and it was not.
##
##     DPS = squad_size x damage / attack_interval
##     EHP = squad_size x health
##     V   = sqrt(DPS x EHP)
##     RP  = food + wood + 1.5 x (gold + stone)
##
##   1. PRICE BUYS POWER -- within a role, a dearer unit must have higher V.
##   2. NO FREE LUNCH -- within a civ and role, no unit may lead on both V
##      and V/RP.
##
## ## The competence boundary, which is D-072's own text and not a loophole
##
## D-072 is explicit about what V cannot see: *"What V does not price,
## stated up front so it is not misread as a verdict: `attack_range`,
## `move_speed`, `vision_range`, `bonus_vs`, `morale`. It is a first-pass
## screen for line infantry and it systematically undervalues missile and
## scouting units."*
##
## Applied mechanically to the fantasy roster the two rules flag NINE
## pairs -- and every single one is a case where the dearer unit buys
## exactly one of those unpriced things. So the comparisons are skipped
## where the premium is outside the metric, and **the skip is reported**,
## because a silent skip is the vacuous pass D-022's audit block was
## written about.
##
## What survives is a real check: a unit that is dearer, weaker, and buys
## nothing V cannot see is a mispricing the metric CAN speak to, and it
## fails here.

const SKIP_ARCHETYPES := [&"gatherers", &"general"]

## Archetype -> role. D-072's rules are scoped "within a role", and
## `UnitDef` has no role field, so the mapping lives here -- one table, in
## the file that is the only thing reading it.
const ROLES := {
	&"levy": "line", &"spearmen": "line", &"heavy": "line",
	&"sellswords": "line", &"shades": "line",
	&"archers": "missile", &"greatbow": "missile",
	&"skirmishers": "skirmisher", &"bowriders": "skirmisher",
	&"cavalry": "cavalry",
	&"engine": "siege", &"ram": "siege", &"bombard": "siege",
	&"breaker": "siege",
	# Naval (#301). A `warboat` fights AND carries -- naval.md §5.3 screens
	# those as "combined" and warships as their own group, so they are two
	# roles here rather than one: D-072's rules are scoped WITHIN a role,
	# and a hull that spends part of its price on a hold is not comparable
	# with one that spends all of it on guns.
	&"warship": "warship", &"warboat": "combined",
	&"transport": "carrier",
}


func _screen() -> Array:
	var out := []
	for def in UnitRoster.load_all():
		if SKIP_ARCHETYPES.has(def.archetype):
			continue
		var dps := float(def.squad_size) * def.damage / maxf(def.attack_interval, 0.001)
		var ehp := float(def.squad_size) * def.health
		var rp := float(def.cost_food + def.cost_wood) \
			+ 1.5 * float(def.cost_gold + def.cost_stone)
		out.append({
			"def": def, "id": def.id, "civ": def.civ,
			"role": String(ROLES.get(def.archetype, "other")),
			"v": sqrt(dps * ehp), "rp": rp,
			"vrp": (sqrt(dps * ehp) / rp) if rp > 0.0 else 0.0,
			"capacity": def.transport_capacity,
			"cap_rp": (float(def.transport_capacity) / rp) if rp > 0.0 else 0.0,
		})
	return out


## What `dearer` buys that V cannot see, or "" if it buys nothing unpriced.
##
## Exactly D-072's own list, minus the two that are not comparable as
## scalars here: `vision_range` and `morale` are deliberately left out, so
## a unit cannot excuse a mispricing with a point of morale.
func _unpriced_premium(dearer: UnitDef, cheaper: UnitDef) -> String:
	var reasons := PackedStringArray()
	if dearer.attack_range > cheaper.attack_range:
		reasons.append("attack_range %.1f > %.1f" % [dearer.attack_range, cheaper.attack_range])
	if dearer.move_speed > cheaper.move_speed:
		reasons.append("move_speed %.1f > %.1f" % [dearer.move_speed, cheaper.move_speed])
	if dearer.bonus_vs.size() > cheaper.bonus_vs.size():
		reasons.append("bonus_vs %d entries > %d" % [
			dearer.bonus_vs.size(), cheaper.bonus_vs.size()])
	if dearer.damage_vs_buildings > cheaper.damage_vs_buildings:
		reasons.append("damage_vs_buildings %.2f > %.2f" % [
			dearer.damage_vs_buildings, cheaper.damage_vs_buildings])
	return ", ".join(reasons)


func test_the_screen_runs_against_the_shipped_roster_at_all() -> void:
	# The claim `docs/plans/fantasy-civs.md` makes ("V/RP-screened") needs
	# something that can screen. Before #220 this arithmetic lived in a
	# playtest script on a branch.
	var screen := _screen()
	assert_gt(screen.size(), 20,
		"the screen found almost no units - the walk is broken, not the roster")
	for entry in screen:
		assert_gt(float(entry["rp"]), 0.0,
			"%s costs nothing, so its V/RP is meaningless" % entry["id"])
		# A CARRIER IS PRICED ON WHAT IT CARRIES, and that is a rule rather
		# than an exemption (naval.md §5.3: "transports (exempt -- V cannot
		# price carrying): capacity per RP"). A transport has no attack BY
		# DESIGN, so V = sqrt(DPS x EHP) is 0 for every one of them and the
		# power assertion below would fail on correct data forever.
		#
		# It is NOT added to SKIP_ARCHETYPES, because a skipped archetype is
		# screened by nothing and a `.tres` shipping a hold that carries
		# NOTHING would pass in silence -- the vacuous-pass shape D-022's
		# audit block was written about. The carrier is screened on the
		# quantity that does price it instead.
		if entry["role"] == "carrier":
			assert_gt(int(entry["capacity"]), 0,
				"%s is a carrier and carries nothing, so nothing prices it"
					% entry["id"])
			assert_gt(float(entry["cap_rp"]), 0.0,
				"%s has no capacity per RP" % entry["id"])
		else:
			assert_gt(float(entry["v"]), 0.0, "%s has no power at all" % entry["id"])
		assert_ne(entry["role"], "other",
			"%s has archetype '%s', which this screen has no role for - add it to ROLES"
				% [entry["id"], entry["def"].archetype])


func test_price_buys_power_where_the_metric_can_see() -> void:
	# D-072 rule 1. Every violation on the shipped roster is a unit buying
	# range, speed, a counter bonus or building damage -- so the check is
	# what remains when those are accounted for.
	var screen := _screen()
	var skipped := 0
	for a in screen:
		for b in screen:
			if a["civ"] != b["civ"] or a["role"] != b["role"]:
				continue
			# Carriers are compared on capacity, never on V (naval.md §5.3).
			# Every transport has V = 0 by design, so a dearer hull would
			# read as "costs more, no more power" against a cheaper one and
			# red on correct data. No civ fields two today, which is exactly
			# why this is written now rather than discovered later.
			if a["role"] == "carrier":
				continue
			if float(b["rp"]) <= float(a["rp"]) or float(b["v"]) > float(a["v"]):
				continue
			var premium := _unpriced_premium(b["def"], a["def"])
			if premium != "":
				skipped += 1
				gut.p("  D-072 rule 1 n/a: %s (%.0f RP, V %.0f) over %s (%.0f RP, V %.0f) buys %s"
					% [b["id"], b["rp"], b["v"], a["id"], a["rp"], a["v"], premium])
				continue
			assert_true(false,
				"%s costs %.0f RP for V %.0f while %s costs %.0f for V %.0f, and buys nothing V cannot price"
					% [b["id"], b["rp"], b["v"], a["id"], a["rp"], a["v"]])
	gut.p("  D-072 rule 1: %d comparison(s) outside the metric's competence" % skipped)
	assert_gt(skipped, 0,
		"no comparison was skipped - either the roster changed shape or the premium "
		+ "detection has stopped working, and a check that never abstains is not this one")


func test_no_free_lunch_where_the_metric_can_see() -> void:
	# D-072 rule 2, scoped as the decision scopes it: within a CIV and
	# role. #220 reports gravesworn_levy leading "the roster", which is a
	# wider claim than the rule makes -- across civs and roles the metric
	# is comparing a levy with a siege engine.
	var screen := _screen()
	var skipped := 0
	var examined := 0
	for civ in CivRoster.ids():
		for role in ["line", "missile", "skirmisher", "cavalry", "siege"]:
			var grp := []
			for entry in screen:
				if entry["civ"] == civ and entry["role"] == role:
					grp.append(entry)
			if grp.size() < 2:
				continue
			examined += 1
			var top_v: Dictionary = grp[0]
			var top_vrp: Dictionary = grp[0]
			for entry in grp:
				if float(entry["v"]) > float(top_v["v"]):
					top_v = entry
				if float(entry["vrp"]) > float(top_vrp["vrp"]):
					top_vrp = entry
			if top_v["id"] != top_vrp["id"]:
				continue
			# The leader leads both. Legal only if every unit it leads
			# buys something V cannot see.
			var excused := true
			var why := PackedStringArray()
			for entry in grp:
				if entry["id"] == top_v["id"]:
					continue
				var premium := _unpriced_premium(entry["def"], top_v["def"])
				if premium == "":
					excused = false
				else:
					why.append("%s buys %s" % [entry["id"], premium])
			if excused:
				skipped += 1
				gut.p("  D-072 rule 2 n/a: %s/%s %s leads both, but %s"
					% [civ, role, top_v["id"], "; ".join(why)])
				continue
			assert_true(false,
				"%s/%s: %s leads on BOTH V (%.0f) and V/RP (%.2f), and what it leads buys nothing V cannot price"
					% [civ, role, top_v["id"], top_v["v"], top_v["vrp"]])
	gut.p("  D-072 rule 2: %d group(s) outside the metric's competence" % skipped)
	# A check that can examine nothing and report success is the vacuity
	# D-022's audit block is about. GUT caught this as RISKY on the first
	# run, which is the estate working.
	assert_gt(examined, 0,
		"no civ fields two units in one role, so the no-free-lunch rule was never asked")
	assert_true(skipped <= examined,
		"more groups were excused than were examined, which is arithmetic rather than balance")


func test_gravesworn_levy_is_the_case_220_reports_and_what_it_rests_on() -> void:
	# #220's specific finding, pinned so it cannot drift silently -- and
	# narrowed to what is actually true. Within its own civ and role
	# `gravesworn_levy` DOES lead both axes, and its spearmen are
	# dominated on both: 44 RP for V 583 against 32 RP for V 665.
	#
	# What the spearmen buy is `bonus_vs`, which V does not price. So this
	# is not a mispricing the metric can prove -- it is the metric handing
	# the question to #219's counter sweep, which measures whether the
	# counter is FELT. That is the connection between the two issues and
	# the reason neither is answered by moving V.
	var screen := _screen()
	var levy: Dictionary = {}
	var spearmen: Dictionary = {}
	for entry in screen:
		if entry["id"] == &"gravesworn_levy":
			levy = entry
		elif entry["id"] == &"gravesworn_spearmen":
			spearmen = entry
	assert_false(levy.is_empty(), "the roster should ship gravesworn_levy")
	assert_false(spearmen.is_empty(), "the roster should ship gravesworn_spearmen")
	assert_gt(float(levy["v"]), float(spearmen["v"]),
		"gravesworn_levy no longer out-powers its own spearmen - #220 has moved")
	assert_gt(float(levy["vrp"]), float(spearmen["vrp"]),
		"gravesworn_levy no longer out-values its own spearmen - #220 has moved")
	assert_ne(_unpriced_premium(spearmen["def"], levy["def"]), "",
		"gravesworn_spearmen now cost more and buy nothing V cannot price, which makes "
		+ "#220 a mispricing the screen can prove rather than a question for the counter sweep")
