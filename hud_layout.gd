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
## `scale_for` divides by exactly that while the window is SMALLER than it,
## so a 16:9 window down to the scale floor comes back to a 1280x720 design
## space and the layout below reproduces the hand-placed coordinates it
## replaces, pixel for pixel. The HUD that was looked at and tuned is the
## HUD you still get; other window shapes are the deviation, and they
## deviate only by where the edges are.
##
## A window LARGER than the reference deliberately does not come back to it
## — magnification is measured against `MAGNIFY_ABOVE`, so the extra pixels
## are battlefield rather than chrome. See `scale_for`; that identity was
## the same statement as "the HUD keeps a constant fraction of the window at
## every size", which is #90.

const REFERENCE := Vector2(1280.0, 720.0)

## Clamped, not unbounded. Below the floor the text stops being legible,
## and above the ceiling a 4K screen gets a HUD that eats the map — the
## point of a big monitor is seeing more of the world, not a bigger
## selection panel.
##
## Raised from 0.75: reported as genuinely hard to read at the old floor —
## a window narrower than the reference (common; Godot's own default
## project window is 1152x648, already below 1280x720) landed on exactly
## that floor, not some rare edge case. `min_window_size` follows this
## constant, so raising it also raises the smallest window this HUD will
## let itself be squeezed into.
const MIN_SCALE := 0.9
const MAX_SCALE := 2.0

## The window size above which the HUD starts being MAGNIFIED — see
## `scale_for`. 1920x1080, the most common desktop resolution there is:
## below it a player gets the HUD at the pixel size it was designed at, and
## only a genuinely bigger monitor than the common one buys magnification.
const MAGNIFY_ABOVE := Vector2(1920.0, 1080.0)

const MARGIN := 12.0
const BAR_HEIGHT := 38.0

## PANEL_HEIGHT is declared further down, after BUILD_ACTION_ROWS — see
## there. It genuinely depends on that (and on ACTION_BUTTON/ACTION_GAP/
## PANEL_PAD below), and GDScript resolves top-level consts in declaration
## order, so it cannot live up here next to the rest of the panel's
## "top of file" geometry without forward-referencing something that
## doesn't exist yet.

## Inner geometry, relative to the panel's top-left corner.
const PANEL_PAD := 12.0
const TITLE_Y := 12.0
const DETAIL_Y := 40.0
const HEALTH_Y := 66.0
const PROGRESS_CAPTION_Y := 82.0
const PROGRESS_Y := 102.0
const QUEUE_CAPTION_Y := 120.0
const QUEUE_SWATCH_Y := 120.0
const QUEUE_SWATCH_PITCH := 20.0

## The title column: who/what is selected, and (for a building) its health.
const TITLE_COLUMN_WIDTH := 172.0

## The chip strip sits between the title column and the actions column —
## see `chip_strip_rect`. Chips are square-ish cards, not a fixed count:
## how many fit is a function of the window, which is why it is computed
## rather than assumed.
const CHIP_SIZE := Vector2(116.0, 58.0)
const CHIP_GAP := 6.0
## Above this many squads, per-squad chips stop being legible as
## individuals and the panel collapses to one chip per ARCHETYPE instead
## (see the reference design's 20-squad state) — counted, not guessed, so
## the threshold lives beside the geometry it is chosen to fit.
const CHIP_COLLAPSE_THRESHOLD := 8

const ACTION_GAP := Vector2(8.0, 6.0)
const ACTION_COLUMNS := 3
const ACTIONS_Y := 8.0

## Playtest fix: the actions column was a small FIXED width (~448px on the
## 1280-wide reference window, ~35% of it) regardless of how much room the
## panel actually had — reported as "the command section is still really
## squished" once build buttons started carrying two-line cost labels.
## Sized to roughly HALF the reference window's width instead of a
## hand-picked button size. This is a deliberate partial departure from
## the "never has to reflow" design the column used to lean on entirely:
## the GRID still doesn't reflow (ACTION_COLUMNS stays fixed at 3, and
## `action_slot`/`build_slot`'s index math is unchanged) — the BUTTONS
## themselves just got wider to fill the space, which needed no reflow
## logic at all.
const ACTIONS_COLUMN_TARGET_WIDTH := REFERENCE.x * 0.5
const ACTION_BUTTON := Vector2(
	(ACTIONS_COLUMN_TARGET_WIDTH - PANEL_PAD * 2.0
		- ACTION_GAP.x * float(ACTION_COLUMNS - 1)) / float(ACTION_COLUMNS),
	38.0)
const ACTIONS_COLUMN_WIDTH := ACTION_BUTTON.x * float(ACTION_COLUMNS) \
	+ ACTION_GAP.x * float(ACTION_COLUMNS - 1)

