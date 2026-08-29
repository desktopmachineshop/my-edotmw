extends GutTest

## Guards #230 — a load-test bot must report the army it actually has,
## and a scenario's verdict must be scoped to what that scenario contains.
##
## The defect was a NUMBER that read zero when the truth was five:
##
##     BOT player=1 squads=5 military=5 ... military_peak=0
##
## `military=5` and `military_peak=0` in one line. #123 made
## `military_peak` a metric precisely so "there was nothing to send" and
## "there was something and it was never sent" could be told apart; on
## `scenarios/clash.tres` it reported the first when the second was true.
##
## And the run around it could not pass either: `clash` places no
## buildings and hands out no crew, so `_verdict_ok`'s buildings gate was
## unreachable — a **vacuous FAILURE**, the mirror of the vacuous passes
## D-022's audit block was written about. It fails identically every time,
## which is how the next person learns to ignore the result.
##
## `clash` is not a corner case: it is one of three shipped scenarios, it
## is the one `just scenarios` describes as being for combat, morale,
## routing and fog, and `docs/status/ai-opponent.md` says outright to pair
## AI profiles on it rather than on `siege`.

const HALL := &"town_centre"


func _scenario(id: StringName) -> ScenarioDef:
	var def := Scenario.by_id(id)
	assert_not_null(def, "scenarios/%s.tres must exist" % id)
	return def


## What `bot_client.gd::_expects_buildings` decides, over a ScenarioDef.
## Kept in step with it by `test_the_bot_asks_this_question_of_the_resource`
## below, which scans for the caller — the D-106 rule, and the only thing
## that can see the bot ignoring its own scenario.
func _expects_buildings(def: ScenarioDef) -> bool:
	if def == null:
		return true
	if not def.buildings.is_empty():
		return true
	var hall := BuildingSim.def_by_id(HALL)
	for entry in def.squads:
		if BuildingSim.can_build(hall, entry.archetype):
			return true
	return false


# --- the scenario decides what a verdict may ask for -------------------

func test_clash_places_nothing_that_could_ever_satisfy_a_buildings_gate() -> void:
	# The fact the whole issue rests on, asserted against the shipped
	# resource rather than quoted from it.
	var clash := _scenario(&"clash")
	assert_true(clash.buildings.is_empty(),
		"clash is two armies and nothing else — if it grows buildings, #230's premise is gone")
	var hall := BuildingSim.def_by_id(HALL)
	for entry in clash.squads:
		assert_false(BuildingSim.can_build(hall, entry.archetype),
			"clash hands out a %s, which CAN found a town hall — the gate is reachable after all"
				% entry.archetype)
	assert_false(_expects_buildings(clash),
		"a run of clash must not be asked for buildings it cannot produce")


func test_a_real_opening_is_still_asked_for_buildings() -> void:
	# The clause that keeps `test-load` measuring exactly what it did. A
	# run with no scenario at all plays the opening, and D-027 slice 4's
	# live proof — a town hall was founded and reached clients — must
	# still be a gate there.
	assert_true(_expects_buildings(null),
		"a run with no scenario is a real opening and must still gate on buildings")


func test_a_scenario_that_ships_buildings_is_still_asked_for_them() -> void:
	var found := false
	for def in Scenario.load_all():
		if def.buildings.is_empty():
			continue
		found = true
		assert_true(_expects_buildings(def),
			"scenario '%s' places buildings and must still be gated on them" % def.id)
	assert_true(found,
		"setup: no shipped scenario places a building, so this test proves nothing")


func test_a_scenario_with_a_crew_but_no_buildings_is_asked_for_them() -> void:
	# The case that separates "places none" from "can produce none", and
	# the reason the question is asked of the RESOURCE rather than of
	# `buildings.is_empty()` alone: a scenario that hands out a gatherer
	# crew and no hall is a legitimate opening variant, and its bots can
	# and should found.
	var synthetic := ScenarioDef.new()
	synthetic.id = &"synthetic"
	var crew := ScenarioSquad.new()
	crew.archetype = &"gatherers"
	crew.count = 1
	synthetic.squads = [crew]
	assert_true(_expects_buildings(synthetic),
		"a scenario whose crew can found a hall must still be gated on buildings")


func test_the_bot_asks_this_question_of_the_resource() -> void:
	# D-106's caller-exists rule, with its own caveat: every assertion
	# above would pass while `bot_client.gd` ignored the scenario entirely
	# and gated on buildings regardless.
	var handle := FileAccess.open("res://bot_client.gd", FileAccess.READ)
	assert_not_null(handle, "bot_client.gd could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_true(source.contains("func _expects_buildings()"),
		"bot_client.gd must decide for itself whether a run could have buildings")
	assert_true(source.contains("_expects_buildings() and _buildings_known()"),
		"the buildings gate must be scoped by it, or clash still cannot pass")
	assert_true(source.contains('Scenario.by_id(StringName(String(args.get("scenario"'),
		"the bot must be TOLD which scenario is being played, or it cannot scope anything")
	assert_true(source.contains("_expects_buildings() and _military_squads()"),
		"a scenario with no buildings must gate on the army it WAS given instead — "
		+ "dropping a gate and adding nothing is the relaxation this must not become")


