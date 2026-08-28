extends GutTest

## Guards the render benchmark's attribution knobs (#229,
## D-20260828-every-microsecond-of-a-frame-has-a-phase).
##
## `bench_render.gd` can now turn off the soldier clamp, the ground
## sampler and the extra lattice copies, and can generate a map of any
## size — because "the frame tripled and four things changed" is not an
## attribution and the only way to separate the four is to switch each
## off. Every one of them therefore has to DEFAULT to what the client
## ships, or a run that names none of them silently measures a client
## nobody plays and every historical number stops being comparable.
##
## That is the same rule `--ai-profiles` follows (an absent profile list
## leaves `test-load` and the ladder measuring what they measured
## yesterday), and it is the rule `just quick-test SANDBOX=1` broke by
## accident: a knob whose default is not the shipped behaviour turns every
## measurement into a question about which invocation was used.
##
## Text, not behaviour: the benchmark needs a GPU (D-014), so what is
## checkable headless is that the defaults are what they claim.

const BENCH := "res://bench_render.gd"

const KNOBS := {
	"clamp": "1",     # the #97 soldier passability clamp
	"sampler": "1",   # the terrain height sample per man
	"copies": "1",    # every visible lattice copy (D-20260818)
}


func _source(path: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	assert_ne(text, "", "%s is readable" % path)
	return text


func test_every_knob_defaults_to_the_shipping_client() -> void:
	var text := _source(BENCH)
	for knob in KNOBS:
		var wanted := 'args.get("%s", %s)' % [knob, KNOBS[knob]]
		assert_true(text.contains(wanted),
			("--%s must default to the shipped behaviour (%s), or a bare "
			+ "`just bench-render` measures a client nobody plays") % [knob, wanted])


func test_the_map_is_the_shipped_one_unless_asked() -> void:
	var text := _source(BENCH)
	assert_true(text.contains('args.get("cells_wide", 0)')
		and text.contains('args.get("cells_high", 0)'),
		"a map size override defaults to OFF")
	assert_true(text.contains('load("res://maps/default.tres")'),
		"and the benchmark still loads the shipped map")
	# Never mutated in place: `maps/default.tres` is what every other
	# recipe loads, and a benchmark that edited it would corrupt them all.
	assert_true(text.contains("_config.duplicate()"),
		"an override duplicates the MapConfig rather than editing it")


func test_the_recipe_passes_nothing_by_default() -> void:
	# The other half: the knobs could default correctly and the recipe
	# could still hand one in. `just` takes arguments POSITIONALLY
	# (D-20260817-recipe-args-are-positional), so ARGS has to be LAST as
	# well as empty — anything before it would shift COUNTS, FRAMES or
	# HEIGHT and quietly measure something else.
	# #339 added HOST/PRESET/HULLS. They go BEFORE ARGS, which keeps this
	# rule intact rather than bending it: ARGS is still last, still empty,
	# and COUNTS/FRAMES/HEIGHT still hold slots 1-3. A new parameter added
	# after ARGS would be the actual violation, because ARGS is the
	# free-form passthrough and anything past it can never be reached.
	var justfile := _source("res://justfile")
	assert_true(justfile.contains(
		'bench-render COUNTS="0,100,250,500,1000" FRAMES="120" HEIGHT="40" '
		+ 'HOST="0" PRESET="" HULLS="0" ARGS="":'),
		"bench-render takes ARGS last and empty by default")


func test_the_breakdown_reports_a_residual() -> void:
	# A breakdown whose parts do not add up to the whole can hide the
	# thing being looked for — the rule
	# D-20260818-every-microsecond-of-a-tick-has-a-phase bought on the
	# server's tick, applied to the frame.
	var text := _source(BENCH)
	assert_true(text.contains("other=%.2f"),
		"the phase line prints the unclaimed remainder")
	assert_true(text.contains("cpu_mean - cull - derive - upload"),
		"and computes it rather than assuming the phases are exhaustive")


func test_the_frame_says_how_many_men_it_actually_derived() -> void:
	# `soldiers` in the CSV is the ARMY's strength; the frame derives far
	# fewer after LOD (15,756 against 4,385 when this was written).
	# Quoting a frame time against the first is how a per-soldier cost
	# gets quoted several times too cheap — the same trap as a us/squad
	# figure with no squad count.
	var text := _source(BENCH)
	assert_true(text.contains("drawn=%.0f soldiers/frame"),
		"the phase line carries the drawn-soldier count")
	assert_true(text.contains("keys_mean"),
		"and the keyframe census, which is what settled whether the "
		+ "curve scan was worth bisecting")
