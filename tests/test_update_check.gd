extends GutTest

## Guards D-20260830-releases-are-a-tag-and-a-nightly-channel: the
## main-menu update check.
##
## The pure halves are what carry the risk — parsing an UNTRUSTED body
## and deciding "newer" — so they are tested exhaustively here, and the
## network half in client.gd is covered by CALLER scans (D-106's rule):
## every parse test below would pass with the menu asking nothing, and
## the "constructed URL only" rule is not something a behavioural test
## can see.


func test_the_api_and_page_urls_are_built_from_the_one_repo_constant() -> void:
	assert_eq(UpdateCheck.api_url(),
		"https://api.github.com/repos/%s/releases/latest" % UpdateCheck.REPO)
	assert_eq(UpdateCheck.page_url(),
		"https://github.com/%s/releases/latest" % UpdateCheck.REPO)
	assert_true(UpdateCheck.page_url().begins_with("https://github.com/"),
		"the button opens GitHub and nothing else")


func test_a_good_body_yields_its_version_with_the_v_stripped() -> void:
	var body := JSON.stringify({"tag_name": "v0.2.0", "html_url": "https://evil.example"})
	assert_eq(UpdateCheck.latest_version(body), "0.2.0")


func test_a_tag_without_the_v_still_parses() -> void:
	assert_eq(UpdateCheck.latest_version(JSON.stringify({"tag_name": "0.3.1"})), "0.3.1")


func test_garbage_bodies_yield_nothing_rather_than_something_plausible() -> void:
	# Every failure path answers "", which the caller reads as silence —
	# a hostile or truncated body must never produce a banner.
	assert_eq(UpdateCheck.latest_version(""), "")
	assert_eq(UpdateCheck.latest_version("not json {{{"), "")
	assert_eq(UpdateCheck.latest_version("[1, 2, 3]"), "")
	assert_eq(UpdateCheck.latest_version(JSON.stringify({"message": "Not Found"})), "")


func test_newer_is_a_strict_numeric_comparison() -> void:
	assert_true(UpdateCheck.is_newer("0.2.0", "0.1.0-alpha"))
	assert_true(UpdateCheck.is_newer("0.1.1", "0.1.0"))
	assert_true(UpdateCheck.is_newer("1.0.0", "0.9.9"))
	assert_false(UpdateCheck.is_newer("0.1.0", "0.1.0"))
	assert_false(UpdateCheck.is_newer("0.1.0", "0.2.0"),
		"a dev checkout ahead of the last tag must not nag")


func test_a_release_outranks_its_own_prerelease_and_nothing_more() -> void:
	assert_true(UpdateCheck.is_newer("0.1.0", "0.1.0-alpha"))
	assert_false(UpdateCheck.is_newer("0.1.0-alpha", "0.1.0"))
	assert_false(UpdateCheck.is_newer("0.1.0-beta", "0.1.0-alpha"),
		"two prereleases of one triple claim no order — nothing ships parallel prerelease tags")


func test_an_unparseable_version_is_never_grounds_for_a_banner() -> void:
	assert_false(UpdateCheck.is_newer("banana", "0.1.0-alpha"))
	assert_false(UpdateCheck.is_newer("0.2.0", "unversioned"))
	assert_false(UpdateCheck.is_newer("", ""))
	# int() strips non-digits (D-20260817-recipe-args-are-positional), so
	# a component like "2x" must fail the parse rather than read as 2.
	assert_false(UpdateCheck.is_newer("0.2x.0", "0.1.0"))


func test_two_part_versions_parse_with_a_zero_patch() -> void:
	assert_true(UpdateCheck.is_newer("0.2", "0.1.9"))
	assert_false(UpdateCheck.is_newer("0.1", "0.1.0"))


# --- caller scans (D-106: the test that catches this class asserts the
# --- caller exists) -----------------------------------------------------

var _client_source: String = ""


func _client() -> String:
	if _client_source.is_empty():
		var f := FileAccess.open("res://client.gd", FileAccess.READ)
		_client_source = f.get_as_text()
	return _client_source


func test_the_menu_actually_asks() -> void:
	assert_true(_client().contains("UpdateCheck.api_url()"),
		"client.gd never requests the releases API — the check is dead code")


func test_the_button_opens_the_constructed_page_and_never_the_response() -> void:
	assert_true(_client().contains("OS.shell_open(UpdateCheck.page_url())"),
		"the update button must open the URL built from REPO — never one off the wire")
