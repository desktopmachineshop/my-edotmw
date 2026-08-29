extends RefCounted
class_name Manual

## The in-game instructions manual (#305), menu -> Help.
##
## All-static and pure, like `controls_reference.gd`, `opening_brief.gd`
## and `hud_layout.gd`: what the manual SAYS is testable headless, and
## what the manual LOOKS LIKE needs a tree. Same D-061 split, same reason.
##
## ## The one architectural rule: a page is derived or it is stamped
##
## A hand-maintained manual is the status-doc-drift defect wearing a
## player-facing skin (#291), and this project has watched prose stop
## being true four times over — D-055's uncalled `damage()`, D-065's
## unreplicated field, D-106's unread `_explored`, #158's unread civ
## knobs. Every one had a comment or a decision entry describing what it
## did not do. A manual would go the same way inside two milestones.
##
## So every page in this file is one of two things, and there is no third:
##
## **DERIVED.** Rosters, stats, counters, costs, buildings, formations,
## and each civ's advantages and disadvantages are computed from the
## shipped `.tres` at the moment the player opens the page. There is no
## copy of the data for the data to disagree with, so the page cannot be
## stale — the same rule that keeps `TerrainGen.biome_color()` from
## letting the minimap and the 3D view drift apart. Change a unit's
## damage and the manual has already changed.
##
## **STAMPED.** Prose — what fog of war is, how morale works, what wins a
## match — cannot be derived. Those pages are `/manual/*.tres`
## (`ManualPageDef`), each naming the files it describes and carrying a
## hash over them. `tests/test_manual.gd` recomputes it, so a gameplay PR
## that moves a rule and forgets the page goes RED. Read that file's
## header for why the stamp is per-page rather than one manifest.
##
## ## Nothing here names a civ, and that is load-bearing
##
## An advantage is a DELTA against the rest of the shipped roster, never a
## sentence keyed to an id: "trains 15% faster than standard" is arithmetic
## over `CivDef.production_speed`, and "the only civ fielding siege" is a
## count over `/units`. D-046 criterion 3's test — no `.gd` may name a civ
## — is what keeps that honest, and it is why a seventh civ is a `.tres`
## and not an edit here.

const PROSE_DIR := "res://manual"

## Sub-heading marker inside a prose body. Deliberately the only markup:
## the renderer is a column of Labels, and a manual that needed a parser
## would be a manual whose fit nobody could check.
const HEADING := "## "

## Page kinds. A generated page's body is computed on open; a prose page's
## body is the `.tres`.
const GENERATED := "generated"
const PROSE := "prose"


# --- the power budget (D-072) -----------------------------------------
#
# D-072 derives cost from power rather than authoring both, so that every
# unit does not end up independently slightly too good. The formulas are
# its, verbatim; running them over the roster is how it found that
# `legion_heavy` cost 2.5x a militia for less DPS.
#
# D-072 is Provisional and was written against the historical roster,
# which is gone (fantasy civs, #191). The ARITHMETIC is what survives, and
# it is exactly what makes a "quality" or "quantity" claim in this manual
# a measurement rather than a slogan.
#
# What V does not price, stated here because the manual states it too: it
# ignores `attack_range`, `move_speed`, `vision_range`, `bonus_vs` and
# morale, so it systematically undervalues missile and scouting troops. A
# page that quoted V without saying so would be worse than one that did
# not quote it.


static func dps(def: UnitDef) -> float:
	if def == null or def.attack_interval <= 0.0:
		return 0.0
	return def.squad_size * def.damage / def.attack_interval


static func effective_health(def: UnitDef) -> float:
	return 0.0 if def == null else def.squad_size * def.health


## D-072's V: `sqrt(DPS x EHP)`, geometric so it stays roughly linear in
## squad size rather than quadratic.
static func power(def: UnitDef) -> float:
	return sqrt(dps(def) * effective_health(def))


## D-072's RP: `food + wood + 1.5 x (gold + stone)`.
static func resource_points(def: UnitDef) -> float:
	if def == null:
		return 0.0
	return def.cost_food + def.cost_wood + 1.5 * (def.cost_gold + def.cost_stone)


