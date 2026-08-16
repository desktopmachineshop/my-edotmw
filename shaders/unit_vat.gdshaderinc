// Shared vertex-animation-texture sampling (D-065).
//
// Included by unit_anim.gdshader, which is the only shader soldiers render
// through: a squad is drawn opaque or not drawn at all (D-099).
//
// There was a transparent sibling here for fog ghosts until D-099 deleted the
// ghost rendering it served. Worth knowing before adding another one: Godot
// decides whether a material is transparent from whether the shader WRITES to
// ALPHA — a compile-time property, not a runtime one. So a translucent variant
// is necessarily a SECOND shader program, and one shader that could do both
// would make all 26,644 soldiers alpha-sorted to serve the handful that need
// it.
//
// ## What the runtime supplies
//
// Per material (one per squad):
//   vat            the baked clips; see art/lib/bake.py for the layout
//   vat_size       texture dimensions, passed rather than queried so this does
//                  not depend on textureSize() under GL Compatibility
//   total_frames   rows of position data; normals start at this row
//   frames_per_clip
//   team_colour    the owning player's colour (D-052)
//
// Per instance, in MultiMesh custom data:
//   INSTANCE_CUSTOM.r  clip index, matching art/lib/clips.py CLIP_ORDER
//   INSTANCE_CUSTOM.g  phase offset for this soldier — a hash of the slot,
//                      so a rank does not march in lockstep
//   INSTANCE_CUSTOM.b  playback rate, derived from the squad's speed
//   INSTANCE_CUSTOM.a  spare
//
// ## Phase is computed here, from TIME
//
// This is the load-bearing half of D-065. The CPU never advances a per-soldier
// phase and never stores one; the shader derives it from TIME and a constant
// per-soldier offset every frame. There is nowhere for per-soldier integration
// state to live, which is what keeps D-006 clause 1 true by construction rather
// than by discipline.

uniform sampler2D vat : filter_nearest, repeat_disable, hint_default_black;
uniform vec2 vat_size = vec2(1.0, 1.0);
uniform float total_frames = 64.0;
uniform float colour_row = 128.0;
uniform float frames_per_clip = 16.0;
uniform vec4 team_colour : source_color = vec4(0.6, 0.6, 0.6, 1.0);

varying vec4 vat_colour;

// Returns the vertex's colour (rgb) and owner-colour mask (a). Returned
// rather than assigned to `vat_colour` directly: Godot forbids writing a
// varying from anywhere but vertex(), so the caller does that assignment.
vec4 vat_pose(vec2 uv2, vec4 custom, inout vec3 vertex, inout vec3 normal) {
	int height = int(vat_size.y);

	// The column this vertex owns. Carried in the mesh (see bake.py) rather
	// than taken from VERTEX_ID, so it survives whatever the glTF importer
	// does to vertex order and does not depend on a built-in that GL
	// Compatibility may not expose.
	int col = int(uv2.x * vat_size.x);

	int clip = int(custom.r + 0.5);
	float phase = fract(custom.g + TIME * custom.b);
	int local = int(phase * frames_per_clip);
	int frame = clip * int(frames_per_clip) + local;

	// Blender writes images bottom row first; Godot's y = 0 is the top. The
	// flip lives here, in one place, and is verified against the baker by a
	// test rather than eyeballed.
	int y_position = height - 1 - frame;
	int y_normal = height - 1 - (int(total_frames) + frame);

	vertex += texelFetch(vat, ivec2(col, y_position), 0).rgb;
	normal = texelFetch(vat, ivec2(col, y_normal), 0).rgb;

	// Colour comes from the texture, NOT from the mesh's COLOR attribute.
	// A MultiMesh overrides COLOR with its own per-instance colour, so a
	// vertex colour never reaches the fragment stage on the path this game
	// renders through — observed as every soldier rendering black while UV2
	// arrived perfectly. Same column, so it costs one fetch and no bookkeeping.
	return texelFetch(vat, ivec2(col, height - 1 - int(colour_row)), 0);
}

// Owner colour over the model's own colour, by the mask baked into the colour
// row's alpha (D-052). Whose units these are is the first thing a player reads
// off the screen; which kind they are is second, and shape carries that.
vec3 vat_albedo() {
	return mix(vat_colour.rgb, team_colour.rgb, vat_colour.a);
}
