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

## PANEL_HEIGHT is declared further down, after the three columns it is
## the tallest of — see there. GDScript resolves top-level consts in
## declaration order, so it cannot live up here next to the rest of the
## panel's "top of file" geometry without forward-referencing something
## that doesn't exist yet.

## Inner geometry, relative to the panel's top-left corner.
const PANEL_PAD := 12.0
## The panel's own vertical padding, smaller than the horizontal one: at 73
## units tall (see `PANEL_HEIGHT`) a 12-unit skirt top and bottom is a third
## of the bar. Horizontal padding is not under the same pressure and stays.
const PANEL_PAD_Y := 7.0

## ## The selection (leftmost) column, as a table
##
## Offsets from the column's own corner, x AND y, rather than a column of
## Y values with the x implied by the caller. It became a table when the
## panel was halved to 73 units (playtest #30's "50% shorter"): six things
## stacked in one 148-wide strip needed 146 units of height, and the same
## six in TWO sub-columns need 68. Nothing was dropped — the readouts moved
## sideways rather than going away.
##
## Left sub-column: what is selected, and how much of it is left.
const TITLE_AT := Vector2(PANEL_PAD, 6.0)
const DETAIL_AT := Vector2(PANEL_PAD, 28.0)
const HEALTH_AT := Vector2(PANEL_PAD, 50.0)
const TITLE_TEXT_WIDTH := 148.0

## Right sub-column: what it is doing, and what is queued behind it. Only a
## BUILDING ever fills these, which is why they are the half that moved.
const PROGRESS_COLUMN_X := PANEL_PAD + TITLE_TEXT_WIDTH + 8.0
const PROGRESS_CAPTION_AT := Vector2(PROGRESS_COLUMN_X, 6.0)
const PROGRESS_AT := Vector2(PROGRESS_COLUMN_X, 24.0)
const QUEUE_CAPTION_AT := Vector2(PROGRESS_COLUMN_X, 32.0)
const QUEUE_SWATCH_AT := Vector2(PROGRESS_COLUMN_X, 48.0)
const QUEUE_SWATCH_PITCH := 18.0
## Here rather than in the client because the swatch row is the LOWEST
## thing in this column, so its size is a term in `TITLE_COLUMN_HEIGHT` and
## therefore in the panel's own height.
const QUEUE_SWATCH_SIZE := 14.0
## Wide enough for the longest readout it carries — "Training Heavy
## Infantry — 12s" — because a Label does not clip unless told to, and the
## first render of this column had that caption running out of its own
## sub-column and across the chip strip.
const PROGRESS_BAR_WIDTH := 168.0

## The selection column: who/what is selected, its health, and (for a
## building) what it is producing. Wider than the 172 it was, because the
## height it gave up had to go somewhere and width is what this panel has
## most of — see the table above.
const TITLE_COLUMN_WIDTH := PROGRESS_COLUMN_X + PROGRESS_BAR_WIDTH + PANEL_PAD

## What the selection column has to be tall enough for: its lowest row, the
## production queue's swatches.
const TITLE_COLUMN_HEIGHT := QUEUE_SWATCH_AT.y + QUEUE_SWATCH_SIZE + PANEL_PAD_Y

## The chip strip sits between the title column and the commands column —
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

## How many rows of chips the panel is sized to hold. ONE, at the halved
## height — a second row is 64 units and the whole bar is 73. It is a number
## here rather than "whatever fits" because it is a term in `PANEL_HEIGHT`;
## `chip_rows` then reports what a real strip actually holds.
##
## One row is why `chip_strip_rect` takes over the build column when the
## selection cannot build: a barracks trains SIX units and those tiles are
## the train controls themselves, so a strip that shows four of them hides
## two orders rather than two labels.
const CHIP_ROWS := 1
## The width the strip is guaranteed, before the action columns take their
## share — two chips, so a full strip can always show a tile beside its
## pager. See `actions_column_width`.
const CHIP_STRIP_MIN_WIDTH := CHIP_SIZE.x * 2.0 + CHIP_GAP
const CHIP_STRIP_HEIGHT := float(CHIP_ROWS) * CHIP_SIZE.y \
	+ float(CHIP_ROWS - 1) * CHIP_GAP + PANEL_PAD_Y

