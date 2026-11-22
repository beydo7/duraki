shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_always;

#include "res://scenes/match/card_face.gdshaderinc"

void fragment() {
	vec4 c = texture(tex, UV) * tint;
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ROUGHNESS = 0.05;
	SPECULAR = 0.9;
	EMISSION = card_emission(c.rgb, UV, view_vec, TIME);
}
