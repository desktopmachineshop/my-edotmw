shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, blend_mix;

// The fog-of-war ghost variant (D-025, D-065).
//
// A concealed squad leaves a client-side ghost: last-known curve and
// composition, frozen. It is drawn with the same VAT so it keeps the pose it
// was last seen in, and faded so a player can tell remembered from observed.
//
// This is a separate shader from unit_anim.gdshader rather than a uniform on
// it, because writing ALPHA is what makes Godot treat a material as
// transparent — see unit_vat.gdshaderinc. Before M7 the same distinction was
// made by mutating `albedo_color.a` on a StandardMaterial3D in place; the
// comment that used to live at that site is worth keeping in mind here, since
// it was bought with a real defect: GeometryInstance3D.transparency is
// silently ignored under gl_compatibility, which is the only renderer
// `just test-client` can use.

#include "res://shaders/unit_vat.gdshaderinc"

uniform float ghost_alpha : hint_range(0.0, 1.0) = 0.35;

void vertex() {
	vat_colour = vat_pose(UV2, INSTANCE_CUSTOM, VERTEX, NORMAL);
}

void fragment() {
	ALBEDO = vat_albedo();
	ROUGHNESS = 0.85;
	ALPHA = ghost_alpha;
}