static func value_per_point(def: UnitDef) -> float:
	var rp := resource_points(def)
	return 0.0 if rp <= 0.0 else power(def) / rp


# --- what a unit is, asked of the data --------------------------------
#
# `carry_capacity > 0` IS the gatherer test, per UnitDef's own comment —
# there is no separate boolean to fall out of step with it. Every question
# below is asked the same way, so a unit added tomorrow answers correctly
# without this file learning its name.


static func is_gatherer(def: UnitDef) -> bool:
	return def != null and def.carry_capacity > 0


static func is_fighting(def: UnitDef) -> bool:
	return def != null and not is_gatherer(def) and not def.is_general


## Siege: a unit whose share of damage landing on a BUILDING is above the
## schema's conservative default. D-056 set that default to the safe end
## precisely so that raising it is a deliberate statement, which makes it
## exactly the right thing to read as "this breaks walls".
static func is_siege(def: UnitDef) -> bool:
	if def == null:
		return false
	return def.damage_vs_buildings > UnitDef.new().damage_vs_buildings


## Fearless: cannot rout, because morale clamps at 0 and every rout
## comparison is strict (`tests/test_fearless.gd` pins both).
static func is_fearless(def: UnitDef) -> bool:
	return def != null and def.rout_threshold <= 0.0 and def.morale_loss_per_casualty <= 0.0


# --- the pages ---------------------------------------------------------


## Every page, in reading order, generated and prose together.
##
## Adding a prose page is a `.tres` under `/manual`; adding a generated
## page is one entry here and one function. That the two interleave by
## `order` rather than being two lists is deliberate — the reading order
## a player wants alternates between "what is this" and "what are the
## numbers", and a manual with all the tables at the back is a reference
## rather than an introduction.
static func pages() -> Array:
	var out := []
	for entry in _generated_pages():
		out.append(entry)
	for def in prose_pages():
		out.append({
			"id": def.id,
			"title": def.title,
			"order": def.order,
			"summary": def.summary,
			"kind": PROSE,
		})
	out.sort_custom(_before)
	return out


## Every page id, in reading order. For error messages and for callers
## that want to name a page without opening it.
static func page_ids() -> Array:
	var out := []
	for entry in pages():
		out.append(String(entry["id"]))
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["order"]) != int(b["order"]):
		return int(a["order"]) < int(b["order"])
	# Ties break on id, so the contents list is stable whatever order the
	# filesystem enumerated /manual in — the same reason UnitRoster and
	# CivRoster sort.
	return String(a["id"]) < String(b["id"])


static func _generated_pages() -> Array:
	return [
		{"id": &"civilisations", "title": "The civilisations", "order": 30,
			"summary": "Every civ, and what the data says each is good and bad at.",
			"kind": GENERATED},
		{"id": &"troops", "title": "Troops", "order": 40,
			"summary": "Every unit every civ fields, with its stats and its price.",
			"kind": GENERATED},
		{"id": &"counters", "title": "Counters", "order": 50,
			"summary": "What beats what, from the bonus table in the unit data.",
			"kind": GENERATED},
		{"id": &"buildings", "title": "Buildings", "order": 60,
			"summary": "What each building costs, does, and can train.",
			"kind": GENERATED},
		{"id": &"formations", "title": "Formations", "order": 70,
			"summary": "The shapes a squad can take, and what each trades away.",
			"kind": GENERATED},
	]


## The hand-written pages, sorted by id so iteration is stable.
##
## Same loader shape as `CivRoster.load_all` on purpose: server, client
## and tests discover content one way, and there is one pattern to learn.
## Not cached — a manual page is opened by a human at human speed and is
## never on a tick path, so the caching D-043 forced on `UnitRoster` buys
## nothing here and would only be state a test has to reset.
static func prose_pages() -> Array:
	var out := []
	var dir := DirAccess.open(PROSE_DIR)
	if dir == null:
		return out
	var names := []
	for file_name in dir.get_files():
		var normalised := String(file_name).trim_suffix(".remap")
		if normalised.ends_with(".tres"):
			names.append(normalised)
	names.sort()
	for name in names:
		var def := load("%s/%s" % [PROSE_DIR, name]) as ManualPageDef
		if def == null:
			push_error("Manual: %s/%s did not load as a ManualPageDef" % [PROSE_DIR, name])
			continue
		var invalid := def.validate()
		if invalid != "":
			push_error("Manual: %s" % invalid)
			continue
		out.append(def)
	return out


