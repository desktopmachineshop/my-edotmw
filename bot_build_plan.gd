class_name BotBuildPlan
extends RefCounted

## What a load-test bot builds and trains next (#123).
##
## `bot_patrol.gd`'s sibling: that one answers where a bot's scouts go,
## this one answers what it spends its wallet on. Both are all-static and
## pure for the same structural reason `formation.gd` is — there is nowhere
## to put per-bot state, so the decisions can be driven by a GUT test
## without an ENet host, a server, or five minutes of docker.
##
## It exists because `test-load`'s bots fielded no army at all. A bot only
## ever built a town centre; `buildings/town_centre.tres` `produces`
## gatherers only; and the haul loop claimed every crew. So `raid_pool` —
## the squads free to be sent anywhere — was empty on every tick of every
## match, and everything below `if raid_pool.is_empty(): return` was
## written, correct, called, and unreachable. The load test exercised the
## economy and the wire and never once put two armies in front of each
## other, while reporting a clean verdict (D-061's harder variant of the
## declared-and-unread family).
##
## Nothing here NAMES a building or a unit. Both are data ids: the roster
## grows a barracks or a stable by adding a `.tres`, and a load test that
## hardcoded "barracks" would stop finding the building the moment that
## happened. `ai_player.gd` discovers both the same way and for the same
## reason, and where the two agree the comment says so — the AI is the
## worked example, not a thing to copy blindly.


## How many hauling crews a bot keeps before it stops asking for more.
##
## A cap is needed at all because production is all-or-nothing against ONE
## `squad_cap` covering workers and soldiers alike (D-033), so a bot that
## trains gatherers forever fills the cap with them and never fields a
## soldier. That is not hypothetical: `ai_player.gd` records exactly this
## outcome from the ladder — "15 squads, 15 workers, 0 attacks" — and it
## reads as an AI too passive to attack rather than as an economy with no
## brakes.
const MAX_HAULING_CREWS := 8


## The building this bot most wants and does not have, or null.
##
## Anything its crews can raise that TRAINS something comes first, because
## that is what turns an economy into a player. Support buildings are not
## considered at all: a load test has no use for a storehouse, and every
## wall in the roster is `built_by` gatherers too — a bot that started
## raising walls would spend its wood on scenery.
static func wanted_building(owned_def_ids: Array, builder_archetype: StringName) -> BuildingDef:
	for def in BuildingSim.all_defs():
		if def.produces.is_empty():
			continue
		if not BuildingSim.can_build(def, builder_archetype):
			continue
		if owned_def_ids.has(String(def.id)):
			continue
		return def
	return null


## Whether `wallet` covers `def`, in the order `Economy.ResourceKind`
## declares.
##
## Checked before ordering rather than left to the server, because the cost
## is charged on ARRIVAL (`server.gd::_finish_build`), not when the order is
## accepted — so an unaffordable build order is a crew walking ten cells to
## be turned away, and the bot cannot tell that from a crew still walking.
static func can_afford(wallet: PackedInt32Array, def: BuildingDef) -> bool:
	if def == null:
		return false
	if wallet.size() < Economy.RESOURCE_COUNT:
		return false
	return wallet[Economy.ResourceKind.FOOD] >= def.cost_food \
		and wallet[Economy.ResourceKind.WOOD] >= def.cost_wood \
		and wallet[Economy.ResourceKind.GOLD] >= def.cost_gold \
		and wallet[Economy.ResourceKind.STONE] >= def.cost_stone


## What to ask THIS building for: the first archetype it produces that the
## civ actually fields, given how many hauling crews the bot already has.
##
## The wire carries an ARCHETYPE and the server resolves it against the
## player's civ (D-047), so this never names a unit and never names a civ —
## `tests/test_civs.gd` fails on either.
##
## Once the crew cap is reached, an archetype that carries is skipped
## rather than the whole building: a town centre that only makes gatherers
## then correctly offers nothing, and a barracks is unaffected.
##
## `civ` may be EMPTY, and for a load-test bot it always is — see `_resolve`.
static func archetype_for(building_def: BuildingDef, civ: StringName,
		hauling_crews: int) -> StringName:
	if building_def == null:
		return &""
	for archetype in building_def.produces:
		var def := _resolve(archetype, civ)
		if def == null:
			continue
		if def.carry_capacity > 0 and hauling_crews >= MAX_HAULING_CREWS:
			continue
		# A command figure is not a load-test instrument
		# (D-20260819-a-general-holds-the-line): the bots' brains read no
		# morale, so a general would be gold spent making the load LESS
		# representative. By FIELD, not by name — the same discipline
		# carry_capacity above uses.
		if def.is_general:
			continue
		return archetype
	return &""


