extends SceneTree

## Re-stamps every prose page of the manual against the sources it names
## (#305). `just build-manual`.
##
## The manual's generated half — rosters, stats, counters, buildings,
## formations — needs no build step at all: it is derived from the shipped
## `.tres` when a player opens the page, so there is nothing to rebuild
## and nothing that can be stale. This tool exists only for the PROSE,
## which cannot be derived and therefore can.
##
## The loop it closes:
##
##   1. you change a gameplay rule;
##   2. `just test-unit` goes red, naming the manual pages that describe
##      it and what changed under them;
##   3. you READ those pages and fix the ones that have stopped being
##      true;
##   4. `just build-manual` renews their stamps;
##   5. green.
##
## Step 3 is the whole point and the only step a machine cannot do. This
## tool is deliberately dumb — it renews stamps and asks nothing — which
## means running it without reading is possible. That is a property of
## every guard of this shape, including `just build-assets`; what stops
## it being pointless is that the red test names the page, so the person
## re-stamping has been shown exactly what to look at.
##
## Run with `--verify` it changes nothing and reports, which is what a
## human wants before deciding whether they have prose to write.


func _init() -> void:
	var verify := false
	for argument in OS.get_cmdline_user_args():
		if String(argument) == "--verify":
			verify = true

	var pages := Manual.prose_pages()
	if pages.is_empty():
		push_error("manual-stamp: no prose pages under %s" % Manual.PROSE_DIR)
		quit(1)
		return

	var stale := 0
	var written := 0
	var broken := 0
	for def in pages:
		var missing: Array = def.missing_sources()
		if not missing.is_empty():
			broken += 1
			print("manual-stamp: %s names sources that do not exist: %s"
				% [def.id, ", ".join(missing)])
		var expected: String = def.expected_stamp()
		if def.stamp == expected:
			continue
		stale += 1
		var was: String = "unstamped" if def.stamp == "" else def.stamp.substr(0, 12)
		print("manual-stamp: %s is %s, wants %s"
			% [def.id, was, expected.substr(0, 12)])
		if verify:
			continue
		def.stamp = expected
		# `resource_path` is where it was LOADED from, which is the only
		# thing that cannot be wrong. Deriving the filename from the id
		# was the first version and it silently missed every page whose
		# file is not named after its id — `first-minutes` lives in
		# `first_minutes.tres`, and a `.tres` may legitimately be called
		# anything. It fell through to a fallback and so still worked,
		# which is the worst kind of near-miss: correct today, silently
		# wrong the day the fallback is tidied away.
		var path: String = def.resource_path
		if path == "":
			push_error("manual-stamp: %s has no resource path" % def.id)
			quit(1)
			return
		var error := ResourceSaver.save(def, path)
		if error != OK:
			push_error("manual-stamp: could not write %s (%d)" % [path, error])
			quit(1)
			return
		written += 1

	# Tokens are checked HERE as well as in the test, because this is the
	# tool somebody runs while writing a page and the test is the thing
	# that runs later. `{Combat.TYPO}` renders visibly wrong in the game
	# and is invisible in the .tres, so the moment to catch it is now.
	var bad_tokens := 0
	for def in pages:
		for token in Manual.unresolved_tokens(def.body):
			bad_tokens += 1
			print("manual-stamp: %s writes %s, which resolves to nothing"
				% [def.id, token])

	if verify:
		print("manual-stamp: %d page(s), %d stale, %d with missing sources, "
			% [pages.size(), stale, broken]
			+ "%d bad token(s)" % bad_tokens)
		quit(1 if (stale > 0 or broken > 0 or bad_tokens > 0) else 0)
		return

	print("manual-stamp: %d page(s), %d re-stamped, %d with missing sources, "
		% [pages.size(), written, broken]
		+ "%d bad token(s)" % bad_tokens)
	quit(1 if (broken > 0 or bad_tokens > 0) else 0)
