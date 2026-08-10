shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Animated soldiers, opaque path (D-065). The project's first shader.
//
// `specular_disabled` and `diffuse_lambert` are chosen rather than defaulted:
// the art direction is flat stylised colour (D-064), and at this scale every
// per-pixel term is paid 26,644 times over.

#include "res://shaders/unit_vat.gdshaderinc"

void vertex() {
	vat_colour = vat_pose(UV2, INSTANCE_CUSTOM, VERTEX, NORMAL);
}

void fragment() {
	ALBEDO = vat_albedo();
	ROUGHNESS = 0.85;
}
