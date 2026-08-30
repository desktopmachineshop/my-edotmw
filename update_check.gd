class_name UpdateCheck
extends RefCounted

## Is a newer OFFICIAL release available, and where does a player get it
## (D-20260830-releases-are-a-tag-and-a-nightly-channel)?
##
## The client asks GitHub's public releases API from the MAIN MENU — the
## one screen where a player is not in a match — compares the answer with
## `BuildVersion.string()`, and offers a button. The button ALWAYS opens
## `page_url()`, a URL constructed HERE from `REPO`: nothing from the
## response body is ever opened, for the reason `game_browser.gd` already
## records — a reply that could name the destination could point every
## player's browser at a third party. The response contributes exactly
## one thing, the version number, and a malformed or hostile body
## contributes nothing (every failure path answers "", which the caller
## reads as "say nothing").
##
## `releases/latest` deliberately never returns a PRERELEASE, which is
## what keeps the nightly channel opt-in: the rolling `nightly` tag is
## published as a prerelease, so this check tracks official tags only and
## a nightly user is never nagged sideways.
##
## All-static and pure, like MainMenu and GameBrowser, so the halves with
## the interesting failure modes — parsing an untrusted body, deciding
## whether a version is genuinely NEWER — are testable without a socket.
## The one HTTPRequest lives in client.gd, fired once per process.

## The one definition of which repository this game's releases live in.
const REPO := "desktopmachineshop/my-edotmw"

## Answers `{"tag_name": "v0.2.0", ...}` for the newest non-prerelease
## release. On a PRIVATE repo this 404s, which the caller treats as
## silence — so the check can ship before the repo is public and simply
## light up the day it flips.
static func api_url() -> String:
	return "https://api.github.com/repos/%s/releases/latest" % REPO


## Where the button sends a player. Constructed, never read off the wire.
static func page_url() -> String:
	return "https://github.com/%s/releases/latest" % REPO


## The version the API body names, or "" for anything unexpected.
##
## A `JSON` instance rather than `JSON.parse_string`, for the reason
## `lan_discovery.gd` records: the static helper pushes an engine error
## per malformed document, and this body arrives off a network.
static func latest_version(body: String) -> String:
	var json := JSON.new()
	if json.parse(body) != OK:
		return ""
	var data: Variant = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return ""
	var tag := str((data as Dictionary).get("tag_name", ""))
	if tag.begins_with("v"):
		tag = tag.substr(1)
	return tag


## Whether `theirs` is a genuinely NEWER version than `mine`.
##
## False on a tie, false when MINE is ahead (a dev checkout past the last
## tag must not nag), and false when either side does not parse — a
## version this function cannot read is never grounds for telling a
## player to download something.
##
## Numeric triples compare numerically; on a tie, a release with no
## suffix outranks one with a suffix (0.1.0 is newer than 0.1.0-alpha),
## and two suffixed versions with equal triples claim no order at all —
## nothing here ships parallel prerelease TAGS, so inventing an ordering
## for them would be a rule with no data behind it.
static func is_newer(theirs: String, mine: String) -> bool:
	var a := _parse(theirs)
	var b := _parse(mine)
	if not bool(a["ok"]) or not bool(b["ok"]):
		return false
	var an: Array = a["nums"]
	var bn: Array = b["nums"]
	for i in range(3):
		if int(an[i]) != int(bn[i]):
			return int(an[i]) > int(bn[i])
	return String(a["suffix"]).is_empty() and not String(b["suffix"]).is_empty()


## The banner's one sentence.
static func banner_text(theirs: String) -> String:
	return "Version %s is available" % theirs


## "MAJOR.MINOR.PATCH[-suffix]" -> {ok, nums, suffix}. Each numeric part
## is checked with `is_valid_int` rather than trusted to `int()`, which
## STRIPS non-digits and would read garbage as a plausible small number —
## the same trap D-20260817-recipe-args-are-positional records for
## recipe arguments.
static func _parse(version: String) -> Dictionary:
	var bad := {"ok": false, "nums": [], "suffix": ""}
	if version.is_empty():
		return bad
	var dash := version.find("-")
	var numeric := version if dash < 0 else version.substr(0, dash)
	var suffix := "" if dash < 0 else version.substr(dash + 1)
	var parts := numeric.split(".")
	if parts.size() < 2 or parts.size() > 3:
		return bad
	var nums := []
	for part in parts:
		if not part.is_valid_int():
			return bad
		nums.append(int(part))
	while nums.size() < 3:
		nums.append(0)
	return {"ok": true, "nums": nums, "suffix": suffix}
