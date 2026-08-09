shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Authored buildings (D-064). Static — a town hall does not walk, so there is
// no vertex animation texture here and no reason to pay for one.
//
// Unlike the unit shaders this CAN read the mesh's own COLOR attribute:
// buildings render as individual MeshInstance3Ds, not through a MultiMesh, and
// it is the MultiMesh that overrides COLOR with its per-instance colour. Same
// convention either way — rgb is the material's own colour, alpha is how much
// of it belongs to the owner (D-052).

uniform vec4 team_colour : source_color = vec4(0.6, 0.6, 0.6, 1.0);

varying vec4 surface;

void vertex() {
	surface = COLOR;
}

void fragment() {
	ALBEDO = mix(surface.rgb, team_colour.rgb, surface.a);
	ROUGHNESS = 0.9;
}
