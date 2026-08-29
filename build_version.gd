class_name BuildVersion
extends RefCounted

## THE one definition of which build this is
## (D-20260827-the-build-is-exported-from-one-version, D-094 criterion 1).
##
## The number itself lives in `project.godot` as
## `application/config/version`, because that is the one place BOTH sides
## of the boundary can read it: GDScript at runtime through
## `ProjectSettings` (baked into the .pck, so an exported build answers
## the same as a checkout), and the `just export` recipe by reading the
## file, so the artifacts are named after the build they contain.
##
## All-static and pure, like CmdArgs and HudLayout, for the same reason:
## a version is a fact about the build, not a thing with instances, and
## a second copy of it is the whole defect this file exists to prevent.
## The project has already paid for the two-copies shape more than once
## (D-058/D-065's "a decision entry saying a field is on the wire is not
## evidence that it is"), and a version is the worst possible field to
## get a second writer, because a wrong one is indistinguishable from a
## right one until somebody is debugging a mixed-build match.
##
## **Deliberately not a git sha and deliberately not a timestamp.**
## D-081 requires that anything generated be reproducible, and #178 says
## so in its own words. A clean clone of this commit must export bytes
## that match this one's; a sha or a build date makes that false by
## construction, and makes "both binaries print the same version" a
## statement about when they were built rather than about what is in
## them.

const SETTING := "application/config/version"

## The version string, e.g. "0.1.0-alpha". Never empty: a build that
## somehow lost the setting says so out loud rather than reporting a
## blank, because a blank version compares equal to another blank one.
static func string() -> String:
	var raw := str(ProjectSettings.get_setting(SETTING, ""))
	if raw.is_empty():
		return "unversioned"
	return raw


## The one line both binaries print at start, so a bug report that
## includes the first line of a log says which build it came from.
## `who` is "server" / "client" / "bots" — the same prefix each of them
## already uses for every other line it prints.
static func banner(who: String) -> String:
	return "%s: my-edotmw %s" % [who, string()]