## ## The two ACTION columns
##
## Formation/behaviour ("commands") and building are two grids SIDE BY
## SIDE, in the middle and at the right of the panel. They used to be two
## segments STACKED vertically inside one right-hand column, with a
## horizontal divider between them — which is why the panel was 264 units
## tall and ate a third of the window at every resolution: its height was
## the SUM of two grids plus a title column, when it only ever had to be
## the tallest of the three. Requested from playtest #30 after the scale
## fix (D-20260817-hud-scale-stops-at-1080p) as "even less room".
##
## The visual break the stacked segments were introduced for is kept and
## costs no height now: a vertical rule at each column's left edge
## (`column_rule_rect`) says "these are two different KINDS of order"
## exactly as the horizontal divider did.
const ACTION_GAP := Vector2(8.0, 6.0)
const ACTION_COLUMNS := 3
## Two rows in EACH column, where it was two stacked segments of two and
## three. What actually fills them, counted rather than assumed: the
## commands grid holds three formations plus Stop plus Gather, five of six;
## the build grid's worst single screen is a category's own group picker,
## four of six (Back, two groups, plus the one ungrouped defensive def).
## So both keep genuine slack.
const ACTION_ROWS := 2
## 26, not the 38 a button was: two rows of 38 plus their gap is 82 units
## and the whole bar is 73 now. What 12 units of button height cost is the
## SECOND LINE of a label — the cost that used to sit under a building's
## name moved onto the same line (`Client._build_action_for`), and the
## button clips with an ellipsis and carries the full text as its tooltip
## rather than overflowing its neighbour.
const ACTION_BUTTON_HEIGHT := 26.0

## The grid starts at the column's top: there is no room at 73 units for a
## per-column caption, so the vertical rules and the buttons' own words are
## what tell the two grids apart. Restoring the captions costs 18 units of
## the bar's height, which is the trade that was made.
const ACTIONS_Y := PANEL_PAD_Y

## Button width is a function of the PANEL now (see `action_button_size`),
## not a constant: with two grids side by side there is no one width that
## is generous at 1920 and still fits at 1280. The grid itself still does
## not reflow — `ACTION_COLUMNS` is fixed at 3 and `action_slot`'s index
## math is unchanged — only the buttons breathe, which is the same trade
## the single column already made when it was widened after a playtest.
##
## The ceiling is what a button measured before this change, so a panel
## wide enough stops growing them rather than sprawling.
##
## The floor is a real trade, not a guess at legibility: every unit the
## floor takes from a button goes to the chip strip, and the strip is where
## a BUILDING's train tiles live (`Client._show_train_chips`) — the one
## thing in this panel that becomes UNREACHABLE rather than merely cramped
## if it does not fit. At 96 the smallest window this HUD allows still
## seats every shipped building's full production list, which
## `test_hud_layout.gd` asserts against the shipped defs rather than
## against a remembered number.
const ACTION_BUTTON_MIN_WIDTH := 96.0
const ACTION_BUTTON_MAX_WIDTH := 200.0
const ACTIONS_COLUMN_SHARE := 0.26

const ACTIONS_COLUMN_MIN_WIDTH := ACTION_BUTTON_MIN_WIDTH * float(ACTION_COLUMNS) \
	+ ACTION_GAP.x * float(ACTION_COLUMNS - 1) + PANEL_PAD * 2.0
const ACTIONS_COLUMN_MAX_WIDTH := ACTION_BUTTON_MAX_WIDTH * float(ACTION_COLUMNS) \
	+ ACTION_GAP.x * float(ACTION_COLUMNS - 1) + PANEL_PAD * 2.0

## What one action column has to be tall enough for: its own grid. Both
## columns are the same shape, so one constant covers them.
const ACTION_GRID_HEIGHT := ACTIONS_Y + float(ACTION_ROWS) * ACTION_BUTTON_HEIGHT \
	+ float(ACTION_ROWS - 1) * ACTION_GAP.y + PANEL_PAD_Y

## The command panel: a WIDE bar spanning (almost) the window, not a tall
## corner card. Reworked from a 430x300 corner panel to match the chosen
## reference design ("chips ... in the live view") — a selection reads as
## one strip: who is selected, what they are made of (as chips), and what
## you can do with them, left to right rather than stacked top to bottom.
##
## **Its height is the TALLEST of its three columns, never their sum** —
## written as that max rather than as the number it currently works out to,
## so a column that grows a row takes the panel with it and a column that
## loses one gives the height back. That is the whole shape of the fix for
## "the selection bar takes up too much room": the stacked layout paid for
## the commands grid AND the build grid AND the title stack, one under the
## other, and only ever needed to pay for the worst of them.
##
## 264 units -> 146 (three columns instead of two stacked grids) -> 72
## (playtest #30's "50% shorter": 26-unit buttons, one row of chips, and the
## selection column's readouts spread across two sub-columns instead of one
## tall stack). Every one of those is a trade written down where it was
## made; none of them removed a control.
const PANEL_HEIGHT := maxf(TITLE_COLUMN_HEIGHT, maxf(CHIP_STRIP_HEIGHT, ACTION_GRID_HEIGHT))

