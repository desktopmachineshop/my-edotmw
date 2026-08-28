class_name SteamPlatform
extends RefCounted

## THE one script in this project that names Steam (D-093, #181).
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
