shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;

// Animated soldiers, opaque path (D-065). The project's first shader.
//
// `specular_disabled` is kept — the art direction is flat stylised colour
// (D-064), and at this scale every per-pixel term is paid 26,644 times over.
// `diffuse_toon` replaces `diffuse_lambert` (D-076's lighting pass): a
// stepped light/shadow split reads as graphic-novel flat colour rather than
// a smooth gradient, which is the "stylised" half of D-064 that lighting
// alone had never actually delivered — the shape was always low-poly, the
// SHADING was still photoreal Lambert. Both this shader's built-in cost is
// the renderer's own light processor, not a per-pixel branch added here.

#include "res://shaders/unit_vat.gdshaderinc"

void vertex() {
	vat_colour = vat_pose(UV2, INSTANCE_CUSTOM, VERTEX, NORMAL);
}

void fragment() {
	ALBEDO = vat_albedo();
	ROUGHNESS = 0.85;
	// A fixed rim term, not a per-material uniform: D-064 calls for "strong
	// silhouettes", and rim light is the cheapest way to keep a soldier's
	// edge legible against similarly-coloured terrain or a crowded melee,
	// at zero added per-instance cost.
	RIM = 0.3;
	RIM_TINT = 0.4;
}