## ## Costs are ICONS, not words
##
## A price is a colour and a number: "150 wood" spends 70 units of a
## 151-unit build button on a word the player already knows from the
## swatch. The swatch IS the icon, and it is the same colour vocabulary the
## top bar, the minimap and the world markers all use (`Client._node_colour`
## resolves every one of them), so it needs no legend beyond the game.
##
## `COST_SLOTS` is four because a unit or building may cost all four
## resources; the shipped worst case is three (a heavy infantry def), and a test
## fails if any def ever exceeds the slots. A CHIP is 116 units wide and
## seats two, with the full price on its tooltip — a chip states a price,
## while the button is the control you actually weigh it on.
## Tight on purpose: the whole point is the room a price gives back, and a
## generously-spaced icon price would give it straight back again. 20 units
## of number is three digits at CAPTION_SIZE, which every shipped cost is.
const COST_SWATCH_SIZE := 8.0
const COST_SWATCH_GAP := 2.0
const COST_NUMBER_WIDTH := 20.0
const COST_ENTRY_GAP := 6.0
const COST_SLOTS := 4
const CHIP_COST_SLOTS := 2
## Where a tile's price sits inside it — the row the "5/5" of a composition
## chip occupies, since a tile shows one or the other and never both.
const CHIP_COST_AT := Vector2(8.0, 30.0)


## How wide one swatch-and-number pair is.
static func cost_entry_width() -> float:
	return COST_SWATCH_SIZE + COST_SWATCH_GAP + COST_NUMBER_WIDTH


## Where the i'th pair starts, within the strip.
static func cost_entry_x(index: int) -> float:
	return float(index) * (cost_entry_width() + COST_ENTRY_GAP)


## How wide a strip of this many pairs is — what a button has to keep clear
## of its own label, and what a chip has to fit.
static func cost_strip_width(entries: int) -> float:
	if entries <= 0:
		return 0.0
	return cost_entry_x(entries - 1) + cost_entry_width()


## One resource readout every this many pixels, across the top bar.
## Down from 168, which was sized for "Food 448". The readout is a swatch
## and a number now — the word was the widest part of it, and four of them
## were spending 300 units of the top bar on saying what four colours
## already say.
const RESOURCE_PITCH := 96.0
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


## How wide ONE action column is, for a panel this wide.
##
## A share of the panel rather than a constant, clamped at both ends: the
## panel is 1256 units wide at the reference window and 1896 at 1080p (the
## design space grows with the window now —
## D-20260817-hud-scale-stops-at-1080p), and two grids side by side cannot
## use one width across that range. Finally capped by what is actually
## left beside the title column, so a degenerately narrow panel shrinks its
## buttons instead of laying its columns on top of its own title.
static func actions_column_width(panel: Rect2) -> float:
	# The chip strip is reserved BEFORE the buttons take their share, not
	# left whatever remains: at one row of chips a strip narrower than two
	# of them cannot page (`Client._chip_window` needs a slot for a tile as
	# well as for the pager), and a strip that cannot page hides orders
	# rather than labels. On a panel too narrow for both, the buttons are
	# what gets cramped — the priority a HUD should have, and the one the
	# "left whatever remains" version had backwards.
	var room := maxf((panel.size.x - TITLE_COLUMN_WIDTH - CHIP_STRIP_MIN_WIDTH
		- PANEL_PAD * 3.0) * 0.5, 0.0)
	return minf(clampf(panel.size.x * ACTIONS_COLUMN_SHARE,
		ACTIONS_COLUMN_MIN_WIDTH, ACTIONS_COLUMN_MAX_WIDTH), room)


## How big one action button is, for a panel this wide — derived FROM the
## column, so a button and the column it sits in cannot disagree.
static func action_button_size(panel: Rect2) -> Vector2:
	var inner := actions_column_width(panel) - PANEL_PAD * 2.0 \
		- ACTION_GAP.x * float(ACTION_COLUMNS - 1)
	return Vector2(maxf(inner / float(ACTION_COLUMNS), 1.0), ACTION_BUTTON_HEIGHT)


## The BUILD column, at the panel's right edge.
##
## Rightmost on request: build is the column a player leaves alone for
## minutes at a time, and the two things they touch constantly — who is
## selected, and what to order it — read left to right in the order they
## are decided.
static func build_column_rect(panel: Rect2) -> Rect2:
	var w := actions_column_width(panel)
	return Rect2(Vector2(panel.position.x + panel.size.x - w, panel.position.y),
		Vector2(w, panel.size.y))