static func prose_by_id(id: StringName) -> ManualPageDef:
	for def in prose_pages():
		if def.id == id:
			return def
	return null


## A page, ready to draw: `{title, summary, sections}`.
##
## A section is `{heading, kind, lines}` or `{heading, kind, columns,
## rows}` — `kind` is `"text"` or `"table"`, so the renderer has two cases
## and no parser. Everything a page needs to be laid out is decided here,
## where a test can read it, rather than in the drawing code, where only a
## picture can.
static func page(id: StringName) -> Dictionary:
	for entry in _generated_pages():
		if entry["id"] == id:
			var built: Dictionary = _generate(id)
			built["title"] = entry["title"]
			built["summary"] = entry["summary"]
			return built
	var def := prose_by_id(id)
	if def != null:
		return {
			"title": def.title,
			"summary": def.summary,
			"sections": parse_body(resolve_constants(def.body)),
		}
	return {"title": "", "summary": "", "sections": []}


static func _generate(id: StringName) -> Dictionary:
	match id:
		&"civilisations":
			return {"sections": civilisation_sections()}
		&"troops":
			return {"sections": troop_sections()}
		&"counters":
			return {"sections": counter_sections()}
		&"buildings":
			return {"sections": building_sections()}
		&"formations":
			return {"sections": formation_sections()}
	return {"sections": []}


## Split a prose body into sections. A line starting `## ` opens one;
## blank lines separate paragraphs within it.
static func parse_body(body: String) -> Array:
	var out := []
	var current := {"heading": "", "kind": "text", "lines": []}
	for raw in body.split("\n"):
		var line := String(raw)
		if line.begins_with(HEADING):
			if not (current["lines"] as Array).is_empty():
				out.append(current)
			current = {"heading": line.substr(HEADING.length()).strip_edges(),
				"kind": "text", "lines": []}
			continue
		(current["lines"] as Array).append(line)
	if not (current["lines"] as Array).is_empty():
		out.append(current)
	for section in out:
		section["lines"] = _flow(section["lines"])
	return out


## Turn authored lines into DISPLAY lines.
##
## A `.tres` body is wrapped at a readable width in the file, and the
## renderer wraps again at whatever width the window gives it — so the
## authored breaks land mid-sentence and the page comes out ragged. The
## first rendered frame is what showed it, which is the fourth time on
## this stack that a picture has caught something no assertion did.
##
## So consecutive lines FLOW into one paragraph and a blank line breaks
## it. The one exception is a line beginning `- `, which keeps its own
## line: a list of three fog states or four stances is a list, and
## flowing it into a paragraph would lose the thing that makes it
## readable. That is the whole markup — `## ` for a heading, `- ` for an
## item, a blank line for a break — and it stays small on purpose,
## because a manual that needed a parser would be a manual whose fit
## nobody could check.
static func _flow(lines: Array) -> Array:
	var out := []
	var buffer := ""
	for raw in lines:
		var line := String(raw).strip_edges()
		if line == "" or line.begins_with("- "):
			if buffer != "":
				out.append(buffer)
				buffer = ""
			out.append(line)
			continue
		buffer = line if buffer == "" else "%s %s" % [buffer, line]
	if buffer != "":
		out.append(buffer)
	# Blank lines at either end are invisible in the file and would draw
	# as empty rows against the heading above and the next section below.
	while not out.is_empty() and String(out[0]) == "":
		out.pop_front()
	while not out.is_empty() and String(out[-1]) == "":
		out.pop_back()
	return out


# --- generated: the civilisations --------------------------------------


