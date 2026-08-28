extends GutTest

## Guards the fix for #376's instrument half: a player seated AFTER the
## match began never had their civ settled, so the server resolved one
## thing and the client believed another.
##
## `_civ_of` is total — with nothing recorded it falls back to
## `all[(player - 1) % all.size()]` — and that fallback is what the server
## trains rosters, costs and D-047 knobs from. Nothing wrote it down, and
## `_on_match_started`'s resolve loop only covers seats present when the
## match started. Every `test-load` bot and every human joining a
## `--lobby=0` server misses it, so their seat still said "Random" and
## `ClientState.civ_of` answered `""` for the whole match.
##
## Nothing could fail: the server never reads the seat for a roster, and
## the client only ever DISPLAYS a civ. The declared-and-unread family
## with the two sides holding different answers rather than one going
## unread — and it made every harness's civ reporting fiction.
##
## "server.gd needs a socket and a scene tree" is true of `_ready()`, not
## of the file (D-075's 2026-08-16 amendment, and `test_civ_knobs.gd`'s
## precedent): a Node never added to the tree does not run `_ready()`.

const W := 24
const H := 12


func _server() -> Object:
	var server = load("res://server.gd").new()
	var space := TorusSpace.new(W, H, 1.0)
	server._sim = SquadSim.new(space, CurveReplicator.new())
	server._buildings = BuildingSim.new(space)
	server._economy = Economy.new(space)
	server._sim.buildings = server._buildings
	server._sim.economy = server._economy
	server._match = MatchState.new()
	return server


func _seat_civ(server: Object, player: int) -> StringName:
	var index: int = server._match.seat_of(player)
	if index < 0:
		return &""
	return StringName(server._match.seats[index].get("civ", ""))


## Seat a player and put their seat in the state the caller means, rather
## than whatever `add_player` happened to leave. The first version of this
## file did not, and paid for it: a bare `MatchState.new()` has an
## UNSEEDED `civ_rng`, and seating resolves the first seat's Random to a
## real civ through it — so the fixture handed player 1 a different civ on
## every run and two assertions failed for a reason that was nothing to do
## with the code under test.
func _seat(server: Object, player: int, civ: StringName) -> void:
	server._match.add_player(player)
	server._match.seats[server._match.seat_of(player)]["civ"] = civ


func test_an_unresolved_seat_starts_out_disagreeing() -> void:
	# The fixture must actually be the broken situation, or everything
	# below passes vacuously.
	var server := _server()
	_seat(server, 1, CivRoster.RANDOM)
	assert_ne(_seat_civ(server, 1), server._civ_of(1),
		"fixture: an unresolved seat must NOT already agree with _civ_of, "
		+ "or this file proves nothing")
	assert_null(CivRoster.by_id(_seat_civ(server, 1)),
		"fixture: and it must not name a real civ yet")
	assert_false(server._civs.has(1), "fixture: nothing is recorded yet")


func test_settling_makes_the_seat_agree_with_the_civ_the_server_uses() -> void:
	var server := _server()
	_seat(server, 1, CivRoster.RANDOM)
	var resolved: StringName = server._civ_of(1)

	server._settle_civ(1)

	assert_eq(server._civs.get(1), resolved,
		"the server must record the civ it already resolves against")
	assert_eq(_seat_civ(server, 1), resolved,
		"and the SEAT must carry it — that is what scoreboard() sends and "
		+ "what ClientState.civ_of reads")
	assert_not_null(CivRoster.by_id(_seat_civ(server, 1)),
		"a settled seat must name a civ that exists")
	assert_ne(_seat_civ(server, 1), CivRoster.RANDOM,
		"and never the unresolved placeholder")


func test_settling_changes_no_civ_the_server_would_have_used() -> void:
	# The claim that makes this safe to land mid-cycle: the VALUE is
	# unchanged, so no troops, stockpiles or D-047 knobs move and every
	# figure measured before it stays comparable.
	for player in [1, 2, 3, 4, 7]:
		var server := _server()
		_seat(server, player, CivRoster.RANDOM)
		var before: StringName = server._civ_of(player)
		server._settle_civ(player)
		assert_eq(server._civ_of(player), before,
			"player %d's civ must be recorded, not changed" % player)


func test_a_seat_that_names_a_real_civ_is_never_overwritten() -> void:
	# The regression this could most easily cause. `_seat_ai` deals a civ
	# at construction and its own comment records what happened when the
	# round-robin disagreed: "The AI reported one civilisation in AI_STATS
	# and fielded another's troops for the whole match." An AI's player id
	# is 1000-odd, so the modulo answers almost anything.
	var ids := CivRoster.ids()
	assert_gt(ids.size(), 1, "need two civs to tell overwrite from agreement")
	var server := _server()
	# Deliberately the civ the fallback would NOT pick.
	_seat(server, 1, CivRoster.RANDOM)
	var dealt: StringName = ids[1] if StringName(ids[0]) == server._civ_of(1) else ids[0]
	server._match.seats[server._match.seat_of(1)]["civ"] = dealt

	server._settle_civ(1)

	assert_eq(_seat_civ(server, 1), dealt, "a dealt civ must survive settling")
	assert_eq(server._civs.get(1), dealt, "and be what the server resolves against")


func test_an_already_recorded_civ_wins() -> void:
	# `_on_match_started` and `_seat_ai` are authoritative; settling must
	# never second-guess them.
	var ids := CivRoster.ids()
	var server := _server()
	_seat(server, 1, CivRoster.RANDOM)
	var recorded := StringName(ids[ids.size() - 1])
	server._civs[1] = recorded

	server._settle_civ(1)

	assert_eq(server._civs.get(1), recorded, "a recorded civ is authoritative")
	assert_eq(_seat_civ(server, 1), recorded,
		"and the seat is brought into line with it, not the other way round")


func test_admission_settles_the_civ() -> void:
	# The caller-exists check (D-106's rule, as a test). Every assertion
	# above can pass while nothing calls `_settle_civ` on the path that
	# matters — which is exactly how the original defect survived.
	var source := FileAccess.get_file_as_string("res://server.gd")
	var admit := source.find("func _admit_player")
	assert_gt(admit, 0, "server.gd must still have _admit_player")
	var body := source.substr(admit, 1200)
	assert_true(body.contains("_settle_civ("),
		"_admit_player must settle the civ, or a mid-match seat is still "
		+ "admitted with an unresolved one")
