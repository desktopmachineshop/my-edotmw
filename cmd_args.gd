class_name CmdArgs
extends RefCounted

## The one parse of `--key=value` command-line arguments, and the one
## check that a value the program is about to read as a NUMBER actually
## is one (D-20260817-recipe-args-are-positional, #89/#98).
##
## All-static and pure, like Formation and HudLayout, for the same
## reason: `server.gd`, `client.gd` and `bot_client.gd` each carried a
## byte-identical private copy of the parser, and none of them could be
## reached from a GUT test to prove what it does with a bad value.
##
## **Why the check exists at all.** GDScript's `int()` STRIPS non-digit
## characters rather than failing, so a malformed argument does not
## arrive as an obvious 0 — it arrives as a plausible small number:
##
##     int("SANDBOX=1") == 1     int("AI=3") == 3     int("1.5") == 1
##
## `just quick-test SANDBOX=1` therefore launched on world seed 1 instead
## of 1337, silently, and no value anywhere in the log looked wrong
## enough to notice. The recipes now check what they were handed
## (`recipe-arg.sh`), and this is the same check on the far side of the
## boundary — because the server, the client and the bots can all be
## launched by hand, which `docs/COMMANDS.md` explicitly tells you to do
## when a recipe does not expose the flag you want.


## Splits `--key=value` arguments into a Dictionary. Only the FIRST `=`
## separates, so a value containing one of its own survives intact —
## `--seed=SANDBOX=1` parses to "SANDBOX=1" rather than to "SANDBOX",
## which is what lets the check below name the real mistake. Anything
## that is not `--key=value` is ignored, as it always has been.
static func parse(raw_args: PackedStringArray) -> Dictionary:
	var parsed := {}
	for arg in raw_args:
		if arg.begins_with("--"):
			var kv := arg.substr(2).split("=", true, 1)
			if kv.size() == 2:
				parsed[kv[0]] = kv[1]
	return parsed


## The names, in the order asked for, of the arguments that are PRESENT
## and cannot be read as an integer. Empty means every one of them is
## usable. An absent argument is not an error — it takes its default.
static func invalid_integers(args: Dictionary, keys: PackedStringArray) -> PackedStringArray:
	var bad := PackedStringArray()
	for key in keys:
		if args.has(key) and not String(args[key]).is_valid_int():
			bad.append(key)
	return bad


## The same for arguments read as a float. `is_valid_float` accepts an
## integer too, so a caller never has to ask for both.
static func invalid_numbers(args: Dictionary, keys: PackedStringArray) -> PackedStringArray:
	var bad := PackedStringArray()
	for key in keys:
		if args.has(key) and not String(args[key]).is_valid_float():
			bad.append(key)
	return bad


## One line naming what was wrong, for a program that is about to quit
## over it. Kept here so server, client and bots word it identically.
static func complaint(who: String, bad: PackedStringArray) -> String:
	return "%s: these arguments are not numbers: %s — note that `just` binds recipe arguments positionally, so `SANDBOX=1` after a recipe name lands in the first parameter" % [who, ", ".join(bad)]