static func civilisation_sections() -> Array:
	var out := []
	var civs := CivRoster.load_all()
	var roster := UnitRoster.load_all()
	out.append({"heading": "", "kind": "text", "lines": [
		("Every civ fields a SUBSET of the game's troop types and tunes them"
		+ " its own way, so the same kind of soldier is not the same soldier"
		+ " in two armies."),
		"",
		("Everything below is measured from the shipped unit and civ data"
		+ " when you open this page, and compared against the other civs."
		+ " It is what the game is, not what it was meant to be."),
	]})
	for civ in civs:
		var standing := CivStanding.measure(civ, civs, roster)
		var lines := []
		var pitch: String = CivIdentity.describe(civ).get("summary", "")
		if pitch != "":
			lines.append(pitch)
		var signature := CivIdentity.signature_name(civ)
		if signature != "":
			lines.append("Signature troops: %s." % signature)
		lines.append("")
		for text in standing["advantages"]:
			lines.append("+  %s" % text)
		for text in standing["disadvantages"]:
			lines.append("-  %s" % text)
		out.append({"heading": civ.display_name, "kind": "text", "lines": lines})
	return out


# --- generated: the troops ---------------------------------------------


static func troop_sections() -> Array:
	var out := []
	out.append({"heading": "", "kind": "text", "lines": [
		("A squad is what you command; the numbers below are per SOLDIER,"
		+ " except Men, which is how many the squad starts with."),
		"",
		("Power is the square root of (damage per second x total health) for"
		+ " the whole squad — one number for how much fight a squad is"
		+ " worth. It does NOT price reach, speed, sight, bonuses or morale,"
		+ " so it undervalues archers and scouts. Read it beside the other"
		+ " columns, not instead of them."),
	]})
	var columns := ["Troops", "Men", "Health", "Damage", "Reach", "Speed",
		"Cost", "Power"]
	for civ in CivRoster.load_all():
		var rows := []
		for def in UnitRoster.for_civ(civ.id):
			rows.append([
				def.display_name,
				str(def.squad_size),
				"%.0f" % def.health,
				"%.1f / %.1fs" % [def.damage, def.attack_interval],
				"%.1f" % def.attack_range,
				"%.1f" % def.move_speed,
				price(def),
				("-" if not is_fighting(def) else "%d" % int(round(power(def)))),
			])
		out.append({"heading": civ.display_name, "kind": "table",
			"columns": columns, "rows": rows})
	return out


## A unit's price, compactly, listing only the resources it actually
## costs. Derived from the four cost fields rather than a stored string,
## so a unit that starts costing stone says so with nothing edited here.
static func price(def: UnitDef) -> String:
	if def == null:
		return ""
	return _price_of(def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone)


static func building_price(def: BuildingDef) -> String:
	if def == null:
		return ""
	return _price_of(def.cost_food, def.cost_wood, def.cost_gold, def.cost_stone)


static func _price_of(food: int, wood: int, gold: int, stone: int) -> String:
	var parts := []
	if food > 0:
		parts.append("%df" % food)
	if wood > 0:
		parts.append("%dw" % wood)
	if gold > 0:
		parts.append("%dg" % gold)
	if stone > 0:
		parts.append("%ds" % stone)
	return "free" if parts.is_empty() else " ".join(parts)


# --- generated: counters -----------------------------------------------
#
# Read straight off `UnitDef.armour_class` and `UnitDef.bonus_vs`, which
# is where combat reads them (D-032). A missing entry means 1.0 — a unit
# with no bonuses is a generalist, never a special case — so a unit that
# appears in no row below is not broken. It is un-countered, and it does
# no countering.


