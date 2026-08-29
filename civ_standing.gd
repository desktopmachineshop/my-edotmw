extends RefCounted
class_name CivStanding

## Where a civ stands against the rest of the shipped roster — MEASURED,
## not written down (#305).
##
## The manual has to tell a player each civ's "specific advantages and
## disadvantages". The tempting way to do that is a table of sentences
## keyed by civ id, and it is the wrong way twice over:
##
## - **It would be a lie within two milestones.** A balance PR moves a
##   number; the sentence that described it stays. That is exactly the
##   drift #305 exists to prevent, and this project has watched prose stop
##   being true four times already (D-055, D-065, D-106, #158).
## - **No `.gd` file may name a civ** (D-046 criterion 3, with a test).
##   Six sentences keyed by id would make a seventh civ a code change,
##   which is the thing D-047 was built to prevent.
##
## So every claim here is a COMPARISON against the other shipped civs,
## computed from the `.tres` when the page is opened. "Trains 15% faster"
## is arithmetic on `CivDef.production_speed`; "the only civ that fields
## siege" is a count over `/units`. Change the data and the claim changes
## with it; add a civ and its entry writes itself.
##
## All-static and pure, and `measure()` takes its whole world as
## arguments, so a test can hand it three synthetic civs and check the
## arithmetic rather than asserting against whatever ships today.
## `for_civ()` is the one-line convenience that reads the real rosters.
##
## ## What a claim has to clear
##
## A margin, not "differs at all". Two civs whose median troop speed
## differs by 1% are the same civ for this purpose, and a page that said
## otherwise would train its reader to ignore it.
const MARGIN := 0.08

## A claim's side.
const ADVANTAGE := "advantage"
const DISADVANTAGE := "disadvantage"


