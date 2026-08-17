class_name LobbyLayout
extends RefCounted

## How big the lobby screen's pieces are, for a window of any size.
##
## `hud_layout.gd`'s sibling, and all-static and pure for the same reason
## (D-061): the client cannot be tested headless (D-014), but "does the
## lobby fit in the window" is arithmetic and needs no GPU to answer. The
## lobby's geometry used to be hand-rolled inside `client.gd` — a fixed
## margin, a fixed right-hand column, six fixed panel minimums — which is
## exactly why nothing covered it.
##
## ## The bug this replaces
##
## The lobby ran off the bottom of the window: on a ~1920x1000 client area
## the chat panel was clipped mid-panel, GAME SETTINGS crossed the bottom
## edge and the SANDBOX panel was not on screen at all, with no scrollbar
## to reach any of it (#91). Three causes, and all three had to go:
##
## 1. Every minimum was a fixed pixel count — 168 of map preview, 96 of
##    chat log, 198 of seat list — so a short window did not give each
##    panel a smaller share, it gave the last panel nothing.
## 2. Nothing scrolled. A `VBoxContainer` handed less height than its
##    children's combined minimum does not shrink them and does not
##    scroll: it overflows, silently.
## 3. **The design space was SMALLER than the window, and did not grow
##    with it.** This is the one that made the other two bite at a
##    resolution with obvious room on screen. The lobby was scaled by the
##    HUD's own factor, and `HudLayout.scale_for` divides by a 720-tall
##    reference — so a 1000-tall window was laid out against 720 design
##    pixels, the same 720 a 1280x720 window gets. Making the window
##    bigger bought the lobby not one extra pixel to fit in.
##
## ## So the lobby scales against its OWN height, not the HUD's
##
## The HUD is an overlay on a world the player is reading THROUGH, and
## `HudLayout.REFERENCE` (1280x720) is the window its hand-placed
## coordinates were tuned against. The lobby is a full-screen document
## with a known amount of content in it, and the useful question is not
## "how much bigger than the reference window is this" but "does the
## content fit". Dividing by `DESIGN_HEIGHT` instead answers that one:
## a window at least that tall lays the lobby out at its natural height
## and scales it up to fill, so every panel is on screen and the extra
## pixels go to making it readable. A shorter window hits `MIN_SCALE`,
## the content genuinely does not fit, and the root `ScrollContainer`
## (client.gd's `_lobby_scroll`) is what keeps it reachable.
##
## Scale and fit are still two mechanisms doing different jobs, exactly as
## `hud_layout.gd`'s header says — this file just aims the scale at the
## right reference.

## The height the lobby's own content wants, in design units, margins
## included.
##
## Not a taste: `tests/test_lobby_layout.gd` builds the REAL lobby, in a
## real tree so its fonts and containers are the shipping ones, and fails
## if the combined minimum height of what it built exceeds this. So adding
## two more rows to GAME SETTINGS goes red here rather than off the bottom
## of somebody's screen — which is the whole failure mode this file exists
## for, and the one no number could see before.
const DESIGN_HEIGHT := 1000.0

## The width half of the reference stays the HUD's, because the horizontal
## layout below (a `1fr 400px` grid, per the reference design) was drawn
## against it and never overflowed — the reported bug is vertical.
const REFERENCE_WIDTH := HudLayout.REFERENCE.x

## One seat row plus its separation — how tall the seat list's scroll
## window is sized against, so "how many rows show before it scrolls" is
## one number rather than a viewport height nobody chose on purpose.
const SEAT_ROW_HEIGHT := 44.0
## The most seat rows the list shows before scrolling on its own. A lobby
## seats up to twenty (D-018); showing all of them would push chat and the
## actions row off the bottom, which is this whole issue in miniature.
const SEAT_ROWS_VISIBLE := 4.5

## The margin between the lobby's edge panels and the window's own edge,
## as a fraction of the design rect with a floor and a ceiling. The
## fractions are exactly the 40x24 the constant used to be, at the
## 1280x720 window it was chosen on — so nothing moves at that size and
## everything else scales.
const MARGIN_FRACTION := Vector2(0.031, 0.033)
const MARGIN_MIN := Vector2(16.0, 10.0)
const MARGIN_MAX := Vector2(48.0, 32.0)

## The right-hand column (map preview + generation settings + sandbox).
##
## The reference design's `grid-template-columns:1fr 400px`, made
## proportional: a wider window still gives most of its extra width to the
## seat list and chat rather than stretching a terrain preview into
## something blurrier, which is what the ceiling is for. The floor is not
## cosmetic — the settings rows carry a 140px label plus a control, so a
## column narrower than this is pushed back out by its own content and the
## LEFT column pays for it.
const RIGHT_COLUMN_FRACTION := 0.28
const RIGHT_COLUMN_MIN := 360.0
const RIGHT_COLUMN_MAX := 520.0

