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


# --- the game browser's platform provider (#187) ------------------------
#
# The browser in the pre-lobby menu holds an ARRAY of providers and knows
# nothing about any of them beyond five methods (`lan_discovery.gd`
# documents the duck type and is the reference implementation). That is
# what keeps this integration a FILE rather than a branch: with no
# platform there is one provider in the array instead of two, and there
# is no platform code path left to be broken by — the same shape D-051
# used for AI players and D-081 for a missing `model_id`.


## The provider that lists this platform's lobbies, or null when there is
## no platform — which is docker, CI, the bots, every test, and any clone
## that has installed nothing.
##
## Null rather than a provider that returns nothing, deliberately: the
## menu says which SOURCES it is searching, and a source that can never
## answer should not be listed as one. "Looking on the network and on a
## platform that is not here" is a lie a player would read as a fault.
static func lobby_provider() -> RefCounted:
	if not available():
		return null
	return LobbyProvider.new()


## Whether invites can be sent and received. False with no platform, and
## the caller's job is to draw no invite affordance at all rather than a
## disabled one — an invite button that cannot invite is D-061's family.
static func invites_available() -> bool:
	return available()


## The platform half of #187, stubbed at the boundary with the calls it
## will make written down, because the OWNER'S half of Steam (the app id,
## the depot, an installed client) is a prerequisite this repo cannot
## satisfy and must not pretend to.
##
## What lands here when that half exists, in the order it will be
## written:
##
## 1. `poll` drives the platform's own message pump and, once a second at
##    most, asks for the lobby list — filtered on the protocol version
##    stored as lobby metadata, so an incompatible build never reaches
##    `GameBrowser.can_join` at all. That metadata is a STRING key/value
##    map on the lobby, set by the host and updated when seats change,
##    which is why `lan_beacon.gd` describes freshly per reply rather
##    than caching: the two sources must be able to say the same thing.
## 2. `take_seen` converts each lobby into the listing shape
##    `game_browser.gd` documents. A platform lobby has no address and no
##    port — it is joined by id, over the platform's own transport
##    (#184) — so those two fields are empty and `join` below is what a
##    row's press calls instead. The browser already treats the endpoint
##    as opaque for exactly this reason.
## 3. Invites, both directions: an overlay invite dialog from inside the
##    lobby, and a join-requested callback from outside the game,
##    including a cold launch carrying a lobby id on the command line.
##    That last one is the case that always gets forgotten and is the
##    only one D-094 criterion 4 names by itself.
##
## Nothing here fabricates an answer while the platform is absent. It
## cannot be reached at all in that case — `lobby_provider` returns null
## — which is what makes "absent costs features, never function" a
## structural claim rather than a promise.
class LobbyProvider extends RefCounted:
	func id() -> String:
		return "platform"

	func label() -> String:
		return "Friends and public games"

	func poll(_now: float) -> void:
		pass

	func take_seen() -> Array:
		return []

	func status() -> String:
		return "the platform lobby list is not wired up yet (#187)"
