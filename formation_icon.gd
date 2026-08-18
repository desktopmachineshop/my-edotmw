extends RefCounted
class_name FormationIcon

## The dots on a formation button — one per soldier, in the shape that
## formation actually stands in.
##
## ## Why this is derived rather than drawn
##
## Every dot is `Formation.slot_offset` output, the SAME function that
## puts real soldiers on the ground. So a formation button is a top-down
## plot of the formation, and adding a `.tres` (D-058) gives it a correct
## icon with nothing drawn by hand. A hand-authored sprite per shape would
## be a second definition of the geometry, free to drift from the first —
## the defect class this project keeps meeting (`biome_color` and the
## minimap, `surface_field` and the ground sampler).
##
## All-static and pure, for the same reason `hud_layout.gd` and
## `selection_pick.gd` are: the part with the interesting failure mode is
## the arithmetic, and it should be testable without a GPU.
##
## ## The two decisions in here
##
## **A sample strength, not the squad's real one.** A button is ~34 px
## wide and a squad is ~36 men. The count is squeezed from both ends: too
## FEW and the shapes stop diverging (`line` is 3 ranks and `column` is 4
## files, so at 12 men both are 4 wide by 3 deep and the two icons are the
## same picture), too MANY and the dots merge into a solid blob at button
## size — which is what 24 did while the scale was still shared, and it
## was only ever visible in a rendered sheet. At 21: line is 7x3 against
## column's 4x6, which reads as wide-versus-deep at a glance, and the dots
## stay apart because the radius follows the pitch.
## Both failure modes have a test; look at `artifacts/formation-icons.png`
## as well, because "merged into a blob" is a picture, not a number.
##
## **Each icon fills its own box, and the aspect ratio is kept.** A shared
## scale across the roster was tried first, so that `tight` would draw
## smaller than `sparse` and the density difference would be visible. It
## was rendered and rejected: `sparse` stands at 1.8x spacing and so set
## the scale for everything, which squashed `line` into 55% of its button
## and left `line` and `column` reading as two similar little grids. On a
## 34 px button SHAPE is the only thing legible, so shape is what the box
## is spent on — wide-and-shallow for `line`, narrow-and-deep for
## `column`, a triangle, a ring.
##
## One scalar, not one per axis: scaling x and y independently would draw
## every formation as the same square and throw away the wide/deep
## distinction that is the entire point.
##
## `tight` and `sparse` stay apart because `sparse` is JITTERED — a
## regular lattice against an irregular one — not because of their size.

## Men plotted per icon. See the note above before changing it.
const SAMPLE_STRENGTH := 21

## Spacing handed to `Formation.slot_offset`. Arbitrary — the shared scale
## below divides it straight back out — so it is 1.0 to keep the
## arithmetic readable.
const SAMPLE_SPACING := 1.0

## Dot diameter as a fraction of the PITCH between neighbouring soldiers,
## not of the icon. Derived rather than guessed: a fixed fraction of the
## icon has no idea how close together this particular formation stands,
## so the number that let `sparse` breathe welded `line` into a bar. Under
## 1.0 by construction, so dots never touch.
const DOT_PITCH_FRACTION := 0.85

## Padding inside the button, as a fraction of the short side, so the
## widest formation does not touch the border.
const INSET_FRACTION := 0.08

## Cache: "shape|strength" -> half-extent. Pure in both.
static var _scale_cache := {}


## Dot positions for `shape`, in a unit box centred on the origin:
## x and y both run -0.5..0.5, y already flipped so the formation's FRONT
## is at the top of the icon the way a player looks at the battlefield.
##
## Returns an empty array for an unknown shape rather than falling back to
## a line: an icon that silently draws the wrong formation is worse than a
## button with no icon, because it cannot be noticed.
static func dots(shape: String, strength: int = SAMPLE_STRENGTH) -> PackedVector2Array:
	var out := PackedVector2Array()
	if FormationRoster.by_id(StringName(shape)) == null:
		return out
	var scale := _extent_of(shape, strength)
	if scale <= 0.0:
		return out
	var usable := 0.5 - INSET_FRACTION
	for slot in range(maxi(strength, 1)):
		var p := Formation.slot_offset(shape, slot, maxi(strength, 1), SAMPLE_SPACING)
		# Formation-local +y is forward (`_grid_offset` puts rank r at
		# -r * spacing), and screen -y is up, so forward is negated to put
		# the front rank at the top of the button.
		# `p / scale` already spans -1..1, so it is multiplied by the
		# half-width wanted, not the full width.
		out.append(Vector2(p.x, -p.y) / scale * usable)
	return out