## Where to put `def`, on the `attempt`-th try: outward from `home` through
## the nearest-first offset table (D-067 sorted it for exactly this), far
## enough out that it clears the town hall standing on the start.
##
## `no_build_radius` denies a disk around every building to anyone not
## allied with its owner, and the bot's own hall is at `home` — so a site
## inside that radius is refused, and asking for one is how a bot spends a
## whole run retrying its way nowhere. `claimed_radius` is the LARGEST such
## disk the bot has standing (see `claimed_radius_of`), not one building's,
## because clearing the hall and landing inside a tower would be the same
## refusal wearing a different name. The offset is bounded so the site
## stays near the base rather than wandering into somebody else's claim.
static func building_site(space: TorusSpace, home: Vector2i, def: BuildingDef,
		claimed_radius: int, attempt: int) -> Vector2i:
	var clear := 1 + maxi(claimed_radius, 0)
	if def != null:
		clear += def.footprint_radius
	var candidates: Array = []
	for offset in TorusSpace.disk_offsets(clear + 4):
		if TorusSpace.hex_length(offset) >= clear:
			candidates.append(offset)
	if candidates.is_empty():
		return home
	return space.normalize(home + candidates[attempt % candidates.size()])


## The largest `no_build_radius` among buildings this bot has standing —
## what `building_site` has to clear. Takes def ids rather than a sim,
## because the caller has a `ClientState` and this file may not know what
## one is.
static func claimed_radius_of(owned_def_ids: Array) -> int:
	var worst := 0
	for id in owned_def_ids:
		var def := BuildingSim.def_by_id(StringName(id))
		if def != null:
			worst = maxi(worst, def.no_build_radius)
	return worst


## The unit an archetype means, for a civ that may be unknown.
##
## A load-test bot never learns its own civ, and that is not an oversight
## to route around: `server.gd` broadcasts the lobby only while there IS a
## lobby, and `test-load` starts a match without one, so
## `ClientState.civ_of` answers "" for every bot in every run. Resolving
## strictly per civ therefore found only what was in the NEUTRAL pool —
## gatherers, at the time — and nothing else, which is exactly the shape
## the bug took: barracks standing, `military_peak=0`, and a town centre
## quietly training crews forever. As of
## D-20260823-the-opening-is-a-crew-and-a-general the neutral pool is
## empty, so a strict per-civ resolution would now find NOTHING for a bot
## and the fallback below carries every archetype rather than most of
## them.
##
## Falling back to any def with the archetype is correct rather than a
## fudge, because of what the wire carries. The client sends an ARCHETYPE
## and the SERVER resolves it against the player's civ (D-047) — a client
## "cannot name another civ's unit at all", as `_handle_order_produce` puts
## it. So the fallback is only being used to answer a LOCAL question ("is
## this a hauler, at the crew cap?"), which every civ's version of an
## archetype answers the same way. What goes on the wire is the archetype
## either way.
static func _resolve(archetype: StringName, civ: StringName) -> UnitDef:
	var def := UnitRoster.for_civ_archetype(civ, archetype)
	if def != null:
		return def
	# The any-civ fallback is for the CIV-LESS caller and nothing else.
	#
	# A load-test bot never learns its civ — `server.gd` broadcasts the
	# lobby only while there is one and `test-load` starts a match without
	# one — so it asks with `civ = &""` and needs SOME def to size its
	# request against. A caller that names a real civ is a different
	# question, and answering it with another civ's unit produces an order
	# the server refuses (D-047 resolves per civ), which reads as a bot
	# that will not train rather than as a bad lookup.
	#
	# Latent until the naval roster: this walks `produces` in order and
	# returns the first archetype that resolves, and every pre-naval
	# building's list STARTS with one every civ fields (`gatherers`,
	# `levy`), so the fallback was never reached with a real civ. A dock
	# offers `warship` first and two civs field a `warboat` instead — so
	# those two were handed a third civ's hull. (No civ is named here:
	# `tests/test_civs.gd` scans this file for civ ids, D-046 criterion 3.)
	# RANDOM is the ABSENCE of a choice, not a civ, so it is CIV-LESS for
	# this purpose. Missing that cost three of four load-test bots their
	# entire economy, and it was this narrowing that did it.
	#
	# `MatchState` seats a player with `civ = RANDOM`, and only
	# `_on_match_started` resolves that. On the `--lobby=0` path every
	# seat added AFTERWARDS still says "random" — which is every bot,
	# since they connect after the match begins. `for_civ_archetype`
	# answers null for "random", this returned null, `archetype_for`
	# returned &"", and those bots never sent a single produce order.
	#
	# NOTHING WAS REFUSED, BECAUSE NOTHING WAS ASKED. The server log
	# showed no production refusals at all, which is exactly what made it
	# read as an economy fault rather than a lookup one. Measured on the
	# merged tree with 4 bots: squads flatlined at 14 against `main`'s 42,
	# and the three affected bots ended with ONE squad each — the general
	# their opening crew had been spent founding a hall for.
	if civ != &"" and civ != CivRoster.RANDOM:
		return null
	for candidate in UnitRoster.load_all():
		if candidate.archetype == archetype:
			return candidate
	return null