static func _median(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var n := sorted.size()
	if n % 2 == 1:
		return float(sorted[n / 2])
	return 0.5 * (float(sorted[n / 2 - 1]) + float(sorted[n / 2]))


static func _percent(ratio: float) -> String:
	return "%d%%" % int(round(abs(ratio - 1.0) * 100.0))


## The units `civ` fields, out of a roster of every civ's units.
##
## `def.civ == id` plus neutral, mirroring `UnitRoster._available_to` —
## the same rule, because a manual that disagreed with the roster about
## who fields what would be worse than no manual.
static func fielded(civ_id: StringName, roster: Array) -> Array:
	var out := []
	for def in roster:
		if def != null and (def.civ == civ_id or def.civ == &"neutral"):
			out.append(def)
	return out


static func fighting(defs: Array) -> Array:
	var out := []
	for def in defs:
		if Manual.is_fighting(def):
			out.append(def)
	return out


static func archetypes(defs: Array) -> Array:
	var out := []
	for def in defs:
		if not out.has(def.archetype):
			out.append(def.archetype)
	out.sort()
	return out


## `{advantages: Array[String], disadvantages: Array[String]}` for `civ`,
## measured against `peers` (every civ, this one included) over `roster`
## (every civ's units).
##
## Order is deliberate rather than alphabetical: the knobs first, because
## they are the civ's declared identity; then what it fields, because that
## is what a player picks it for; then how its troops measure, which is
## the part a balance change moves most often.
static func measure(civ: CivDef, peers: Array, roster: Array) -> Dictionary:
	var advantages := []
	var disadvantages := []
	if civ == null:
		return {"advantages": advantages, "disadvantages": disadvantages}

	var claims := []
	claims.append_array(_knob_claims(civ))
	claims.append_array(_opening_claims(civ, peers))
	claims.append_array(_roster_claims(civ, peers, roster))
	claims.append_array(_troop_claims(civ, roster))

	for claim in claims:
		if claim["side"] == ADVANTAGE:
			advantages.append(String(claim["text"]))
		else:
			disadvantages.append(String(claim["text"]))
	return {"advantages": advantages, "disadvantages": disadvantages}


static func for_civ(civ_id: StringName) -> Dictionary:
	return measure(CivRoster.by_id(civ_id), CivRoster.load_all(), UnitRoster.load_all())


# --- the declared knobs (D-047, wired up by #158) ----------------------
#
# Compared against the SCHEMA DEFAULT rather than against the other civs,
# because these three have one: `CivDef.new()` is what an unknown civ
# resolves to, and `CivRoster.effects_of` returns exactly that. So 1.0 IS
# "standard" in the game's own terms, and there is nowhere for a second
# definition of standard to live.


static func _knob_claims(civ: CivDef) -> Array:
	var neutral := CivDef.new()
	var out := []

	if civ.squad_cap_bonus > neutral.squad_cap_bonus:
		out.append({"side": ADVANTAGE, "text":
			"Fields %d squads more than the map's cap allows anyone else."
			% civ.squad_cap_bonus})
	elif civ.squad_cap_bonus < neutral.squad_cap_bonus:
		out.append({"side": DISADVANTAGE, "text":
			"Fields %d squads fewer than the map's cap." % -civ.squad_cap_bonus})

	if civ.production_speed > neutral.production_speed:
		out.append({"side": ADVANTAGE, "text":
			"Trains %s faster than standard." % _percent(civ.production_speed)})
	elif civ.production_speed < neutral.production_speed:
		out.append({"side": DISADVANTAGE, "text":
			"Trains %s slower than standard." % _percent(civ.production_speed)})

	if civ.gather_speed > neutral.gather_speed:
		out.append({"side": ADVANTAGE, "text":
			"Gathers %s faster than standard." % _percent(civ.gather_speed)})
	elif civ.gather_speed < neutral.gather_speed:
		out.append({"side": DISADVANTAGE, "text":
			"Gathers %s slower than standard." % _percent(civ.gather_speed)})
	return out


# --- the opening bank --------------------------------------------------
#
# Priced in D-072's RP, so a civ opening on stone is comparable with one
# opening on wood. Compared against the MEDIAN of the other civs, because
# there is no schema default worth anything here — the numbers exist to
# differ.


static func opening_points(civ: CivDef) -> float:
	if civ == null:
		return 0.0
	return (civ.starting_food + civ.starting_wood
		+ 1.5 * (civ.starting_gold + civ.starting_stone))


static func _opening_claims(civ: CivDef, peers: Array) -> Array:
	var others := []
	for peer in peers:
		if peer != null and peer.id != civ.id:
			others.append(opening_points(peer))
	if others.size() < 2:
		return []
	var typical := _median(others)
	if typical <= 0.0:
		return []
	var ratio := opening_points(civ) / typical
	if ratio >= 1.0 + MARGIN:
		return [{"side": ADVANTAGE, "text":
			"Opens with %s more in the bank than most." % _percent(ratio)}]
	if ratio <= 1.0 - MARGIN:
		return [{"side": DISADVANTAGE, "text":
			"Opens with %s less in the bank than most." % _percent(ratio)}]
	return []


# --- what it fields ----------------------------------------------------


static func _roster_claims(civ: CivDef, peers: Array, roster: Array) -> Array:
	var out := []
	var mine := archetypes(fighting(fielded(civ.id, roster)))

	# How many civs field each archetype, so "only" and "everyone else"
	# are counts rather than judgements.
	var fielded_by := {}
	var breadths := []
	for peer in peers:
		if peer == null:
			continue
		var theirs := archetypes(fighting(fielded(peer.id, roster)))
		if peer.id != civ.id:
			breadths.append(float(theirs.size()))
		for archetype in theirs:
			fielded_by[archetype] = int(fielded_by.get(archetype, 0)) + 1

	var exclusive := []
	for archetype in mine:
		if int(fielded_by.get(archetype, 0)) == 1:
			exclusive.append(readable_archetype(archetype))
	if not exclusive.is_empty():
		out.append({"side": ADVANTAGE, "text":
			"The only civ that fields %s." % _list(exclusive)})

	# An archetype MOST other civs field and this one does not. A strict
	# majority, so "everyone else has it" is true rather than nearly true.
	var civ_count := peers.size()
	var missing := []
	for archetype in fielded_by:
		if mine.has(archetype):
			continue
		if int(fielded_by[archetype]) * 2 > civ_count:
			missing.append(readable_archetype(archetype))
	if not missing.is_empty():
		missing.sort()
		out.append({"side": DISADVANTAGE, "text":
			"Fields no %s, which most civs do." % _list(missing)})

	if breadths.size() >= 2:
		var typical := _median(breadths)
		if typical > 0.0:
			var ratio := float(mine.size()) / typical
			if ratio >= 1.0 + MARGIN:
				out.append({"side": ADVANTAGE, "text":
					"A wide roster — %d kinds of troop against a usual %d."
					% [mine.size(), int(round(typical))]})
			elif ratio <= 1.0 - MARGIN:
				out.append({"side": DISADVANTAGE, "text":
					"A narrow roster — %d kinds of troop against a usual %d."
					% [mine.size(), int(round(typical))]})
	return out


# --- how its troops measure -------------------------------------------
#
# Against the median of EVERY fighting unit in the game rather than
# against the other civs' medians, because the question a player is
# asking is "are these troops fast", not "is this civ faster than the
# median civ". The two differ whenever one civ fields many more units
# than another.


static func _troop_claims(civ: CivDef, roster: Array) -> Array:
	var out := []
	var mine := fighting(fielded(civ.id, roster))
	var all := fighting(roster)
	if mine.is_empty() or all.size() < 4:
		return out

	# Fearless is not a comparison — it is a rule (`tests/test_fearless.gd`).
	# Reported when it holds for EVERY fighting unit, because "some of its
	# troops never rout" is a fact about a unit, not about a civ.
	var fearless := true
	for def in mine:
		if not Manual.is_fearless(def):
			fearless = false
	if fearless:
		out.append({"side": ADVANTAGE, "text":
			"Its troops never rout — no morale, and nothing to break."})

	# D-072's two axes, which are the whole quality-versus-quantity
	# question expressed as arithmetic: V is what a squad is worth in a
	# fight, V/RP is what it is worth per resource spent.
	var power_ratio := _ratio(mine, all, Manual.power)
	var value_ratio := _ratio(mine, all, Manual.value_per_point)
	if power_ratio >= 1.0 + MARGIN and value_ratio <= 1.0 - MARGIN:
		out.append({"side": ADVANTAGE, "text":
			("Quality: its squads are worth %s more in a fight than the "
			+ "average, one for one.") % _percent(power_ratio)})
		out.append({"side": DISADVANTAGE, "text":
			"And cost %s more per point of that power." % _percent(value_ratio)})
	elif value_ratio >= 1.0 + MARGIN and power_ratio <= 1.0 - MARGIN:
		out.append({"side": ADVANTAGE, "text":
			("Quantity: %s more fighting power per resource spent than the "
			+ "average.") % _percent(value_ratio)})
		out.append({"side": DISADVANTAGE, "text":
			"But each squad is %s weaker on its own." % _percent(power_ratio)})
	elif power_ratio >= 1.0 + MARGIN:
		out.append({"side": ADVANTAGE, "text":
			"Strong squads — %s above the average in a straight fight."
			% _percent(power_ratio)})
	elif power_ratio <= 1.0 - MARGIN:
		out.append({"side": DISADVANTAGE, "text":
			"Weak squads — %s below the average in a straight fight."
			% _percent(power_ratio)})

	var speed_ratio := _ratio(mine, all, func(d): return d.move_speed)
	if speed_ratio >= 1.0 + MARGIN:
		out.append({"side": ADVANTAGE, "text":
			"Fast — %s quicker across the map than the average troop."
			% _percent(speed_ratio)})
	elif speed_ratio <= 1.0 - MARGIN:
		out.append({"side": DISADVANTAGE, "text":
			"Slow — %s slower across the map than the average troop."
			% _percent(speed_ratio)})

	var reach_ratio := _ratio(mine, all, func(d): return d.attack_range)
	if reach_ratio >= 1.0 + MARGIN:
		out.append({"side": ADVANTAGE, "text":
			"Outranges most armies — %s more reach than the average troop."
			% _percent(reach_ratio)})
	elif reach_ratio <= 1.0 - MARGIN:
		out.append({"side": DISADVANTAGE, "text":
			"Short reach — %s less than the average troop, so it has to close."
			% _percent(reach_ratio)})

	var siege := []
	for def in mine:
		if Manual.is_siege(def):
			siege.append(def.display_name)
	var anyone := false
	for def in all:
		if Manual.is_siege(def) and not mine.has(def):
			anyone = true
	if not siege.is_empty():
		siege.sort()
		out.append({"side": ADVANTAGE, "text":
			"Brings buildings down: %s hit walls far harder than troops do."
			% _list(siege)})
	elif anyone:
		out.append({"side": DISADVANTAGE, "text":
			"No siege troops, so taking a defended building means numbers."})
	return out


## Median of `of(def)` over `mine`, divided by the same over `all`.
## 0 when either side has nothing to measure, which every caller reads as
## "no claim" — the margin test cannot be passed by 0.
static func _ratio(mine: Array, all: Array, of: Callable) -> float:
	var ours := []
	for def in mine:
		ours.append(float(of.call(def)))
	var theirs := []
	for def in all:
		theirs.append(float(of.call(def)))
	var typical := _median(theirs)
	if typical <= 0.0:
		return 0.0
	return _median(ours) / typical


# --- words -------------------------------------------------------------


## An archetype id as a player would read it. Ids are lowercase with
## underscores by convention and nothing enforces it, so this only
## reshapes what it is given rather than looking anything up — a new
## archetype needs no entry anywhere.
static func readable_archetype(archetype: StringName) -> String:
	return String(archetype).replace("_", " ")


static func _list(items: Array) -> String:
	if items.is_empty():
		return ""
	if items.size() == 1:
		return String(items[0])
	var head := []
	for i in range(items.size() - 1):
		head.append(String(items[i]))
	return "%s and %s" % [", ".join(head), String(items[-1])]
