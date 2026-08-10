class_name HudLayout
extends RefCounted

## Where the HUD's pieces go, for a window of any size.
##
## All-static and pure, for the reason `render_cull.gd` and
## `selection_pick.gd` are: the client cannot be tested headless (D-014),
## but "does the resource bar reach the right-hand edge" is arithmetic and
## does not need a GPU to answer.
##
## ## The bug this replaces
##
## Every HUD element was placed at a literal pixel coordinate written
## against an implied 1280x720 window — a resource bar 1280 wide, a
## selection panel at y=408 because 408+300 is about 720. Nothing consulted
## the viewport. Full-screened at 1920x1080 the bar therefore stopped
## two-thirds of the way across, and the panel and minimap floated in the
## middle of the screen with a band of nothing beneath them. Reported as
## the HUD not scaling with the window, which is exactly what it did.
##
## ## Two mechanisms, and they do different jobs
##
## 1. **Scale** (`scale_for`) makes the HUD the same PHYSICAL size on a big
##    monitor as on a small one. Applied as the CanvasLayer's transform, so
##    fonts, borders and button sizes all come along — which is why the
##    layout below can go on thinking in one fixed set of units.
## 2. **Anchoring** (`compute`) makes it FIT. Scale alone cannot: a
##    21:9 monitor scaled to fill vertically still leaves the bar short,
##    because the shape of the window changed and not just its size.
##
## Both are needed, and the first without the second is the bug above
## wearing a bigger font.
##
## ## The reference window is 1280x720 on purpose
##
## `scale_for` divides by exactly that, so on any 16:9 window the design
## space comes back to 1280x720 and the layout below reproduces the
## hand-placed coordinates it replaces, pixel for pixel. The HUD that was
## looked at and tuned is the HUD you still get; other window shapes are
## the deviation, and they deviate only by where the edges are.

const REFERENCE := Vector2(1280.0, 720.0)

## Clamped, not unbounded. Below the floor the text stops being legible,
## and above the ceiling a 4K screen gets a HUD that eats the map — the
## point of a big monitor is seeing more of the world, not a bigger
## selection panel.
const MIN_SCALE := 0.75
const MAX_SCALE := 2.0

const MARGIN := 12.0
const BAR_HEIGHT := 34.0
const PANEL_SIZE := Vector2(430.0, 300.0)

## Inner geometry of the selection panel, relative to its top-left corner.
## Here rather than in the client so that the panel's contents move with
## the panel by construction, instead of by two lists of numbers that have
## to be kept agreeing.
const PANEL_PAD := 12.0
const TITLE_Y := 8.0
const DETAIL_Y := 32.0
const HEALTH_Y := 56.0
const PROGRESS_CAPTION_Y := 70.0
const PROGRESS_Y := 88.0
const QUEUE_CAPTION_Y := 104.0
const QUEUE_SWATCH_Y := 126.0
const QUEUE_SWATCH_PITCH := 20.0
const ACTIONS_Y := 152.0
const ACTION_BUTTON := Vector2(128.0, 34.0)
const ACTION_GAP := Vector2(8.0, 6.0)
const ACTION_COLUMNS := 3

## One resource readout every this many pixels, across the top bar.
const RESOURCE_PITCH := 150.0
const RESOURCE_X := 16.0

## The Menu button, at the right end of the top bar. Its own slot rather
## than a floating button, so the readouts to its left can be told where
## they must stop.
const MENU_BUTTON := Vector2(76.0, 24.0)

## The compass dial, under the top bar on the RIGHT — opposite the
## minimap, which owns the left. Both are navigation, and putting them in
## the same corner would mean covering one with the other on a short
## window.
const COMPASS_SIZE := 68.0


## How much to magnify the HUD for a window of this size.
##
## `min` of the two ratios rather than either alone: scaling by width on a
## short window would push the selection panel off the bottom, which is a
## worse failure than a HUD that is slightly small.
static func scale_for(viewport: Vector2) -> float:
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	return clampf(minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y),
		MIN_SCALE, MAX_SCALE)


## The design-space size a scaled HUD has to fill.
##
## On a 16:9 window this is exactly REFERENCE. On anything else it is the
## real shape of the window in HUD units, which is what `compute` anchors
## against — the whole reason the bar reaches the edge of an ultrawide.
static func design_size(viewport: Vector2) -> Vector2:
	var s := scale_for(viewport)
	return Vector2(maxf(viewport.x, 1.0), maxf(viewport.y, 1.0)) / s


