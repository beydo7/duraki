shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;

#include "res://scenes/match/card_face.gdshaderinc"

void fragment() {
	vec4 c = texture(tex, UV) * tint;
	ALBEDO = c.rgb;
	ROUGHNESS = rough;
	SPECULAR = 0.25;
	EMISSION = card_emission(c.rgb, UV, view_vec, TIME);
}
