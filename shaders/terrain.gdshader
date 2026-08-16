shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// The ground (D-096). Three atlas taps per fragment, blended by per-vertex
// weights, over UVs that run CONTINUOUSLY across cell boundaries.
//
// ## Why a shader was needed at all
//
// Before this the terrain was a StandardMaterial3D and each hex was inscribed
// in its own biome's atlas tile with a 6% inset and a hashed rotation. That is
// what made the texture restart at every boundary — the strongest remaining cue
// of the hex lattice once D-096 blended the colour. Continuous UVs fix it, but
// a continuous UV over an eight-tile atlas sampled by a fixed material would
// walk straight out of one biome's tile and into its neighbour's. Wrapping the
// coordinate back into the right tile is a per-fragment decision, and there is
// no fixed-function way to express it.
//
// ## The atlas still MODULATES; vertex colour still decides (D-083)
//
// ALBEDO is COLOR (which `TerrainGen.biome_color` supplies, blended per vertex)
// multiplied by the detail. `art/terrain/atlas.py` writes every tile to average
// near neutral precisely so this multiplication leaves the palette alone, which
// is what keeps the minimap and the terrain preview PNG — neither of which ever
// sees this shader — from drifting away from the 3D view.
//
// ## Tiles must tile, and that is now load-bearing
//
// `fract()` below wraps the continuous coordinate back into one tile, so the
// tile's own edges meet each other thousands of times across the map. The
// generator has always built its noise periodically; before this it was
// insurance, and now a non-periodic tile would draw a hard grid of its own.

uniform sampler2D atlas : source_color, filter_linear_mipmap, repeat_disable;

// Fog of war on the GROUND (D-102). One texel per cell, addressed by UV2, which
// `TerrainChunk.fog_uv` derives from the CELL — never from world position, so
// all nine torus copies (D-035) agree by construction, exactly as the atlas UVs
// above do.
//
// `repeat_enable` is what carries the seam: a chunk at the far edge of the map
// carries UV2 slightly outside [0,1], and the wrap lands it on the cell the
// torus says is there. `filter_linear` blends between cells, which — together
// with `TerrainFog.BLUR_SELF` — is what keeps the edge of a vision disk from
// reading as a ring of hexes.
//
// `hint_default_white` is load-bearing, not tidiness. Nothing but the game
// client binds this: `bench-render`, `gen-terrain-shot`, `gen-model-preview` and
// `gen-cover-preview` all build the same material through
// `TerrainChunk.make_material` and have no player whose knowledge could be
// asked about. White means fully lit, so they keep rendering the whole map.
uniform sampler2D fog : hint_default_white, filter_linear, repeat_enable;

// The atlas layout, from TerrainChunk.ATLAS_COLUMNS/ATLAS_ROWS, which a test
// pins to art/terrain/atlas.py. Passed in rather than hardcoded so there is one
// place it can be wrong.
uniform vec2 atlas_grid = vec2(4.0, 2.0);

// Matching the StandardMaterial3D this replaced. A constant rather than a
// uniform: nothing sets it, and a knob nothing turns is this project's
// fourth-most-repeated defect.
const float TERRAIN_ROUGHNESS = 0.95;

// Half a texel of a 512-px tile. Keeps the bilinear tap at the wrap point from
// reaching into the neighbouring biome's tile, at the cost of a jump of one
// thousandth of a tile — invisible, and smaller still because the tiles are
// periodic and therefore nearly equal at their two edges anyway.
const float TILE_EDGE = 0.001;

// Three atlas tile indices, constant over a cell (all seven of its vertices
// carry the same triple, so interpolation is a no-op and the value arrives
// exact). CUSTOM1 carries this vertex's weight for each of them, and THOSE
// interpolate — which is the whole trick: interpolating an index would ask for
// tile 4.7.
varying vec3 tile_index;
varying vec3 tile_weight;

void vertex() {
	tile_index = CUSTOM0.xyz;
	tile_weight = CUSTOM1.xyz;
}

vec3 tile_sample(float index, vec2 uv, vec2 ddx, vec2 ddy) {
	vec2 tile = vec2(mod(index, atlas_grid.x), floor(index / atlas_grid.x));
	vec2 size = vec2(1.0) / atlas_grid;
	vec2 within = clamp(fract(uv), TILE_EDGE, 1.0 - TILE_EDGE);
	// Explicit gradients, because `fract` tears the derivative once per tile
	// repeat and an implicit-derivative sample would pick the smallest mip
	// there — a bright seam every few hexes, in a ruler-straight line.
	return textureGrad(atlas, (tile + within) * size, ddx * size, ddy * size).rgb;
}

void fragment() {
	vec2 uv = UV;
	vec2 ddx = dFdx(uv);
	vec2 ddy = dFdy(uv);

	vec3 detail = tile_sample(tile_index.x, uv, ddx, ddy) * tile_weight.x
		+ tile_sample(tile_index.y, uv, ddx, ddy) * tile_weight.y
		+ tile_sample(tile_index.z, uv, ddx, ddy) * tile_weight.z;

	// How much of this ground the player knows about (D-102). Multiplying
	// ALBEDO is what makes unexplored ground genuinely black rather than merely
	// dark: D-086's rig lights the world with sky ambient as well as a sun, and
	// an unlit surface with albedo still takes the ambient. Specular goes with
	// it for the same reason — a black but still shiny sea would read as a
	// rendering fault rather than as unknown ground.
	float known = texture(fog, UV2).r;

	ALBEDO = COLOR.rgb * detail * known;
	ROUGHNESS = TERRAIN_ROUGHNESS;
	SPECULAR = 0.5 * known;
}
