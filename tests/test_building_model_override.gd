extends GutTest

## Guards D-20260830-a-building-wears-a-civs-own-body: a building def may
## name a per-civ model override, resolved through BuildingDef.model_for —
## the shape #191's ratification chose for units, applied to a building.
##
## Three kinds of check, each bought elsewhere in this project's history:
## the RULE (override wins for its civ, everyone else keeps model_id), the
## CALLER (client.gd must resolve through model_for, or the feature is
## quietly absent — D-106's caller-exists rule), and the DATA (every model
## an override names must exist in the baked manifest, because a typo'd
## override does not fall back to the neutral authored model — it falls
## all the way to the primitive, on one civ's screen only, with nothing
## failing).


func test_the_override_wins_for_its_civ_and_nobody_else() -> void:
	var def := BuildingDef.new()
	def.model_id = &"town_centre"
	def.model_overrides = {&"emberdeep": &"emberdeep_town_centre"}
	assert_eq(def.model_for(&"emberdeep"), &"emberdeep_town_centre",
		"the civ named in the override wears its own body")
	assert_eq(def.model_for(&"stoneblood"), &"town_centre",
		"a civ with no override resolves exactly as before")
	assert_eq(def.model_for(&""), &"town_centre",
		"an unknown civ (a bot with no lobby, load-testing.md) gets the default")


func test_a_def_with_no_overrides_is_unchanged() -> void:
	var def := BuildingDef.new()
	def.model_id = &"barracks"
	assert_eq(def.model_for(&"emberdeep"), &"barracks")
	assert_eq(def.model_overrides.size(), 0,
		"the schema default is empty — no shipped def pays for this unasked")


func test_an_empty_override_value_falls_back_rather_than_blanking() -> void:
	var def := BuildingDef.new()
	def.model_id = &"storehouse"
	def.model_overrides = {&"emberdeep": &""}
	assert_eq(def.model_for(&"emberdeep"), &"storehouse",
		"an empty override must not strip the model to the primitive")


func test_the_shipped_overrides_resolve_for_emberdeep() -> void:
	var town := BuildingSim.def_by_id(&"town_centre")
	var store := BuildingSim.def_by_id(&"storehouse")
	assert_eq(town.model_for(&"emberdeep"), &"emberdeep_town_centre")
	assert_eq(store.model_for(&"emberdeep"), &"emberdeep_storehouse")
	# The other five civs keep the neutral bodies bit for bit.
	for civ in [&"stoneblood", &"gravesworn", &"thornwood", &"windmarch", &"gildedreach"]:
		assert_eq(town.model_for(civ), &"town_centre")
		assert_eq(store.model_for(civ), &"storehouse")


func test_every_override_names_a_baked_model() -> void:
	# A wrong name here costs one civ its building model with nothing
	# failing — the primitive fallback (D-064) is exactly what makes it
	# silent. The manifest is the record of what build-assets produced.
	var file := FileAccess.open("res://generated/manifest.json", FileAccess.READ)
	assert_not_null(file, "generated/manifest.json must exist")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	var baked: Dictionary = manifest.get("buildings", {})
	var overrides_seen := 0
	for def in BuildingSim.all_defs():
		for civ in def.model_overrides:
			var model: StringName = def.model_overrides[civ]
			overrides_seen += 1
			assert_true(baked.has(String(model)),
				"%s's override for %s names '%s', which build-assets never baked"
				% [def.id, civ, model])
	assert_gt(overrides_seen, 0,
		"the shipped data carries at least emberdeep's two overrides — zero "
		+ "means this test is asserting nothing (the vacuous-pass rule)")


func test_the_client_resolves_models_through_the_override() -> void:
	# The caller-exists scan (D-106): every rule above can hold while
	# client.gd still reads model_id raw, and then the feature is absent
	# with every other test green.
	var source := FileAccess.get_file_as_string("res://client.gd")
	assert_true(source.contains(".model_for("),
		"client.gd must resolve a building's mesh through model_for(civ)")
	# And the raw read it replaced must not come back at the mesh site:
	# 'mesh = UnitMesh.mesh_for(def.model_id)' was the old line.
	assert_false(source.contains("UnitMesh.mesh_for(def.model_id)"),
		"a second mesh site reading model_id raw would give one civ two answers")