## The actions column is two SEGMENTS stacked vertically, not one shared
## grid: formation/behaviour on top (`action_slot`), building on the
## bottom (`build_slot`), with a divider and its own caption between them.
## Building used to sit in the same grid as Stop/Gather, ordered after the
## formation buttons by construction — which worked, but on request reads
## worse than a real visual break: "Build Barracks" and "Stop" are not the
## same KIND of order, and a player scanning quickly for one wants to know
## which half of the column to even look at.
##
## `ACTION_CONTROL_ROWS` caps the top segment before the divider begins —
## generous for what actually fills it (three formations + Stop + Gather
## is five, fitting in two rows of three with room to spare), and if a
## selection ever offered more than that, the excess would simply not
## show — the same silent cap the single shared grid always had.
const ACTION_CONTROL_ROWS := 2
const BUILD_DIVIDER_Y := ACTIONS_Y \
	+ float(ACTION_CONTROL_ROWS) * (ACTION_BUTTON.y + ACTION_GAP.y) + 4.0
const BUILD_CAPTION_Y := BUILD_DIVIDER_Y + 8.0
const BUILD_ACTIONS_Y := BUILD_CAPTION_Y + 18.0

## How many rows the build segment's own pooled buttons (client.gd's
## `_build_action_buttons`) are sized for — `PANEL_HEIGHT` is derived from
## this, not the other way around, so the two cannot drift apart the way
## PANEL_HEIGHT drifted from the true 2-row height before this fix. The
## build menu is tiered by category now (BuildingDef.category), so the
## worst case in one screen is one category's defs plus a Back button —
## currently 6 (5 defensive + Back) — with a full row of slack on top.
const BUILD_ACTION_ROWS := 3

## The command panel: a WIDE bar spanning (almost) the window, not a tall
## corner card. Reworked from a 430x300 corner panel to match the chosen
## reference design ("chips ... in the live view") — a selection reads as
## one strip: who is selected, what they are made of (as chips), and what
## you can do with them, left to right rather than stacked top to bottom.
##
## Tall enough for the actions column's two stacked segments: formation/
## behaviour (`ACTION_CONTROL_ROWS`) and, below the divider, build
## (`BUILD_ACTION_ROWS`).
##
## Playtest fix: this used to be a hand-picked 176 that only ever properly
## fit ONE row of build buttons — the divider math already put a second
## row's bottom edge past it. Invisible while the roster fit one row of
## three, and it did until D-076 added five wall-family defs; computed
## from `BUILD_ACTION_ROWS` now so the two cannot drift apart the same way
## again.
const PANEL_HEIGHT := BUILD_ACTIONS_Y + float(BUILD_ACTION_ROWS) * ACTION_BUTTON.y \
	+ float(BUILD_ACTION_ROWS - 1) * ACTION_GAP.y + PANEL_PAD

## One resource readout every this many pixels, across the top bar.
const RESOURCE_PITCH := 168.0
const RESOURCE_X := 16.0

## The Menu button, at the right end of the top bar. Its own slot rather
## than a floating button, so the readouts to its left can be told where
## they must stop.
const MENU_BUTTON := Vector2(84.0, 28.0)

## The nav ring: the compass dial and the minimap MERGED into one widget,
## top-right under the bar — the reference design's chosen synthesis
## ("compass on the minimap ring"), replacing what used to be two unrelated
## widgets in two different corners.
##
## The minimap is visually CROPPED to the ring's circle
## (`shaders/circular_crop.gdshader`) — a genuine crop (pixels outside the
## circle are hidden, at the map's own unchanged scale), not a SQUASH
## (stretching a non-square rectangle to fill a circle, which would
## reintroduce the exact distortion this project already spent an
## afternoon fixing once: a square world stretched into a 2:1 box read
## distances wrong). The trade a crop makes instead is losing whatever
## map content falls outside the circle from view — accepted deliberately,
## on request, over the alternative of a rectangular minimap poking past
## its own frame.
##
## Sized around the minimap's SHORTER dimension, not its diagonal: a ring
## that circumscribes the whole rectangle (rim touching the far corners)
## works out almost exactly the size of the rectangle's own bounding
## circle, and a crop at that radius clips almost nothing — the ring
## LOOKED like a frame but the crop inside it was a no-op. Sizing from the
## shorter side instead gives a ring that visibly crops the longer side's
## overflow, the standard "cover crop" a circular photo avatar uses.
const RING_MIN_SIZE := 172.0
## Also the width of the ring's visible coloured border band — see
## `ring_crop_radius`.
const RING_PADDING := 17.0


