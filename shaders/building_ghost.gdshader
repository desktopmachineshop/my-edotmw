shader_type spatial;
render_mode cull_back, unshaded, blend_mix, depth_draw_never;

// The PLACEMENT PREVIEW of an authored building
// (D-20260831-a-placement-ghost-is-the-building-it-will-build): the model
// that is about to be raised, drawn semi-transparent and tinted by whether
// the ground will take it.
//
// Unshaded on purpose. A ghost is a statement about an INTENT, not an
// object standing in the world's light — and D-086's rig has no shadows,
// so a lit ghost sitting inside the terrain reads as a real building that
// has half sunk into the ground.
//
// THE VERTEX ALPHA IS NOT TRANSPARENCY, and that is the whole reason this
// shader exists rather than a StandardMaterial3D with
// `vertex_color_use_as_albedo`. COLOR_0's alpha is the OWNER-COLOUR MASK
// (D-052) — 1.0 on a roof or banner, 0.0 on most walls — and Godot's
// standard shader multiplies the vertex colour into ALBEDO *including its
// alpha*. A ghost built that way would be transparent exactly where the
// building shows least owner colour: the walls would vanish and a roof
// would hang in the air, with every count healthy and nothing failing.
// Same family as the MultiMesh-overrides-COLOR trap in art/lib/bake.py.

uniform vec4 tint : source_color = vec4(0.4, 0.95, 0.5, 1.0);

// How far the model's own colours are pulled toward the tint. Not 1.0:
// a flat silhouette says where the building goes and not WHICH building,
// and telling a barracks from a storehouse at a glance is most of what a
// preview is for.
uniform float tint_mix : hint_range(0.0, 1.0) = 0.55;

// One opacity for the whole model, from the tint's own alpha, so the
// ghost's transparency is a property of the PREVIEW rather than of
// whichever part of the mesh a fragment happens to land on.
uniform float opacity : hint_range(0.0, 1.0) = 0.45;

varying vec3 surface;

void vertex() {
	// rgb only. See the note above about COLOR.a.
	surface = COLOR.rgb;
}

void fragment() {
	ALBEDO = mix(surface, tint.rgb, tint_mix);
	ALPHA = opacity;
}