## Every positioned rect, in design space. `minimap_size` is passed in
## rather than computed because the minimap is shaped by the MAP's
## proportions, which the HUD does not know until a match starts.
static func compute(design: Vector2, minimap_size: Vector2) -> Dictionary:
	var width := maxf(design.x, 1.0)
	var height := maxf(design.y, 1.0)

	# Full width, always. This is the element the bug was reported against.
	var resource_bar := Rect2(0.0, 0.0, width, BAR_HEIGHT)

	# The Menu button owns the right end of the bar; the status readout
	# gets what is left between the resources and it.
	var menu_button := Rect2(
		Vector2(maxf(width - MARGIN - MENU_BUTTON.x, 0.0),
			(BAR_HEIGHT - MENU_BUTTON.y) * 0.5),
		MENU_BUTTON)

	# Right-aligned in the top bar, past the last resource readout. It was
	# at a fixed x=700, which on a narrow window sat on top of the stone
	# count and on a wide one left a lake of empty bar to its right.
	var status_left := RESOURCE_X + RESOURCE_PITCH * 4.0
	var status_right := menu_button.position.x - MARGIN
	var status := Rect2(minf(status_left, status_right), 6.0,
		maxf(status_right - status_left, 0.0), 22.0)

	# Top-right, below the bar. Clamped so it cannot ride up under the bar
	# or off the left edge on a very narrow window.
	var compass := Rect2(
		Vector2(maxf(width - MARGIN - COMPASS_SIZE, MARGIN), BAR_HEIGHT + MARGIN),
		Vector2(COMPASS_SIZE, COMPASS_SIZE))

	# Centred under the bar, where a refusal is actually read. Spans the
	# full width and centres its text, rather than being placed at the x
	# that happened to look centred on one window.
	var notice := Rect2(0.0, BAR_HEIGHT + 10.0, width, 22.0)

	# Bottom-left, clamped so it can never climb under the resource bar on
	# a very short window.
	var panel := Rect2(
		Vector2(MARGIN, maxf(height - PANEL_SIZE.y - MARGIN, BAR_HEIGHT + MARGIN)),
		PANEL_SIZE)

	# Directly above the panel, sharing its left edge. Clamped below the
	# resource bar for the same reason.
	var minimap := Rect2(
		Vector2(MARGIN, maxf(panel.position.y - MARGIN - minimap_size.y,
			BAR_HEIGHT + MARGIN)),
		minimap_size)

	return {
		"resource_bar": resource_bar,
		"status": status,
		"menu_button": menu_button,
		"compass": compass,
		"notice": notice,
		"panel": panel,
		"minimap": minimap,
	}


## Where the i'th resource swatch sits in the top bar.
static func resource_slot(index: int) -> Vector2:
	return Vector2(RESOURCE_X + float(index) * RESOURCE_PITCH, 9.0)


## Where cardinal `index` (0=N, 1=E, 2=S, 3=W) sits on the compass dial,
## as an offset from its centre, for a camera turned `yaw` radians.
##
## Here rather than inline in the client because it is the one piece of
## this HUD whose geometry is not obvious, and getting it backwards
## produces a compass that looks entirely plausible and lies.
##
## The DIAL turns and the needle does not. A compass answers "which way am
## I facing": you keep facing up the screen, and the world's north swings
## around you. Hence the minus on yaw — turn the camera one way and the
## letters go the other. A ring of fixed letters with a swinging needle is
## a magnetic compass, which answers a different question.
##
## Screen y grows downward, so "up the screen" is -y — that is the minus
## on the cosine, and it is why this is worth testing rather than
## eyeballing.
static func compass_offset(yaw: float, index: int, radius: float) -> Vector2:
	var angle := -yaw + float(index) * (TAU / 4.0)
	return Vector2(sin(angle), -cos(angle)) * radius


# --- readouts ---------------------------------------------------------
#
# Text, not geometry, and here rather than in the client for the reason
# everything else in this file is: these are pure functions with real edge
# cases (an hour boundary, an unknown cap, being over the cap) and the
# client they are read from cannot be tested headless (D-014).


## The match clock, as h:mm:ss past an hour and m:ss below it.
##
## Zero-padded from the left only where it has to be: "9:07" reads as nine
## minutes, "1:09:07" as over an hour. A bare seconds count would be
## useless at the 1–2 hour match length this game is aiming at (D-056).
static func clock_text(seconds: float) -> String:
	var total := int(maxf(seconds, 0.0))
	var hours := total / 3600
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%d:%02d" % [minutes, secs]


## "12/40 squads", or "12 squads" when the server never stated a cap.
##
## The no-cap case is real: a client welcomed by a server too old to send
## one gets 0, and printing "12/0" would read as a bug in the cap rather
## than as an absent number.
static func squad_count_text(living: int, cap: int) -> String:
	if cap <= 0:
		return "%d squads" % living
	return "%d/%d squads" % [living, cap]


## Where the i'th action button sits, relative to the panel's corner.
static func action_slot(index: int) -> Vector2:
	return Vector2(
		PANEL_PAD + float(index % ACTION_COLUMNS) * (ACTION_BUTTON.x + ACTION_GAP.x),
		ACTIONS_Y + float(index / ACTION_COLUMNS) * (ACTION_BUTTON.y + ACTION_GAP.y))
