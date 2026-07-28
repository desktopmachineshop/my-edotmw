extends GutTest

## M0 smoke test: proves `just test-unit` / GUT wiring actually runs
## headless, end to end. Real coverage (wrap-aware hex math per D-008,
## etc.) starts in M1.


func test_gut_runs() -> void:
	assert_true(true, "GUT harness executed this test")


func test_unit_def_defaults() -> void:
	var def := UnitDef.new()
	assert_eq(def.squad_size, 40, "UnitDef.squad_size default should match D-018's ~40 soldiers/squad")
	assert_eq(def.mesh_primitive, "capsule", "UnitDef.mesh_primitive should default to capsule (D-011)")
