class_name Platform
extends RefCounted

## THE one script in this project that names Steam (D-093, #181).
##
## **It is called `Platform`, not `SteamPlatform`, and that is not a
## style choice** (#184). D-093's rule is that no other `.gd` file
## mentions Steam at all — so a boundary whose own CLASS NAME contains
## the word cannot be called from anywhere without breaking the rule it
## exists to enforce. `SteamPlatform` passed its own grep test only
## because nothing called it: the declared-and-unread shape this project
## keeps finding, arriving in the guard rather than in the feature. The
## first consumer (#184's transport) found it immediately.
##
## The rename is also the better abstraction. Nothing outside this file
## should care that the platform IS Steam; it should ask whether there is
## a platform, what identity it offers and whether it can carry a socket.
## If GodotSteam is ever replaced (D-093's own fallback ladder), the
## callers do not move.
##
## Every Steamworks call this game will ever make goes through here, and
## `tests/test_steam_boundary.gd` fails if any other `.gd` file names the
## API at all — the same falsifiable-by-grep pattern as D-046 criterion 3
## (no script names a civ) and D-086's lighting-rig guard. That test is
## the whole reason D-021 could be amended by exactly one category
## (platform integration) without the amendment becoming a hole: the rule
## is structural rather than remembered.
##
## ## Absent Steam costs Steam, never the game
##
## No Steam context — docker, CI, the bots, a LAN game, a clone that has
## installed nothing — means every function here reports unavailable and
## everything else works over ENet exactly as it does today. The
## precedent is D-081's empty `model_id`: a missing integration costs
## FIDELITY (no relay, no lobbies, no invites), not function.
##
## **That is also the configuration this file is actually exercised in.**
## Every automated context this repo has is Steam-less, which is the
## right way round — the fallback is the constantly-tested path rather
## than the one nobody runs. D-094 criterion 7 asks for it to be
## ASSERTED rather than assumed, and it is.
##
## ## How Steam is detected, and why that survives the open question
##
## `Engine.has_singleton("Steam")` / `ClassDB.class_exists("Steam")`. Both
## answer the same way whether GodotSteam arrives as a GDExtension or as
## a modified engine build — which matters, because
## `decisions/D-20260828-godotsteam-does-not-ship-a-gdextension.md`
## records that D-093's assumed distribution shape does not exist, and
## the question of how it arrives is open. **This file is indifferent to
## the answer**, and that is deliberate: the boundary was built first so
## that the transport (#184), the lobbies (#187) and the identity (#186)
## can be written against a fixed surface whichever way it lands.
##
## All-static and pure, like `CmdArgs` and `BuildVersion`, for the same
## reason: there is exactly one Steam context per process and it is the
## engine's, not this class's. An instance would be a second place for it
## to live.

## The class GodotSteam registers. Named once, here, so the detection and
## the grep test agree about what "Steam is present" means.
const SINGLETON := "Steam"

## The GodotSteam release this project is pinned to, read from
## `.godotsteam-version` — `.godot-version`'s sibling, and paired with it
## on purpose. **A mismatched pair fails at LOAD, not at build**, which
## means on a player's machine rather than on the builder's, so the pin
## records the pairing and `just doctor` prints both.
const VERSION_FILE := "res://.godotsteam-version"


## Whether a Steam context is reachable from this process.
##
## The one question everything else here is gated on. False in docker, in
## CI, in the bots, in every test, and in any clone that has installed
## nothing — which is every automated context this repo has.
static func available() -> bool:
	return Engine.has_singleton(SINGLETON) or ClassDB.class_exists(SINGLETON)


## The pinned GodotSteam version, or "" if the pin is missing.
##
## A string rather than a parsed thing: nothing compares it, `doctor`
## prints it, and the moment something starts comparing it that is a
## decision about compatibility rather than a formatting change.
static func pinned_version() -> String:
	if not FileAccess.file_exists(VERSION_FILE):
		return ""
	var handle := FileAccess.open(VERSION_FILE, FileAccess.READ)
	if handle == null:
		return ""
	var text := handle.get_as_text().strip_edges()
	handle.close()
	return text


## This player's Steam identity, or 0 when Steam is absent.
##
## Zero is the "no identity" value and every caller must treat it as one:
## D-090 rebinds a SEAT by SteamID, and a seat rebound by 0 would be a
## seat anybody could claim. That is a rule for #186 to enforce at the
## point of use; this only promises never to invent one.
static func steam_id() -> int:
	if not available():
		return 0
	return int(Engine.get_singleton(SINGLETON).call("getSteamID"))


