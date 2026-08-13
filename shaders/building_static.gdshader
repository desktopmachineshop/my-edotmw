shader_type spatial;
render_mode cull_back, diffuse_toon, specular_disabled;
// diffuse_toon (D-076's lighting pass, matching unit_anim.gdshader): a
// stepped light/shadow split instead of a smooth Lambert gradient — the
// shading half of D-064's "stylised low-poly" that the shape alone never
// delivered.

// Authored buildings (D-064). Static — a town hall does not walk, so there is
// no vertex animation texture here and no reason to pay for one.
//
// Unlike the unit shaders this CAN read the mesh's own COLOR attribute:
// buildings render as individual MeshInstance3Ds, not through a MultiMesh, and
// it is the MultiMesh that overrides COLOR with its per-instance colour. Same
// convention either way — rgb is the material's own colour, alpha is how much
// of it belongs to the owner (D-052).

uniform vec4 team_colour : source_color = vec4(0.6, 0.6, 0.6, 1.0);
// D-076: an authored gate has no separate "open" mesh — the passability
// cue is a colour lift, same idea as the primitive path's
// mesh_color.lightened(0.5), so a player can read a gate's state without
// selecting it regardless of which rendering path drew it.
uniform float gate_open : hint_range(0.0, 1.0) = 0.0;

varying vec4 surface;

void vertex() {
	surface = COLOR;
}

void fragment() {
	vec3 base = mix(surface.rgb, team_colour.rgb, surface.a);
	ALBEDO = mix(base, vec3(1.0), gate_open * 0.35);
	ROUGHNESS = 0.9;
	// D-076: matches unit_anim.gdshader's rim term — a building's silhouette
	// should read as cleanly as a soldier's, not less, since it is what a
	// player identifies "whose ground is this" from at a glance (D-052).
	RIM = 0.25;
	RIM_TINT = 0.35;
}