func test_the_recipe_hands_the_scenario_to_the_bots() -> void:
	# And the other end of that plumbing. `test-scenario` has exported
	# EDOTMW_SCENARIO for the server since scenarios existed; the bots
	# never saw it.
	var handle := FileAccess.open("res://justfile", FileAccess.READ)
	assert_not_null(handle, "the justfile could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_true(source.contains('scenario="${EDOTMW_SCENARIO:-}"'),
		"run-bots must read the scenario the run is playing")
	assert_true(source.count('--scenario="$scenario"') >= 2,
		"both the docker and the native bot invocations must pass it")


# --- military_peak is not gated on the opening -------------------------

func test_military_peak_is_not_gated_on_having_found_a_crew() -> void:
	# The one-line half of #230. `_is_military` already excludes the
	# founding squad and handles -1 correctly on its own, because no squad
	# has id -1 — so the extra guard bought nothing and cost the entire
	# metric on any scenario with no crew to identify.
	var handle := FileAccess.open("res://bot_client.gd", FileAccess.READ)
	assert_not_null(handle, "bot_client.gd could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_false(source.contains("military_squads() if _founding_squad >= 0 else 0"),
		"military_peak is still gated on the founding squad, so a scenario with no crew "
		+ "reports an army of zero beside a line saying it has five")
	assert_true(source.contains("var fighting := military_squads()"),
		"military_peak must count the army the bot has")


func test_the_opening_guard_asks_whether_there_is_an_opening() -> void:
	# `_owns_a_building()` is the same question as "am I still trying to
	# found" only while every match starts from the opening. Under a
	# scenario it answers "no building" forever, so the bot never reached
	# the raid order or the patrol at all — raid_orders=0, scouts_peak=0,
	# patrol_legs=0, beside five military squads.
	var handle := FileAccess.open("res://bot_client.gd", FileAccess.READ)
	assert_not_null(handle, "bot_client.gd could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_true(source.contains("func _opening_pending()"),
		"the bot must be able to ask whether it still has an opening to complete")
	assert_false(source.contains("if not _owns_a_building():\n\t\t\t_found_town_hall()"),
		"the order path still gates the raid on owning a building rather than on founding")
	assert_true(source.contains("if _opening_pending():"),
		"both the order path and the patrol must gate on the opening, not on a proxy for it")

# --- the peak-knowledge gate is asked only where it can be answered ----

func test_clash_declares_that_it_cannot_prove_peak_fog_gating() -> void:
	# Measured, not asserted from taste: `test-scenario clash` reports
	# `known_squads_max` equal to the total at BOTH 2 bots (10 of 10) and
	# 4 bots (20 of 20). The comparison is about the peak, and these
	# armies converge, so somebody ends up having seen everything.
	var clash := _scenario(&"clash")
	assert_false(clash.proves_fog_gating,
		"clash's armies converge, so the peak-knowledge comparison cannot hold there")


func test_every_other_shipped_scenario_still_proves_it() -> void:
	# The clause that keeps this from becoming a way to switch a gate off.
	# `siege` is the fast loop's default and passes fog-squads today;
	# nothing else may quietly opt out.
	for def in Scenario.load_all():
		if def.id == &"clash":
			continue
		assert_true(def.proves_fog_gating,
			"scenario '%s' opted out of the peak fog gate — that needs a measurement, not a flag"
				% def.id)


func test_the_default_is_to_prove_it() -> void:
	# A new `.tres` written without thinking about this is gated, not
	# excused. The dangerous default is the permissive one.
	assert_true(ScenarioDef.new().proves_fog_gating,
		"a scenario must have to opt OUT of the fog gate, never into it")


func test_the_server_puts_it_on_the_scenario_marker() -> void:
	# Travels as a structured marker like every other cross-process fact
	# here, rather than the recipe re-reading the `.tres` — a second
	# reader of a resource is a second thing to keep in step.
	var handle := FileAccess.open("res://server.gd", FileAccess.READ)
	assert_not_null(handle, "server.gd could not be read")
	if handle == null:
		return
	assert_true(handle.get_as_text().contains("proves_fog_gating=%s"),
		"the SCENARIO marker must carry what the scenario can prove")


func test_the_recipe_announces_the_skip_rather_than_taking_it_quietly() -> void:
	# gate-check.sh's own header: "a comparison that silently skips is the
	# vacuous pass D-022's audit was written against". A skip that prints
	# its reason is a different thing from a check that was deleted.
	var handle := FileAccess.open("res://justfile", FileAccess.READ)
	assert_not_null(handle, "the justfile could not be read")
	if handle == null:
		return
	var source := handle.get_as_text()
	assert_true(source.contains('grep -q "proves_fog_gating=false" "$server_log"'),
		"test-scenario must consult what the scenario said it can prove")
	assert_true(source.contains("gate-check(fog-squads): SKIPPED"),
		"and must SAY when it skipped the comparison, with its reason")
	assert_true(source.contains('bash gate-check.sh fog-nodes "$bots_log" "$server_log"'),
		"fog-nodes must still run unconditionally — fog is asserted either way")