## The left column's floor: enough for a seat row's name, civ, team and
## kick button to read as one line rather than wrapping.
const LEFT_COLUMN_FRACTION := 0.44
const LEFT_COLUMN_MIN := 420.0
const LEFT_COLUMN_MAX := 620.0

## The help line under the seat list. A minimum WIDTH on an autowrapping
## label is what decides where it wraps, so this is a text measure rather
## than a box — hence its own fraction.
const HELP_WIDTH_FRACTION := 0.47
const HELP_WIDTH_MIN := 380.0
const HELP_WIDTH_MAX := 600.0

## The three fixed heights, made fractional. Each is tuned so that the
## 1280x720 design space (the smallest one this layout is ever handed,
## because `MIN_SCALE` floors the scale there) produces a visibly smaller
## share, and `DESIGN_HEIGHT` reproduces the number that was hardcoded.
const PREVIEW_HEIGHT_FRACTION := 0.175
const PREVIEW_HEIGHT_MIN := 110.0
const PREVIEW_HEIGHT_MAX := 180.0

const BLURB_HEIGHT_FRACTION := 0.035
const BLURB_HEIGHT_MIN := 24.0
const BLURB_HEIGHT_MAX := 40.0

const CHAT_HEIGHT_FRACTION := 0.115
const CHAT_HEIGHT_MIN := 64.0
const CHAT_HEIGHT_MAX := 110.0

const SEAT_LIST_HEIGHT_FRACTION := 0.22
const SEAT_LIST_HEIGHT_MIN := SEAT_ROW_HEIGHT * 3.0
const SEAT_LIST_HEIGHT_MAX := SEAT_ROW_HEIGHT * SEAT_ROWS_VISIBLE


## How much to magnify the lobby for a window of this size.
##
## `override` is the player's explicit HUD scale (D-063), or 0 for
## automatic. It can only make the lobby SMALLER than the fit: a player
## who picked 2.0 because the in-match HUD is hard to read did not ask for
## the lobby's last panel to leave the screen, and the fit is the thing
## this whole file is about.
static func scale_for(viewport: Vector2, override := 0.0) -> float:
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	var fit := clampf(minf(viewport.x / REFERENCE_WIDTH, viewport.y / DESIGN_HEIGHT),
		HudLayout.MIN_SCALE, HudLayout.MAX_SCALE)
	if override > 0.0:
		return minf(override, fit)
	return fit


## The design-space rect the lobby is laid out in — the window divided by
## the scale actually applied to it, the same way `HudLayout.design_size`
## works for the HUD.
static func design_size(viewport: Vector2, override := 0.0) -> Vector2:
	var s := scale_for(viewport, override)
	return Vector2(maxf(viewport.x, 1.0), maxf(viewport.y, 1.0)) / s


static func margin(design: Vector2) -> Vector2:
	return Vector2(
		clampf(design.x * MARGIN_FRACTION.x, MARGIN_MIN.x, MARGIN_MAX.x),
		clampf(design.y * MARGIN_FRACTION.y, MARGIN_MIN.y, MARGIN_MAX.y))


## Where the scrolling page itself sits: the design rect, inset by the
## margin. Everything else the lobby draws is a container inside this.
static func root_rect(design: Vector2) -> Rect2:
	var edge := margin(design)
	return Rect2(edge, Vector2(
		maxf(design.x - edge.x * 2.0, 0.0),
		maxf(design.y - edge.y * 2.0, 0.0)))


static func right_column_width(design: Vector2) -> float:
	return clampf(design.x * RIGHT_COLUMN_FRACTION, RIGHT_COLUMN_MIN, RIGHT_COLUMN_MAX)


static func left_column_width(design: Vector2) -> float:
	return clampf(design.x * LEFT_COLUMN_FRACTION, LEFT_COLUMN_MIN, LEFT_COLUMN_MAX)


static func help_width(design: Vector2) -> float:
	return clampf(design.x * HELP_WIDTH_FRACTION, HELP_WIDTH_MIN, HELP_WIDTH_MAX)


static func map_preview_height(design: Vector2) -> float:
	return clampf(design.y * PREVIEW_HEIGHT_FRACTION, PREVIEW_HEIGHT_MIN, PREVIEW_HEIGHT_MAX)


static func map_blurb_height(design: Vector2) -> float:
	return clampf(design.y * BLURB_HEIGHT_FRACTION, BLURB_HEIGHT_MIN, BLURB_HEIGHT_MAX)


static func chat_log_height(design: Vector2) -> float:
	return clampf(design.y * CHAT_HEIGHT_FRACTION, CHAT_HEIGHT_MIN, CHAT_HEIGHT_MAX)


static func seat_list_height(design: Vector2) -> float:
	return clampf(design.y * SEAT_LIST_HEIGHT_FRACTION,
		SEAT_LIST_HEIGHT_MIN, SEAT_LIST_HEIGHT_MAX)