static func counter_sections() -> Array:
	var out := []
	out.append({"heading": "", "kind": "text", "lines": [
		("Every troop type counts as infantry, cavalry or missile. Some"
		+ " troops hit one of those classes harder than the rest; that is"
		+ " the whole counter system, and it is the table below."),
		"",
		("Troops listed nowhere have no bonuses. That makes them"
		+ " generalists — never hard countered, and never getting the bonus"
		+ " themselves."),
	]})
	var rows := []
	for def in UnitRoster.load_all():
		if not is_fighting(def):
			continue
		var against := []
		for armour in def.bonus_vs:
			var multiplier := float(def.bonus_vs[armour])
			if multiplier == 1.0:
				continue
			against.append("%s x%.2f" % [String(armour), multiplier])
		if against.is_empty():
			continue
		against.sort()
		rows.append([def.display_name, def.armour_class, ", ".join(against)])
	out.append({"heading": "Who hits harder, and against what", "kind": "table",
		"columns": ["Troops", "Counts as", "Bonus against"], "rows": rows})

	# The other direction, which is the one a player actually asks: I am
	# holding these troops, what am I afraid of? Derived by inverting the
	# same table rather than written out, so the two can never disagree.
	var threatened := {}
	for def in UnitRoster.load_all():
		if not is_fighting(def):
			continue
		for armour in def.bonus_vs:
			if float(def.bonus_vs[armour]) <= 1.0:
				continue
			var key := String(armour)
			if not threatened.has(key):
				threatened[key] = []
			var names: Array = threatened[key]
			if not names.has(def.display_name):
				names.append(def.display_name)
	var classes := threatened.keys()
	classes.sort()
	var afraid := []
	for armour in classes:
		var names: Array = threatened[armour]
		names.sort()
		afraid.append([String(armour), ", ".join(names)])
	out.append({"heading": "And what each class should avoid", "kind": "table",
		"columns": ["If your troops count as", "Beware"], "rows": afraid})
	return out


# --- generated: buildings ----------------------------------------------


static func building_sections() -> Array:
	var out := []
	out.append({"heading": "", "kind": "text", "lines": [
		("Buildings are placed by a squad, which then walks over and builds"
		+ " them. Everything below comes from the building data."),
		"",
		("A building's train list is every troop type ANY civ can produce"
		+ " from it. Yours will be shorter: a civ fields a subset, and the"
		+ " Troops page says which."),
	]})
	var rows := []
	for def in BuildingSim.all_defs():
		rows.append([
			def.display_name,
			building_price(def),
			"%.0fs" % def.build_time,
			"%.0f" % def.max_health,
			building_role(def),
		])
	out.append({"heading": "", "kind": "table",
		"columns": ["Building", "Cost", "Build", "Health", "What it does"],
		"rows": rows})
	return out


## What a building is FOR, read off its own fields rather than its id.
##
## Same discipline as `opening_brief.gd`: the town centre is found by the
## rule it satisfies (`consumes_builder`), never by name, so a second
## founding building or a renamed one needs no edit here.
static func building_role(def: BuildingDef) -> String:
	if def == null:
		return ""
	var parts := []
	if def.consumes_builder:
		parts.append("founds a settlement, and spends the crew that builds it")
	if def.is_drop_off:
		parts.append("gatherers deliver here")
	if not def.produces.is_empty():
		var names := []
		for archetype in def.produces:
			names.append(CivStanding.readable_archetype(archetype))
		names.sort()
		parts.append("trains %s" % ", ".join(names))
	if def.damage > 0.0 and def.attack_range > 0.0:
		parts.append("shoots for %.0f every %.1fs, reach %.0f"
			% [def.damage, def.attack_interval, def.attack_range])
	if def.vision_range > 0.0:
		parts.append("sees %.0f" % def.vision_range)
	if def.no_build_radius > 0:
		parts.append("denies %d cells of ground to enemies" % def.no_build_radius)
	return "; ".join(parts) if not parts.is_empty() else "-"


# --- generated: formations ---------------------------------------------


static func formation_sections() -> Array:
	var out := []
	out.append({"heading": "", "kind": "text", "lines": [
		("A formation is a fighting style, not just a shape. What a squad"
		+ " stands in changes how much damage it takes from the front, the"
		+ " flank and the rear, how much it takes from arrows, and how fast"
		+ " it moves."),
		"",
		("A number under 1.00 is damage AVOIDED: 0.50 from the front means a"
		+ " frontal attack does half. Nothing here changes the damage a"
		+ " formation DEALS — only what it suffers, and how quickly it"
		+ " walks."),
	]})
	var rows := []
	for def in FormationRoster.load_all():
		rows.append([
			def.display_name,
			"%.2f" % def.taken_front,
			"%.2f" % def.taken_flank,
			"%.2f" % def.taken_rear,
			"%.2f" % def.missile_taken,
			"%.2f" % def.pace_scale,
			formation_users(def),
		])
	out.append({"heading": "", "kind": "table",
		"columns": ["Formation", "Front", "Flank", "Rear", "Arrows", "Pace",
			"Who may use it"],
		"rows": rows})
	return out


