shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

// Fallen soldiers (D-20260819-a-casualty-is-visible).
//
// A second compile-time program rather than a branch in unit_anim.gdshader,
// for the reason unit_vat.gdshaderinc's header already records: what a shader
// SAMPLES and WRITES is a compile-time property, and making 26,644 live
// soldiers carry a fog tap to serve the dead would price the exception into
// the rule. Live squads are only ever drawn while visible (D-099), so they
// never needed fog; a corpse is knowledge — drawn forever once seen, like a
// building (D-030/D-101) — and #81's rule therefore applies: everything on
// fogged ground takes the tap.
//
// ## Custom data is REMAPPED here, and that is the point
//
// A corpse layer has one clip and rate zero by construction, so the four
// per-instance floats the live path spends on (clip, phase hash, rate, spare)
// are re-budgeted:
//
//   INSTANCE_CUSTOM.r  fall phase in [0, 1] — written per frame by the CPU
//                      while the man falls, from
//                      clamp((now - event_time) / FALL_SECONDS), then never
//                      again. Derived from the replicated event's time, not
//                      accumulated (D-082's rule; see CorpseLedger).
//   INSTANCE_CUSTOM.g  fog U of the cell the body lies in
//   INSTANCE_CUSTOM.b  fog V
//   INSTANCE_CUSTOM.a  1.0 when gb mean anything; previews leave 0 and draw
//                      fully lit (prop_fog.gdshader's bargain)
//
// The clip the pose samples is a UNIFORM: "death" once the VAT carries one,
// the pose the renderer chose while it does not (D-081's fallback rule — a
// missing clip costs fidelity, never the game).

#include "res://shaders/unit_vat.gdshaderinc"

uniform float corpse_clip = 0.0;
uniform sampler2D fog : hint_default_white, filter_linear, repeat_enable;

varying vec3 corpse_fog;

void vertex() {
	corpse_fog = vec3(INSTANCE_CUSTOM.g, INSTANCE_CUSTOM.b, INSTANCE_CUSTOM.a);
	// Clamped strictly below 1.0: vat_pose wraps phase with fract(), and a
	// settled corpse handed exactly 1.0 would wrap to frame 0 — the whole
	// squad standing back up on the frame the fall completed.
	float phase = min(INSTANCE_CUSTOM.r, 1.0 - 0.5 / frames_per_clip);
	vat_colour = vat_pose(UV2, vec4(corpse_clip, phase, 0.0, 0.0), VERTEX, NORMAL);
}

void fragment() {
	float known = mix(1.0, texture(fog, corpse_fog.xy).r,
		clamp(corpse_fog.z, 0.0, 1.0));
	ALBEDO = vat_albedo() * known;
	ROUGHNESS = 0.85;
}
