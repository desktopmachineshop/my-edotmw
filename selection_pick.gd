class_name SelectionPick
extends RefCounted

## Which thing a click selected, given every candidate's screen geometry.
##
## All-static and pure, for the reason `render_cull.gd` is: the client
## cannot be tested headless (D-014), but the half with the interesting
## failure mode — ranking a forty-man line against the town centre it is
## standing on — is plain arithmetic and needs no GPU to be wrong.
##
## ## The bug this replaces
##
## Squads and buildings were ranked on two different scales that were then
## compared to each other. A squad scored `distance - allowance`, which is
## NEGATIVE when the click lands inside its footprint and grows more
## negative the bigger the formation. A building scored raw `distance`,
## always positive. So `if distance < best_distance` could not be true for
## a building once any squad had claimed the click: a town centre 5 px from
## the cursor lost to a militia line scoring -60.
##
## The visible consequence was that a building became unselectable exactly
## when it was most covered in units — which is exactly when a player wants
## it, because that is what a base under attack looks like. Reported as
## selecting a building through lots of units being hard.
##
## ## Two questions, and they want different answers
##
## **Which of these squads did I click?** is answered by distance
## NORMALISED by the candidate's own allowance — 0.0 dead centre, 1.0 at
## the edge, above 1.0 a miss. A small squad clicked squarely should beat a
## huge one whose edge the cursor merely grazed, and only a scale-free
## metric says so.
##
## **A squad or the building?** is answered by raw distance to centre,
## because normalising re-creates the original bug in a milder form: a
## formation filling the screen scores near zero almost everywhere, so it
## would still swallow the town centre standing in the middle of it. Which
## centre the cursor is actually nearer does not care how big either thing
## is, and it is also what a player means — you aim at a thing, not at a
## proportion of it.
##
## The footprint stays the GATE in both cases: nothing wins a click that
## landed outside it.
##
## Sizes come from the caller, already projected, so this file never
## touches a Camera3D and every case below is expressible as numbers.

## How much a building's distance is discounted when it is up against a
## squad.
##
## Soldiers are drawn as tall meshes standing around and in front of a
## structure, so the pixels directly over a town centre frequently belong
## to somebody's militia. Without a bias the two are a coin toss decided by
## sub-pixel projection, which reads as the click "sometimes" working.
## Below 1.0 = the building wins a genuine tie; well above 0.5 so that a
## squad clicked clearly nearer its own centre still wins.
const BUILDING_PREFERENCE := 0.75

## Smallest a building's clickable radius may get, in pixels. Zoomed out, a
## town centre is a few pixels across and would otherwise need pixel-exact
## aim. Squads get the same treatment from the caller.
const MIN_BUILDING_ALLOWANCE_PX := 22.0


## A candidate's score: 0.0 dead centre, 1.0 at the edge, INF for a miss.
##
## INF rather than a large number so that no accumulation of near-misses
## can ever beat a real hit, and so a caller can compare scores without
## also having to re-test eligibility.
static func score(distance: float, allowance: float) -> float:
	if allowance <= 0.0 or distance > allowance:
		return INF
	return distance / allowance


## Pick a winner from squad and building candidates.
##
## Each candidate is `{"id": int, "distance": float, "allowance": float}`,
## in screen pixels. Returns `{"squad": int, "building": int}` with -1 for
## "nothing", and never both set — selecting a building clears the squad
## selection, so the caller needs one answer rather than two.
static func choose(squads: Array, buildings: Array) -> Dictionary:
	var best_squad := -1
	var best_squad_score := INF
	var best_squad_distance := INF
	for candidate in squads:
		var distance := float(candidate["distance"])
		var s := score(distance, float(candidate["allowance"]))
		if s < best_squad_score:
			best_squad_score = s
			best_squad_distance = distance
			best_squad = int(candidate["id"])

	var best_building := -1
	var best_building_score := INF
	var best_building_distance := INF
	for candidate in buildings:
		var distance := float(candidate["distance"])
		var s := score(distance,
			maxf(float(candidate["allowance"]), MIN_BUILDING_ALLOWANCE_PX))
		if s < best_building_score:
			best_building_score = s
			best_building_distance = distance
			best_building = int(candidate["id"])

	# Across the two kinds, raw distance decides — see the header. The
	# eligibility gate has already been applied by `score`, so a building
	# here is one the click genuinely landed on.
	if best_building >= 0 \
			and best_building_distance * BUILDING_PREFERENCE <= best_squad_distance:
		return {"squad": -1, "building": best_building}
	return {"squad": best_squad, "building": -1}