## The player's Steam display name, or "" when Steam is absent.
##
## Cosmetic only, and deliberately so: a name is what a lobby shows, and
## nothing may key on it. Steam names are user-settable and non-unique,
## so a seat identified by one is a seat two people can claim.
static func persona_name() -> String:
	if not available():
		return ""
	return str(Engine.get_singleton(SINGLETON).call("getPersonaName"))


## One line for `just doctor`, in the same reported-never-required style
## the art tooling and the export templates are reported under: producing
## a Steam build needs Steam, playing the game does not.
static func describe() -> String:
	var pin := pinned_version()
	var pinned := pin if not pin.is_empty() else "unpinned"
	if available():
		return "steam: available — GodotSteam pinned at %s" % pinned
	return ("steam: absent — GodotSteam pinned at %s. "
		+ "Steam features (relay, lobbies, invites) are off; "
		+ "ENet, LAN, docker and every test recipe are unaffected (D-093).") % pinned


# --- carrying the game's wire (D-088, #184) ----------------------------
#
# D-088 puts remote players on Steam's networking with relay, so NAT and
# port-forwarding never reach a user. `net_transport.gd` is the shape the
# server and the client take; what follows is what this boundary owes a
# Steam implementation of it, and the mapping it must use.
#
# ## Channels to lanes, and the one thing that must not be got wrong
#
# The game opens `CHANNELS = 2` and sends everything reliable on channel
# 0. ENet's guarantee is reliable-ordered WITHIN a channel; Steam's
# `k_nSteamNetworkingSend_Reliable` is reliable-ordered WITHIN a lane.
# So the mapping is the identity — **ENet channel N is Steam lane N** —
# and it holds because both guarantee ordering per-stream rather than
# globally.
#
# **The send flag is the dangerous half.** Steam offers unreliable sends
# on the same connection, and D-042 measured that this protocol cannot
# use them: curve packets carry no sequence number, so a single reorder
# leaves a client permanently holding a stale curve with no later message
# to correct it (curves are sent only on change, D-003). A wrapper that
# reached for `Unreliable` — for the perfectly reasonable-sounding reason
# that position updates are usually fine to drop — would produce exactly
# the desync class the state-hash machinery exists to catch, rarely and
# unreproducibly. `tests/test_transport_ordering.gd` is what a wrapper is
# held against; it drives a deliberately reordering transport through the
# seam and fails if the client does NOT diverge.

## The lane a channel maps to. The identity, and a named function rather
## than an assumption, so the day it stops being the identity there is
## one place to change and one place to read.
static func lane_for_channel(channel: int) -> int:
	return channel


## Whether this build could carry the game's wire over Steam.
##
## False without a Steam context, which is docker, CI, the bots, every
## test and every clone that has installed nothing — so the ENet path is
## what actually runs, everywhere, today. It is also false when Steam IS
## present but the transport has not been built yet, which is where this
## stands: #184 laid the seam and the mapping, and the wrapper itself
## needs a Steam runtime and an account to write against.
static func can_carry_a_socket() -> bool:
	if not available():
		return false
	# The wrapper is not written. Reporting `true` here on the strength
	# of Steam merely being present would be the worst kind of wrong: the
	# caller would choose a transport that does not exist, and would do
	# it only on the machines that have Steam — never on any machine that
	# runs the tests.
	return false


## Why `can_carry_a_socket()` said no, for a caller that has to explain
## itself to a player or a log. Never empty when it said no.
static func socket_unavailable_reason() -> String:
	if not available():
		return ("Steam is not available in this build, so its relay is not either. "
			+ "Direct connections over ENet are unaffected (D-093).")
	return ("Steam is available but the Steam transport is not built yet (#184) — "
		+ "the seam and the lane mapping are in place; the wrapper needs a Steam "
		+ "runtime to write against. Use a direct address for now.")


## What to CALL this platform in front of a player.
##
## It exists because #184 found the rule's next collision before it
## happened. D-093 forbids any other `.gd` from naming Steam, and that is
## right for CALLS — but #187's lobby browser has to put the word on a
## button, and a UI file spelling it out would either break the guard or
## force the guard to be weakened for everybody.
##
## So user-facing text comes from here too, which is the better shape
## anyway: one place decides what the platform is called, exactly as
## `player_colours.gd` is the one place that decides what a player's
## colour is (D-052). A caller writes
## `"%s lobbies" % Platform.display_name()` and never the word itself.
static func display_name() -> String:
	return "Steam"
