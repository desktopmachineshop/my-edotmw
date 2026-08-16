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
// D-076, playtest amendment: a gate's door leaf actually swings open now,
// on top of the colour lift below — a player reading the silhouette from
// across the map (too far to tell a colour shift) still sees a passage.
// UV2 carries (is_door_leaf, hinge_x) per vertex, written by
// art/lib/bake.py's door_hinge_uv into the channel a building's UV1 would
// otherwise sit unused in (buildings have no VAT, D-064). Every vertex not
// part of the gate's "gate_leaf" (art/buildings/_add_gate_leaf) has
// UV2.x == 0.0 and is left untouched.
uniform float gate_open : hint_range(0.0, 1.0) = 0.0;
const float GATE_SWING_RADIANS = 1.74533; // ~100 degrees

varying vec4 surface;

void vertex() {
	surface = COLOR;
	if (UV2.x > 0.5) {
		float hinge_x = UV2.y;
		float angle = gate_open * GATE_SWING_RADIANS;
		float dx = VERTEX.x - hinge_x;
		float dz = VERTEX.z;
		float s = sin(angle);
		float c = cos(angle);
		VERTEX.x = hinge_x + dx * c - dz * s;
		VERTEX.z = dx * s + dz * c;
	}
}

void fragment() {
	vec3 base = mix(surface.rgb, team_colour.rgb, surface.a);
	ALBEDO = mix(base, vec3(1.0), gate_open * 0.35);
	ROUGHNESS = 0.9;
}
