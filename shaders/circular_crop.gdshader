shader_type canvas_item;

// Crops a texture to a circle, in real pixel space rather than normalised
// UVs — the minimap is not square, and a UV-space circle over a non-square
// rect is an ellipse, not a circle. Used to fit the minimap inside the nav
// ring's border band (see Client._draw_nav_ring_frame): the ring is a
// decorative frame drawn OVER the minimap, not a stretch of the map itself,
// so this is a crop (hides pixels outside the circle) rather than a
// distortion of the map's own proportions (see hud_layout.gd's RING_MIN_SIZE
// doc comment for why that distinction matters here).

// `rect_size`/`centre_px`/`radius_px` are in the RECT's own displayed
// pixel space (its `size`), not the source texture's native resolution —
// the minimap Image is one pixel per cell and is then stretched to fill a
// differently-sized on-screen rect (`TextureRect.STRETCH_SCALE`), so
// deriving pixel space from the texture itself would crop against the
// wrong scale.
uniform vec2 rect_size = vec2(1.0, 1.0);
// The circle's own centre stays FIXED on screen (the ring around it does
// not move) — only WHICH part of the map is sampled at that centre moves,
// via `focus_uv` below.
uniform vec2 centre_px = vec2(0.0, 0.0);
uniform float radius_px = 0.0;

// Where in the SOURCE texture (0..1) the fixed crop centre currently
// points — Client._centre_minimap_crop_on_camera keeps this at the
// camera's own cell, so the ring reads as "centred on the camera" even
// though its own screen position never moves.
//
// `fract()` wraps the sampled UV rather than clamping it: the map this
// texture represents is a TORUS (see torus_space.gd — every distance,
// neighbour and world conversion in this project has to be wrap-aware,
// and a minimap crop is no exception), and the camera can legitimately
// sit anywhere on it, including right at the flat image's own hard edge.
// Clamping there would show a mostly-empty circle with the map content
// squeezed into one corner; wrapping shows the seam continuing around,
// the same illusion the 3D terrain's own nine-times tiling gives.
uniform vec2 focus_uv = vec2(0.5, 0.5);

void fragment() {
	vec2 pixel = UV * rect_size;
	if (distance(pixel, centre_px) > radius_px) {
		discard;
	}
	vec2 delta_uv = (pixel - centre_px) / rect_size;
	COLOR = texture(TEXTURE, fract(focus_uv + delta_uv));
}
