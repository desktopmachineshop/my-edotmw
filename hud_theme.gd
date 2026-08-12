class_name HudTheme
extends RefCounted

## The HUD's palette, corner radii and text colours in one place.
##
## Before this, every panel/button/label call site wrote its own
## `Color(r, g, b, a)` literal, so "what does this game's UI look like" had
## no single answer — changing the palette meant hunting scattered numbers
## across `client.gd`. This file exists so the answer lives in one place,
## matched against the "restrained historical" reference design: a dark
## parchment/campaign-map register (near-black ground, warm amber accent,
## cream text) rather than the cool navy/blue placeholder it replaces.
##
## All-static, like `hud_layout.gd` and for the same reason: colours are
## data, not state, and a RefCounted with no instance keeps that honest.
##
## ## The font is a deliberate, flagged deviation
##
## The reference design specifies Cormorant Garamond (display) and Figtree
## (body) — Google Fonts, not present anywhere in this project and not
## something this pass fetches: there is no asset pipeline for UI fonts
## here (`/art` generates 3D models, not type), and vendoring a webfont
## without a considered licensing/asset-tracking decision is out of scope
## for a UI re-theme. The hierarchy those fonts create is approximated with
## `ThemeDB.fallback_font` at varying size and colour instead — a heavier,
## brighter title next to a smaller, dimmer caption reads as the same
## hierarchy even in one typeface. Swapping in real fonts later is a
## drop-in: every size call in this file is named for its ROLE
## (`TITLE_SIZE`, not "18"), so a future FontFile only has to be assigned
## once, not chased through every label.

# --- ground and panels --------------------------------------------------

const BG_VOID := Color8(0x14, 0x12, 0x0e)              ## the darkest ground colour
const BG_PANEL := Color8(0x14, 0x12, 0x0e, 0xe6)        ## rgba(20,18,14,.9) panels float on
const BG_PANEL_SOFT := Color8(0x14, 0x12, 0x0e, 0xdb)   ## the top bar's slightly lighter wash
const BG_SOLID := Color8(0x1b, 0x19, 0x14)              ## lobby/menu panel backing (opaque)
const BG_ROW := Color8(0x22, 0x1f, 0x19)                ## a highlighted row (e.g. "this is you")
const BG_ROW_DIM := Color8(0x1b, 0x19, 0x14)            ## an ordinary row

const BORDER := Color8(0x3a, 0x35, 0x2b)                ## the ordinary hairline
const BORDER_STRONG := Color8(0x4a, 0x42, 0x35)         ## a control's own outline
const RULE := Color8(0x2b, 0x27, 0x21)                  ## a divider inside a panel

# --- the one accent ------------------------------------------------------
#
# Warm amber, doing every job blue used to: borders, the selected state,
# positive emphasis. One accent rather than several keeps "this is the
# thing that matters" legible at a glance.

const ACCENT := Color8(0xc6, 0x71, 0x39)
const ACCENT_BRIGHT := Color8(0xf6, 0xa0, 0x6b)         ## accent text/icons on dark
const ACCENT_DIM := Color8(0x4a, 0x42, 0x35)            ## accent's own disabled/rule tone


## The accent as a translucent wash — a "selected" chip or badge's fill.
static func accent_wash(alpha: float) -> Color:
	var c := ACCENT
	c.a = alpha
	return c


## The accent as a translucent border — one step stronger than the wash.
static func accent_border(alpha: float = 0.5) -> Color:
	var c := ACCENT
	c.a = alpha
	return c

# --- text, brightest to dimmest ------------------------------------------

const TEXT_BRIGHT := Color8(0xf9, 0xf4, 0xed)           ## headings
const TEXT := Color8(0xee, 0xe7, 0xdb)                  ## ordinary body text
const TEXT_MUTED := Color8(0xdc, 0xd3, 0xc4)            ## secondary body text
const TEXT_DIM := Color8(0xa1, 0x97, 0x86)              ## captions, counts
const TEXT_FAINT := Color8(0x82, 0x79, 0x6a)            ## timestamps, hints
const TEXT_GHOST := Color8(0x64, 0x5c, 0x50)            ## the dimmest legible tone
const TEXT_DISABLED := Color8(0x4a, 0x42, 0x35)         ## "not yet" — same tone as ACCENT_DIM

# --- status colours -------------------------------------------------------

const GOOD := Color8(0x8f, 0xa0, 0x73)                  ## income, healthy bars
const BAD := Color8(0xd9, 0x82, 0x82)                   ## upkeep deficit, low health
const WARNING := ACCENT_BRIGHT                          ## "under attack", refusals
const DANGER := Color8(0xc0, 0x39, 0x2b)                ## destructive actions (Exit, Remove)
const NEUTRAL := Color8(0x82, 0x79, 0x6a)                ## an outlined button with no strong opinion

# --- resource swatches (must match the ground markers — see _node_colour) -

const RESOURCE_FOOD := Color8(0xd9, 0x82, 0x82)
const RESOURCE_WOOD := Color8(0xb2, 0x62, 0x2d)
const RESOURCE_GOLD := Color8(0xb8, 0xa1, 0x3a)
const RESOURCE_STONE := Color8(0xa1, 0x97, 0x86)

# --- geometry --------------------------------------------------------------

const RADIUS_SM := 4
const RADIUS_MD := 6
const RADIUS_LG := 8
const RADIUS_PILL := 999

# --- type sizes, named by role rather than by number ------------------------

## Bumped up from the reference design's own (smaller) sizes — those were
## tuned against a crisp static mockup image, not against a real HUD
## viewed at MIN_SCALE on an ordinary monitor. Reported as genuinely hard
## to read; legibility wins over matching the mockup's exact proportions.
const DISPLAY_SIZE := 26      ## a screen's own headline (Defeated, Menu, Settings)
const TITLE_SIZE := 19        ## a panel's title (a chip's unit name, a building's name)
const BODY_SIZE := 16         ## ordinary readable text
const CAPTION_SIZE := 13      ## small uppercase-tracked labels ("FORMATION", "COMMANDS")
const MONO_SIZE := 15         ## counts and clocks


## A StyleBoxFlat built from this palette, so every panel/button call site
## stops hand-rolling the same six lines with a different colour swapped in.
static func stylebox(bg: Color, border: Color = BORDER, border_width: int = 1,
		radius: int = RADIUS_MD) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
