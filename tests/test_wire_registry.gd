extends GutTest

## Guards that no two messages share a wire opcode (#362).
##
## `net_protocol.gd` is "the one definition of the wire protocol, shared
## by server, client and bots so they can't drift" (CLAUDE.md). Two
## messages sharing an id breaks that in the worst available way: a
## client sends "I surrender" and the server reads "start researching".
##
## It happened. Three open PRs each defined a different message at
## opcode 39 — surrender (#297), explore (#273), research (#225) — on
## three independent chains, each allocating "the next free number on
## `main`", which is the same number for everybody who branched from one
## commit.
##
## **The existing suite could not see it**, and that is the interesting
## part rather than an oversight: it checks encode/decode ROUND TRIPS per
## message, and a round trip is self-consistent even when two messages
## share a number. Each PR was green on its own branch and green in
## isolation after merging; only the union was broken, and git reports it
## only if the two edits land in the same file region.
##
## Same family as D-042's note that curve packets carry no sequence
## number so in-order delivery is load-bearing — a property nothing
## asserts until something depends on it.

const PROTOCOL := "res://net_protocol.gd"


func _constants() -> Dictionary:
	var script: GDScript = load(PROTOCOL)
	assert_not_null(script, "net_protocol.gd must load")
	return script.get_script_constant_map()


func _source() -> String:
	var handle := FileAccess.open(PROTOCOL, FileAccess.READ)
	assert_not_null(handle, "net_protocol.gd must be readable")
	if handle == null:
		return ""
	var text := handle.get_as_text()
	handle.close()
	return text


func test_no_two_messages_share_an_opcode() -> void:
	# THE check, and it is three lines, which is what makes its absence
	# worth recording: it would have caught this the moment the second PR
	# was opened.
	var table: Dictionary = _constants().get("OPCODES", {})
	assert_gt(table.size(), 30, "the registry must actually hold the protocol")

	# Live allocations AND in-flight reservations, together. Checking only
	# the live ones would miss the exact case this exists for: three
	# branches that cannot see each other, each taking the number that is
	# free on `main`.
	var all := table.duplicate()
	for name in _constants().get("OPCODES_RESERVED", {}):
		all[name] = int(_constants()["OPCODES_RESERVED"][name])

	var by_value := {}
	var clashes := []
	for name in all:
		var value := int(all[name])
		if by_value.has(value):
			clashes.append("%d is BOTH %s and %s" % [value, by_value[value], name])
		else:
			by_value[value] = String(name)
	assert_eq(clashes.size(), 0,
		("two messages sharing an id means a client sends one thing and the "
		+ "server reads another: %s") % str(clashes))


func test_every_opcode_comes_from_the_registry() -> void:
	# The half that keeps the check above meaningful. A constant written
	# as `const C2S_THING := 41` beside its encoder is invisible to a
	# registry it never entered — so every opcode must be DERIVED, which
	# makes a second home for a number inexpressible rather than merely
	# detectable.
	var source := _source()
	var re := RegEx.new()
	re.compile("(?m)^const ((?:C2S|S2C)_[A-Z_0-9]+) := (.+)$")
	var strays := []
	for hit in re.search_all(source):
		var assigned := hit.get_string(2).strip_edges()
		if not assigned.begins_with("OPCODES["):
			strays.append("%s := %s" % [hit.get_string(1), assigned])
	assert_eq(strays.size(), 0,
		("these bypass the registry, so nothing can notice them colliding: %s")
			% str(strays))


func test_the_registry_and_the_constants_agree() -> void:
	# Belt and braces, and cheap: derivation is what makes them agree, so
	# a disagreement here means somebody has reintroduced a literal.
	var consts := _constants()
	var table: Dictionary = consts.get("OPCODES", {})
	for name in table:
		assert_true(consts.has(name),
			"the registry allocates %s, which no constant exposes — a "
				% name + "reservation belongs in OPCODES_RESERVED until its "
				+ "constant lands in the same commit")
		if consts.has(name):
			assert_eq(int(consts[name]), int(table[name]),
				"%s is %d but the registry says %d"
					% [name, int(consts.get(name, -1)), int(table[name])])


func test_the_reserved_ranges_are_documented_and_respected() -> void:
	# Allocating "the next free number on main" is what collided, so the
	# space is carved into per-workstream ranges. A range that exists only
	# in somebody's head is not a convention.
	var source := _source()
	assert_true(source.contains("RESERVED RANGES"),
		"net_protocol.gd must document how an opcode is allocated, or the "
		+ "next worker allocates the same way the colliding three did")

	# The ranges are DATA, so this is a rule rather than a remembered
	# convention: an opcode outside every declared range fails here rather
	# than at a merge six branches later.
	var ranges: Dictionary = _constants().get("OPCODE_RANGES", {})
	assert_gt(ranges.size(), 3, "the ranges must be declared as data, not only in prose")

	var all: Dictionary = _constants().get("OPCODES", {}).duplicate()
	for name in _constants().get("OPCODES_RESERVED", {}):
		all[name] = int(_constants()["OPCODES_RESERVED"][name])

	var outside := []
	for name in all:
		var value := int(all[name])
		var housed := false
		for band in ranges:
			if value >= int(ranges[band][0]) and value <= int(ranges[band][1]):
				housed = true
		if not housed:
			outside.append("%s = %d" % [name, value])
	assert_eq(outside.size(), 0,
		"these fall in no declared range: %s" % str(outside))

	# And the ranges must not overlap each other, or "take the next free
	# number in your range" stops being a guarantee.
	var band_names: Array = ranges.keys()
	var overlaps := []
	for i in range(band_names.size()):
		for j in range(i + 1, band_names.size()):
			var a: Array = ranges[band_names[i]]
			var b: Array = ranges[band_names[j]]
			if int(a[0]) <= int(b[1]) and int(b[0]) <= int(a[1]):
				overlaps.append("%s and %s" % [band_names[i], band_names[j]])
	assert_eq(overlaps.size(), 0, "ranges must not overlap: %s" % str(overlaps))


func test_the_wire_numbers_already_shipped_are_frozen() -> void:
	# An opcode is a WIRE FORMAT. Renumbering one silently breaks every
	# client that has not been rebuilt, which is precisely the hazard
	# #179's version handshake exists for. Pinned so a future tidy-up of
	# the registry cannot renumber them by accident.
	var table: Dictionary = _constants().get("OPCODES", {})
	var frozen := {
		"S2C_WELCOME": 1, "S2C_CURVE": 2, "S2C_SQUAD_INFO": 3,
		"C2S_ORDER_MOVE": 10, "C2S_ORDER_STOP": 11, "C2S_ORDER_ATTACK_MOVE": 12,
		"C2S_CHAT": 22, "C2S_ORDER_CHARGE": 36, "C2S_ORDER_STANCE": 37,
		"C2S_CHEAT_REGEN_MAP": 38,
	}
	for name in frozen:
		assert_eq(int(table.get(name, -1)), int(frozen[name]),
			"%s has moved — an opcode already on main is a wire format" % name)
