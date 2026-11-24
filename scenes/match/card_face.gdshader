shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

#include "res://scenes/match/card_face.gdshaderinc"

void fragment() {
	vec4 c = texture(tex, UV) * tint;
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	EMISSION = card_emission(c.rgb, UV, view_vec, TIME);
	if (burn > 0.0) {
		float edge = burn_mask(UV);
		if (edge < 0.0) discard;
		ALBEDO = mix(ALBEDO, vec3(0.05, 0.02, 0.01), smoothstep(0.0, 0.6, burn) * 0.6 + edge * 0.4);
		EMISSION += vec3(1.0, 0.45, 0.08) * edge * 3.0;
	}
}