## The COMMANDS column (formation and movement), immediately left of build.
static func commands_column_rect(panel: Rect2) -> Rect2:
	var w := actions_column_width(panel)
	return Rect2(Vector2(build_column_rect(panel).position.x - w, panel.position.y),
		Vector2(w, panel.size.y))


## What is left in the middle, for chips — between the selection column and
## the commands column. Can come out zero-width on a very narrow window;
## callers must cope with that (see `chip_columns`), not assume it is
## positive.
##
## `building_column_in_use` false hands the strip the BUILD column's width
## as well. Not a cosmetic stretch: at one row of chips (see `CHIP_ROWS`)
## the strip seats four tiles on a 1080p window and a barracks trains SIX,
## and those tiles ARE the train orders (`Client._show_train_chips`) — so
## the strip has to be wider exactly when a building is selected. Which is
## exactly when the build column is empty, because a building builds
## nothing. The two facts are the same fact, which is what makes this an
## invariant rather than a special case.
static func chip_strip_rect(panel: Rect2, building_column_in_use := true) -> Rect2:
	var title := title_column_rect(panel)
	var left := title.position.x + title.size.x + PANEL_PAD
	var edge := commands_column_rect(panel) if building_column_in_use \
		else build_column_rect(panel)
	var right := edge.position.x - PANEL_PAD
	return Rect2(Vector2(left, panel.position.y),
		Vector2(maxf(right - left, 0.0), panel.size.y))


## How many chips fit across a strip of this width. At least one, even on a
## strip too narrow to truly fit one — better an overflowing chip than a
## division by a column count of zero silently hiding the whole selection.
static func chip_columns(strip_width: float) -> int:
	return maxi(1, int((strip_width + CHIP_GAP) / (CHIP_SIZE.x + CHIP_GAP)))


## How many rows of chips fit down a strip this tall, keeping the panel's
## bottom pad clear.
static func chip_rows(strip_height: float) -> int:
	return maxi(1, int((strip_height - PANEL_PAD_Y + CHIP_GAP) / (CHIP_SIZE.y + CHIP_GAP)))


## When a per-squad chip list should collapse to one chip per ARCHETYPE.
##
## The lower of the legibility threshold and what the strip can actually
## hold. `CHIP_COLLAPSE_THRESHOLD` alone was the whole rule while the strip
## was four rows deep and could seat twelve; at one row it seats four, so
## six selected squads meant four chips and a pager where "Gatherers x6"
## says more in one chip than six identical tiles say in six. The collapse
## was always the better answer for a uniform selection — the short bar
## just made it the only one.
static func chip_collapse_at(strip: Rect2) -> int:
	return mini(CHIP_COLLAPSE_THRESHOLD, chip_capacity(strip))


## How many chips a strip can actually SHOW.
##
## Necessary because the panel is short now: the chip strip used to be tall
## enough that a caller could hand it every entry and trust the pool size
## to bound the result, and at two rows it no longer is. A caller that
## ignored this would draw chips below the panel's own bottom edge — the
## overflow is silent, because a Control outside its panel still renders
## perfectly happily on top of the battlefield.
static func chip_capacity(strip: Rect2) -> int:
	return chip_columns(strip.size.x) * chip_rows(strip.size.y)


## Where the i'th chip sits, relative to the strip's own top-left corner.
static func chip_slot(index: int, columns: int) -> Vector2:
	var row := index / columns
	var col := index % columns
	return Vector2(float(col) * (CHIP_SIZE.x + CHIP_GAP),
		float(row) * (CHIP_SIZE.y + CHIP_GAP))


## Where the i'th button of an action grid sits, relative to ITS OWN
## column's corner (not the panel's — see `commands_column_rect` and
## `build_column_rect`).
##
## One function for both grids, where there were two: side by side they are
## the same grid in different columns, and the caller already has to say
## which column it is placing into. Two identical bodies differing only in
## a start Y is exactly how the build segment's row count and the panel's
## height drifted apart the last time.
static func action_slot(index: int, button: Vector2) -> Vector2:
	return Vector2(
		PANEL_PAD + float(index % ACTION_COLUMNS) * (button.x + ACTION_GAP.x),
		ACTIONS_Y + float(index / ACTION_COLUMNS) * (button.y + ACTION_GAP.y))


## A thin VERTICAL rule down a column's left edge, in panel space — what
## separates one column from its neighbour now that the two action grids
## sit side by side rather than stacked with a horizontal divider between
## them. Inset top and bottom so it reads as a separator rather than as a
## box that failed to close.
static func column_rule_rect(column: Rect2) -> Rect2:
	return Rect2(Vector2(column.position.x, column.position.y + PANEL_PAD),
		Vector2(1.0, maxf(column.size.y - PANEL_PAD * 2.0, 0.0)))
