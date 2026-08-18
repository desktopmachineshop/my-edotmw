extends SceneTree

## Tiles every formation icon into one PNG so the dots can be LOOKED at.
##
## `test-client`'s capture scenario never selects a squad, so the panel it
## photographs has no formation buttons in it and structurally cannot show
## whether these read as the right shapes. Same reason `gen-terrain-shot`
## exists beside `gen-terrain-preview`.

const CELL := 96
const PAD := 8


func _init() -> void:
	var defs := FormationRoster.load_all()
	var w := (CELL + PAD) * defs.size() + PAD
	var sheet := Image.create(w, CELL + PAD * 2, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.09, 0.10, 0.13, 1.0))
	var x := PAD
	for def in defs:
		var img := FormationIcon.texture(String(def.id),
			Vector2i(CELL, CELL)).get_image()
		# Tint white dots to the panel's foreground so the sheet looks like
		# the button will, rather than like a mask.
		for y in range(CELL):
			for xx in range(CELL):
				var c := img.get_pixel(xx, y)
				if c.a > 0.02:
					sheet.set_pixel(x + xx, PAD + y,
						Color(0.09, 0.10, 0.13, 1.0).lerp(
							Color(0.86, 0.89, 0.95, 1.0), c.a))
		print("%s: %d dots, kind=%s" % [def.id,
			FormationIcon.dots(String(def.id)).size(), def.kind])
		x += CELL + PAD
	# A second row at the size the button ACTUALLY is. The row above is
	# magnified, and an icon that reads at 96 px may be mush at 34 — the
	# same rule as never quoting a frame time without saying what hardware
	# drew it.
	var panel: Rect2 = HudLayout.compute(
		HudLayout.design_size(HudLayout.REFERENCE), Vector2(216.0, 216.0))["panel"]
	var real: Vector2 = HudLayout.formation_icon_size(panel, defs.size())
	print("true button size: %.1f x %.1f px" % [real.x, real.y])
	var rw := int(round(real.x))
	var rh := int(round(real.y))
	var strip := Image.create(w, rh + PAD * 2, false, Image.FORMAT_RGBA8)
	strip.fill(Color(0.09, 0.10, 0.13, 1.0))
	var sx := PAD
	for def in defs:
		var img2 := FormationIcon.texture(String(def.id),
			Vector2i(rw, rh)).get_image()
		for y in range(rh):
			for xx in range(rw):
				var c2 := img2.get_pixel(xx, y)
				if c2.a > 0.02:
					strip.set_pixel(sx + xx, PAD + y,
						Color(0.86, 0.89, 0.95, 1.0).lerp(
							Color(0.09, 0.10, 0.13, 1.0), 1.0 - c2.a))
		sx += CELL + PAD
	var both := Image.create(w, sheet.get_height() + strip.get_height(), false,
		Image.FORMAT_RGBA8)
	both.fill(Color(0.09, 0.10, 0.13, 1.0))
	both.blit_rect(sheet, Rect2i(0, 0, w, sheet.get_height()), Vector2i(0, 0))
	both.blit_rect(strip, Rect2i(0, 0, w, strip.get_height()),
		Vector2i(0, sheet.get_height()))
	sheet = both
	DirAccess.make_dir_recursive_absolute("res://artifacts")
	var out := "res://artifacts/formation-icons.png"
	var err := sheet.save_png(out)
	print("wrote %s (%s)" % [out, "ok" if err == OK else str(err)])
	quit(0 if err == OK else 1)
