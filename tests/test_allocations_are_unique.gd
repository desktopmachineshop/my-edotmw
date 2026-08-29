extends GutTest

## Nothing is allocated twice, in any namespace (#363, #362).
##
## Two collisions were found by a merge rehearsal within days of each
## other, and they are the same bug wearing different clothes: a scarce
## namespace, allocated by branches that cannot see one another.
##
##   keyboard letters   #302 moved `garrison_wall` G -> J; #246 added
##                      `farm` on J. Both checked J against the tables AS
##                      THEY STOOD ON MAIN.
##   wire opcodes       three PRs each defined a different message at 39.
##
## One test, because it is one rule. Splitting it per namespace is how the
## next scarce thing — a bus name, a control-group digit, a cheat opcode —
## gets allocated with no guard at all.
##
## ## It reads THE REAL TABLES
##
## Every claim below comes from `get_script_constant_map()` on the
## shipping script, so there is no parallel copy of the allocation that
## could drift from the thing actually in use. A test that asserted
## against its own list would pass while the client bound something else.
##
## ## What is loud already, and what is silent
##
## A duplicate key inside ONE dictionary literal is a **parse error** —
## verified, not assumed: `Key "A" was already used in this dictionary`,
## and the script fails to load. That is loud, but at the worst possible
## moment (a merge, with the client not loading at all), which is why the
## in-flight reservation table matters more than this scan.
##
## What is SILENT, and what this file is really for:
##
##   - the same letter in TWO tables — `BUILD_KEYS` is consulted before
##     `TRAIN_KEYS` and before the hand-written branches, so the later
##     claim is simply unreachable and nothing says so. That was #302:
##     `G` was in `BUILD_KEYS` and `_gather_selected()` could never be
##     reached from the keyboard;
##   - two opcode constants with the same number, which the round-trip
##     tests cannot see because a round trip is self-consistent even when
##     two messages share an id.

const CLIENT := "res://client.gd"
const PROTOCOL := "res://net_protocol.gd"

## Key tables, in the order `Client._handle_key` consults them. The order
## is what decides which claim wins, so it is recorded rather than
## implied.
const KEY_TABLES := ["RESERVED_KEYS", "BUILD_KEYS", "TRAIN_KEYS",
	"RESERVED_FOR_IN_FLIGHT"]


func _constants(path: String) -> Dictionary:
	var script: GDScript = load(path)
	assert_not_null(script, "%s must load" % path)
	return script.get_script_constant_map() if script != null else {}


## Every claim in a namespace, as `claim -> who claimed it`, or the
## clashes if any claim was made twice.
func _collect(claims: Array) -> Array:
	var seen := {}
	var clashes := []
	for claim in claims:
		var what := String(claim[0])
		var who := String(claim[1])
		if seen.has(what):
			clashes.append("%s is claimed by BOTH %s and %s" % [what, seen[what], who])
		else:
			seen[what] = who
	return clashes


func test_nothing_is_allocated_twice_in_any_namespace() -> void:
	var report := []

	# --- keyboard letters -------------------------------------------
	var client := _constants(CLIENT)
	var letters := []
	var tables_seen := 0
	for table in KEY_TABLES:
		if not client.has(table):
			continue          # RESERVED_FOR_IN_FLIGHT may legitimately be absent
		tables_seen += 1
		for letter in Dictionary(client[table]):
			letters.append([String(letter), table])
	assert_gt(tables_seen, 2,
		"the key tables must actually be readable from client.gd — if this "
		+ "drops to zero the whole check passes vacuously")
	assert_gt(letters.size(), 10, "and must actually contain the bindings")
	report.append_array(_collect(letters))

	# --- wire opcodes -------------------------------------------------
	var protocol := _constants(PROTOCOL)
	var opcodes := []
	for name in protocol:
		var id := String(name)
		if not (id.begins_with("C2S_") or id.begins_with("S2C_")):
			continue
		if typeof(protocol[name]) != TYPE_INT:
			continue          # OPCODES/OPCODE_RANGES are tables, not opcodes
		opcodes.append([str(int(protocol[name])), id])
	assert_gt(opcodes.size(), 30,
		"the protocol constants must actually be readable from net_protocol.gd")
	report.append_array(_collect(opcodes))

	assert_eq(report.size(), 0,
		("a namespace allocated twice: the later claim is unreachable, or two "
		+ "messages share an id. %s") % str(report))


func test_the_client_tables_are_the_ones_the_game_uses() -> void:
	# The anti-drift clause, and the reason this file loads the script
	# rather than keeping its own list: a guard that checked a copy would
	# stay green while the client bound something else entirely.
	var client := _constants(CLIENT)
	for table in ["BUILD_KEYS", "TRAIN_KEYS"]:
		assert_true(client.has(table),
			"client.gd must expose %s — this test reads the shipping table, "
				% table + "not a description of it")
	# And they must be non-empty dictionaries of letter -> id, which is
	# what makes the collection above meaningful.
	for table in ["BUILD_KEYS", "TRAIN_KEYS"]:
		var value = client.get(table, null)
		assert_eq(typeof(value), TYPE_DICTIONARY, "%s must be a dictionary" % table)
		assert_gt(Dictionary(value).size(), 0, "%s must not be empty" % table)


## A DUPLICATE WITHIN ONE TABLE IS A PARSE ERROR, not a silent win.
##
## Recorded here because a report reached me claiming the opposite — that
## a GDScript dictionary literal with a repeated key "silently keeps one
## entry", making the symptom a building no keyboard can reach.
##
## It does not. Verified directly against this engine (Godot 4.7.1) on
## 2026-08-28 with a throwaway script holding `{"A": 1, "A": 2}`:
##
##     Parse Error: Key "A" was already used in this dictionary (at line 2).
##     Failed to load script with error "Parse error".
##
## which is also exactly what #363 observed in the wild on `BUILD_KEYS`.
##
## It is NOT asserted at runtime here on purpose: compiling bad source
## emits that engine error on every single run, and a permanent parse
## error in the log is the noise-floor problem #338 was filed about —
## the condition under which a real new error goes unread. It is an
## ENGINE behaviour, not project code that can regress, so it is checked
## once by hand and written down.
##
## The distinction matters for what these guards are FOR. Intra-table
## duplication cannot ship — it cannot even parse. The reachable failures
## are CROSS-table (checked above) and cross-BRANCH (checked by the
## reservation tables), and those are the silent ones.