## Who can actually order this formation.
##
## Reachability is two conditions (D-20260819-a-formation-is-a-fighting-
## style): a formation is either OFFERED to everyone, or GRANTED to
## particular units through `UnitDef.formations`. The server checks
## exactly that pair, so reading both here is what makes the page a
## statement about what the player can DO rather than about what exists.
##
## A formation that is neither says so. That is not a hedge — the shipped
## data currently has two (#309), and a manual that quietly omitted them
## would be hiding the very fact that makes it useful.
static func formation_users(def: FormationDef) -> String:
	if def == null:
		return ""
	if def.offered:
		return "Any squad"
	var names := []
	for unit in UnitRoster.load_all():
		if unit.formations.has(def.id) and not names.has(unit.display_name):
			names.append(unit.display_name)
	if names.is_empty():
		return "Not granted to any troops"
	names.sort()
	return ", ".join(names)


# --- prose that quotes a number quotes the REAL one --------------------
#
# A prose page may write `{Combat.CHAIN_ROUT_MORALE_LOSS}` and get
# whatever `combat.gd` says today. Nothing else is substituted, and there
# is no expression language: this is a lookup into a script's constant
# map, exactly the technique `controls_reference.gd` uses to derive its
# build rows from `client.gd`'s own `BUILD_KEYS`.
#
# It exists because the alternative is a manual that hardcodes 12.0 beside
# a game that has moved on, and #305's whole premise is that the manual
# must not lie. The stamp guard would CATCH that drift; this makes the
# common case unable to drift at all, which is strictly better — a guard
# tells you to go and fix something, and this is already fixed.
#
# Deliberately NOT extended to `.tres` values. Those have generated pages,
# and a second way to quote a unit's damage is a second thing to keep in
# step (D-058/D-065's family). Script constants are the case with no
# other answer.

const CONSTANT_SOURCES := {
	"Combat": "res://combat.gd",
	"SquadSim": "res://squad_sim.gd",
	"Economy": "res://economy.gd",
}

## An unresolved token is left VISIBLE rather than blanked. A page reading
## "costs {Combat.GONE} morale" is obviously broken to anyone who opens
## it; a page reading "costs  morale" looks like prose. The test fails on
## it either way, but the failure should also be legible without the test.
static func resolve_constants(text: String) -> String:
	var out := text
	for owner in CONSTANT_SOURCES:
		var script := load(CONSTANT_SOURCES[owner]) as GDScript
		if script == null:
			continue
		var constants := script.get_script_constant_map()
		for name in constants:
			var token := "{%s.%s}" % [owner, name]
			if out.contains(token):
				out = out.replace(token, _readable_number(constants[name]))
	return out


## Numbers as a reader would write them: 12.0 is "12", 1.5 stays "1.5".
## Anything that is not a number is stringified, which is what makes an
## accidentally-substituted array look wrong rather than plausible.
static func _readable_number(value: Variant) -> String:
	if typeof(value) == TYPE_INT:
		return str(value)
	if typeof(value) == TYPE_FLOAT:
		var number := float(value)
		if is_equal_approx(number, round(number)):
			return "%d" % int(round(number))
		return String.num(number, 2).trim_suffix("0").trim_suffix(".")
	return str(value)


## Every `{Owner.NAME}` token in `text` that CONSTANT_SOURCES cannot
## resolve. The staleness test reads this: a constant that is renamed or
## deleted takes its manual page with it, and that has to be loud.
static func unresolved_tokens(text: String) -> Array:
	var out := []
	var from := 0
	while true:
		var open := text.find("{", from)
		if open < 0:
			break
		var close := text.find("}", open)
		if close < 0:
			break
		var token := text.substr(open, close - open + 1)
		from = close + 1
		if resolve_constants(token) == token:
			out.append(token)
	return out