## The radius, from the ring's own centre, the minimap is visually CROPPED
## to (see `shaders/circular_crop.gdshader`) — the inner edge of the
## coloured border band, so the map and its frame meet with no gap and no
## overlap.
static func ring_crop_radius(ring_diameter: float) -> float:
	return ring_diameter * 0.5 - 1.0 - RING_PADDING


## How much to magnify the HUD for a window of this size.
##
## `min` of the two ratios rather than either alone, in BOTH branches below:
## scaling by width on a short window would push the selection panel off the
## bottom, which is a worse failure than a HUD that is slightly small.
##
## ## Two ratios, because shrinking and magnifying answer different questions
##
## Below `REFERENCE` the HUD must SHRINK to keep fitting — the window is
## smaller than the layout below assumes, and the alternative is the bar and
## the wide command panel walking off their own edges. That is a fit
## question, and it is measured against `REFERENCE` (floored at `MIN_SCALE`,
## which `min_window_size` then turns back into real pixels).
##
## Above it, nothing needs to fit any more and the question becomes whether
## a bigger window should buy more BATTLEFIELD or a bigger HUD. This used to
## be one linear ratio against `REFERENCE` for both, and linear magnification
## means every element keeps a CONSTANT FRACTION of the window at every
## resolution: the command panel is 36.7% of the reference's height by
## construction (see `PANEL_HEIGHT`) and was still 36.7% at 1920x1080 and at
## 2560x1440. Reported from playtest #30 as a HUD that dominates the screen
## at 1080p (#90) — correctly: a player who bought a bigger window got no
## more of the world, only bigger chrome.
##
## So magnification is measured against `MAGNIFY_ABOVE` instead. Up to
## 1920x1080 the HUD is drawn at exactly the pixel size it was designed at
## and every pixel the window gains is battlefield; past that it grows again,
## which is the "same PHYSICAL size on a big monitor" intent this file was
## written with — that intent is right about a 4K screen and was wrong about
## the step from 720p to 1080p, where it is the same monitor with a bigger
## window on it. The panel's share of the window falls 36.7% -> 24.4% at
## 1080p and holds there up to `MAX_SCALE`.
##
## The curve is <= the old one at every window size, which is why this
## needed no re-check of the anchoring above: nothing can overflow anywhere
## it used to fit. What it does risk is legibility, and the two answers to
## that are both already here — `MIN_SCALE`'s floor, and the player's own
## HUD scale slider (D-063), which overrides this entirely.
static func scale_for(viewport: Vector2) -> float:
	if viewport.x <= 0.0 or viewport.y <= 0.0:
		return 1.0
	var fit := minf(viewport.x / REFERENCE.x, viewport.y / REFERENCE.y)
	if fit < 1.0:
		return maxf(fit, MIN_SCALE)
	return clampf(minf(viewport.x / MAGNIFY_ABOVE.x, viewport.y / MAGNIFY_ABOVE.y),
		1.0, MAX_SCALE)


## The smallest real window this HUD should ever be asked to fit.
##
## `scale_for` stops shrinking the HUD once it hits `MIN_SCALE` — below
## that floor the HUD stays the same size while the WINDOW keeps getting
## smaller, so the resource bar and the wide command panel start walking
## off their own edges rather than merely getting small. This is that
## floor turned back into real pixels, meant to be set as the native
## window's `min_size` so a player cannot resize past a point the layout
## math above already assumes cannot happen.
static func min_window_size() -> Vector2i:
	return Vector2i(REFERENCE * MIN_SCALE)


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
	var status := Rect2(minf(status_left, status_right), (BAR_HEIGHT - 24.0) * 0.5,
		maxf(status_right - status_left, 0.0), 24.0)

	# Top-right, below the bar. Sized around the minimap's SHORTER
	# dimension — see the const's doc comment above for why: circumscribing
	# the diagonal instead sizes the ring almost exactly to the rectangle's
	# own bounding circle, and the crop this ring frames then clips nearly
	# nothing. Clamped so it cannot ride up under the bar or off the left
	# edge on a very narrow window.
	var ring_diameter := maxf(RING_MIN_SIZE,
		minf(minimap_size.x, minimap_size.y) + RING_PADDING * 2.0)
	var ring := Rect2(
		Vector2(maxf(width - MARGIN - ring_diameter, MARGIN), BAR_HEIGHT + MARGIN),
		Vector2(ring_diameter, ring_diameter))

	# Centred inside the ring, keeping its own aspect ratio.
	var minimap := Rect2(ring.position + (ring.size - minimap_size) * 0.5, minimap_size)

	# Centred under the bar, where a refusal is actually read. Spans the
	# full width and centres its text, rather than being placed at the x
	# that happened to look centred on one window.
	var notice := Rect2(0.0, BAR_HEIGHT + 10.0, width, 22.0)

	# The wide command bar. Bottom-left, full width, clamped above the ring
	# so a very short window cannot stack the two widgets on top of each
	# other the way the bar and the old corner panel once could.
	var panel := Rect2(
		Vector2(MARGIN, maxf(height - PANEL_HEIGHT - MARGIN,
			ring.position.y + ring.size.y + MARGIN)),
		Vector2(maxf(width - MARGIN * 2.0, 0.0), PANEL_HEIGHT))

	return {
		"resource_bar": resource_bar,
		"status": status,
		"menu_button": menu_button,
		"ring": ring,
		"notice": notice,
		"panel": panel,
		"minimap": minimap,
	}