## This formation's own half-extent, on whichever axis is larger — the
## divisor that makes it fill its button without distorting its aspect.
static func _extent_of(shape: String, strength: int) -> float:
	var key := "%s|%d" % [shape, strength]
	if _scale_cache.has(key):
		return _scale_cache[key]
	var widest := 0.0
	for slot in range(maxi(strength, 1)):
		var p := Formation.slot_offset(shape, slot, maxi(strength, 1), SAMPLE_SPACING)
		widest = maxf(widest, maxf(absf(p.x), absf(p.y)))
	_scale_cache[key] = widest
	return widest


## Dot radius as a fraction of the icon's side, for `shape`.
##
## Analytic, from the formation's own `spacing_scale`, rather than measured
## from the dots: `sparse` is jittered, so its true minimum pair distance
## is luck and would set every dot's size from the closest accidental pair.
## Neighbouring slots sit `spacing_scale` apart in the units `slot_offset`
## is sampled in, and `_extent_of` is what those units are divided by — so
## this is that pitch expressed in icon widths. It varies per shape because
## the scale does; a dense formation gets smaller dots, which is what stops
## it welding into a blob.
static func dot_radius_fraction(shape: String, strength: int = SAMPLE_STRENGTH) -> float:
	var def := FormationRoster.by_id(StringName(shape))
	if def == null:
		return 0.0
	var scale := _extent_of(shape, strength)
	if scale <= 0.0:
		return 0.0
	var pitch := maxf(def.spacing_scale, 0.01) / scale * (0.5 - INSET_FRACTION)
	return pitch * DOT_PITCH_FRACTION * 0.5



## Cache: "shape|w|h" -> ImageTexture.
static var _texture_cache := {}

## Supersampling factor. The button is ~26 px tall and a dot is a couple
## of pixels; rasterising at size gives stair-stepped blobs, so it is drawn
## large and shrunk with a filter.
const ICON_SUPERSAMPLE := 4


## The button icon for `shape` at this exact pixel size — its dots stamped
## white on transparent, so the theme's own modulate decides the colour.
##
## The SIZE is a parameter, not a constant, because the button is not
## square (45x26 at the reference window) and `expand_icon` stretches
## whatever it is given to fill. A square texture stretched into that
## squashes every formation vertically by ~1.75x, which flattens the wedge
## and undoes exactly the wide-versus-deep distinction the icons exist to
## draw. So the dots are FITTED to the button's own aspect here: a wide
## `line` is limited by the width and a deep `column` by the height, and
## both use the whole button.
##
## This is the RENDERING half of the file and `dots()` is the geometry
## half. They are together because a hand-drawn sprite beside a derived
## geometry is exactly the second definition this file exists to avoid;
## they stay separable because nothing here needs a GPU, so both halves are
## testable headless.
static func texture(shape: String, size: Vector2i) -> ImageTexture:
	var w := maxi(size.x, 1)
	var h := maxi(size.y, 1)
	var key := "%s|%d|%d" % [shape, w, h]
	if _texture_cache.has(key):
		return _texture_cache[key]

	var pts := dots(shape)
	var img := Image.create(w * ICON_SUPERSAMPLE, h * ICON_SUPERSAMPLE, false,
		Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	if pts.is_empty():
		var blank := ImageTexture.create_from_image(img)
		_texture_cache[key] = blank
		return blank

	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in pts:
		lo = lo.min(p)
		hi = hi.max(p)
	var span := hi - lo
	var target := Vector2(img.get_width(), img.get_height()) * (1.0 - INSET_FRACTION * 2.0)
	# Fit, not stretch: one scalar, whichever axis runs out first.
	var fit := minf(target.x / maxf(span.x, 0.0001), target.y / maxf(span.y, 0.0001))
	var centre := Vector2(img.get_width(), img.get_height()) * 0.5
	var radius := maxi(int(round(dot_radius_fraction(shape)
		* float(mini(img.get_width(), img.get_height())))), 1)
	for p in pts:
		_stamp(img, centre + (p - (lo + hi) * 0.5) * fit, radius)
	img.resize(w, h, Image.INTERPOLATE_LANCZOS)
	var tex := ImageTexture.create_from_image(img)
	_texture_cache[key] = tex
	return tex


## One soldier. A filled disc, clipped to the image rather than clamped —
## a dot pushed off the edge should vanish, not smear along the border.
static func _stamp(img: Image, at: Vector2, radius: int) -> void:
	var r2 := float(radius * radius)
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if float(dx * dx + dy * dy) > r2:
				continue
			var x := int(round(at.x)) + dx
			var y := int(round(at.y)) + dy
			if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
				continue
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, 1.0))
