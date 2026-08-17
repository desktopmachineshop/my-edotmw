shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Everything that STANDS on the fogged ground (D-20260817-fog-covers-props).
//
// D-106 gave the ground three states and `shaders/terrain.gdshader` draws them.
// Nothing else on screen had the uniform, so a forest the player scouted an hour
// ago kept rendering at full brightness on top of the dim ground it stands in —
// and at the blurred edge of a vision disk, on ground that is nearly black. The
// symptom the owner reported was "cliffs showing through the fog"; the things
// actually leaking were tree canopies and stone piles (issue #81).
//
// ## Why this exists rather than a `fog` uniform on the imported material
//
// The authored resource models arrive as ordinary glTF: one StandardMaterial3D
// per part colour, flat albedo, no textures (`art/resources/split_markers.gd`
// merges each kind into ONE mesh with one surface per material). A
// StandardMaterial3D cannot multiply its albedo by a texture read at a
// coordinate the mesh does not carry, and `material_override` on a
// MultiMeshInstance3D would flatten every surface to one colour — a tree would
// lose the difference between its trunk and its canopy, which is the same trap
// `art/lib/bake.py` records for props.
//
// So `PropFog.shaded()` re-expresses those materials as this shader: the
// authored albedo/roughness/metallic go in as uniforms (a test asserts they
// arrive unchanged) and the fog arrives as one extra tap.
//
// ## The coordinate comes from the CELL, per instance
//
// Trees batch into one MultiMesh per (chunk, model) and the chunk root is moved
// every frame to whichever of the nine torus copies (D-035) is on screen, so the
// same tree renders at nine different world positions over a match. A fog lookup
// keyed on world position would sample a different part of the field for every
// copy — forests correctly fogged mid-map and wrongly fogged near a seam. Same
// rule the terrain UVs already obey (D-035/D-096), and the reason `TerrainChunk`
// bakes `fog_uvs` per cell rather than deriving them in the shader.
//
// A MultiMesh's per-instance custom data is where a per-TREE value can live, so
// INSTANCE_CUSTOM carries `TerrainChunk.fog_uv` for the cell the tree grows on.
// It is a UV rather than a finished brightness on purpose: the fog texture is
// re-uploaded four times a second and the props follow it for free, where a
// baked-in brightness would mean rewriting every instance in every chunk on
// every refresh.
//
// `.z` is 1.0 when `.xy` means anything. A plain MeshInstance3D — a felled tree
// mid-animation, `forest_preview.gd`'s parade — gets an all-zero INSTANCE_CUSTOM
// and is drawn fully lit, which is the same bargain `hint_default_white` makes
// on the terrain shader: a renderer with no player whose knowledge could be
// asked about draws the whole world.

uniform vec4 albedo : source_color = vec4(1.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.9;
uniform float surface_metallic : hint_range(0.0, 1.0) = 0.0;

// Black for every authored model. It is here for the primitive stand-ins the
// client draws when `generated/` has not been built, whose whole job is to read
// against similar-hued terrain — and which would otherwise be the one thing on
// the ground that fog could not dim.
uniform vec4 surface_emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// One texel per cell, exactly as the ground reads it — see
// `terrain.gdshader`'s own note on why `repeat_enable` carries the seam and why
// white is the right default.
uniform sampler2D fog : hint_default_white, filter_linear, repeat_enable;

varying vec3 fog_at;

void vertex() {
	fog_at = INSTANCE_CUSTOM.xyz;
}

void fragment() {
	float known = mix(1.0, texture(fog, fog_at.xy).r, clamp(fog_at.z, 0.0, 1.0));
	// Specular goes with albedo for the terrain shader's reason: a black but
	// still glossy canopy reads as a rendering fault rather than as ground
	// nobody has walked.
	ALBEDO = albedo.rgb * known;
	EMISSION = surface_emission.rgb * known;
	ROUGHNESS = surface_roughness;
	METALLIC = surface_metallic;
	SPECULAR = 0.5 * known;
}