## The resource swatches: vertically centred in the bar, not at a fixed Y
## tuned for one font size — that stopped lining up with the label text
## the moment the label's own font size changed and nothing here followed.
const RESOURCE_SWATCH_SIZE := 13.0


## Where the i'th resource swatch sits in the top bar.
static func resource_slot(index: int) -> Vector2:
	return Vector2(RESOURCE_X + float(index) * RESOURCE_PITCH,
		(BAR_HEIGHT - RESOURCE_SWATCH_SIZE) * 0.5)


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


## The title column, at the panel's left edge.
static func title_column_rect(panel: Rect2) -> Rect2:
	return Rect2(panel.position, Vector2(TITLE_COLUMN_WIDTH, panel.size.y))


## The actions column (formation + command buttons), at the panel's right
## edge — the one sub-region whose width is fixed regardless of window
## size, so the button grid never has to reflow.
static func actions_column_rect(panel: Rect2) -> Rect2:
	var w := minf(ACTIONS_COLUMN_WIDTH + PANEL_PAD * 2.0, panel.size.x)
	return Rect2(Vector2(panel.position.x + panel.size.x - w, panel.position.y),
		Vector2(w, panel.size.y))


## What is left in the middle, for chips — between the title column and the
## actions column. Can come out zero-width on a very narrow window; callers
## must cope with that (see `chip_columns`), not assume it is positive.
static func chip_strip_rect(panel: Rect2) -> Rect2:
	var title := title_column_rect(panel)
	var actions := actions_column_rect(panel)
	var left := title.position.x + title.size.x + PANEL_PAD
	var right := actions.position.x - PANEL_PAD
	return Rect2(Vector2(left, panel.position.y),
		Vector2(maxf(right - left, 0.0), panel.size.y))


## How many chips fit across a strip of this width. At least one, even on a
## strip too narrow to truly fit one — better an overflowing chip than a
## division by a column count of zero silently hiding the whole selection.
static func chip_columns(strip_width: float) -> int:
	return maxi(1, int((strip_width + CHIP_GAP) / (CHIP_SIZE.x + CHIP_GAP)))


## Where the i'th chip sits, relative to the strip's own top-left corner.
static func chip_slot(index: int, columns: int) -> Vector2:
	var row := index / columns
	var col := index % columns
	return Vector2(float(col) * (CHIP_SIZE.x + CHIP_GAP),
		float(row) * (CHIP_SIZE.y + CHIP_GAP))


## Where the i'th FORMATION/BEHAVIOUR button sits — the top segment,
## relative to the ACTIONS COLUMN's corner (not the panel's — see
## `actions_column_rect`).
static func action_slot(index: int) -> Vector2:
	return Vector2(
		PANEL_PAD + float(index % ACTION_COLUMNS) * (ACTION_BUTTON.x + ACTION_GAP.x),
		ACTIONS_Y + float(index / ACTION_COLUMNS) * (ACTION_BUTTON.y + ACTION_GAP.y))


## Where the i'th BUILD button sits — the segment below the divider (see
## `BUILD_DIVIDER_Y`'s doc comment for why this is a separate segment
## rather than a continuation of `action_slot`'s grid).
static func build_slot(index: int) -> Vector2:
	return Vector2(
		PANEL_PAD + float(index % ACTION_COLUMNS) * (ACTION_BUTTON.x + ACTION_GAP.x),
		BUILD_ACTIONS_Y + float(index / ACTION_COLUMNS) * (ACTION_BUTTON.y + ACTION_GAP.y))


## The divider's own rect, relative to the actions column's corner — a
## thin horizontal rule spanning the column's width, the same way
## `chip_strip_rect`'s neighbours are computed relative to a shared corner
## rather than each carrying its own absolute math.
static func build_divider_rect() -> Rect2:
	return Rect2(Vector2(PANEL_PAD, BUILD_DIVIDER_Y), Vector2(ACTIONS_COLUMN_WIDTH, 1.0))
