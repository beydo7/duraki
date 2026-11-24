shader_type spatial;
render_mode blend_mix, cull_back;

#include "res://scenes/match/card_face.gdshaderinc"

// Glaskarte: das Glasbild liegt auf dunklem Grund (wie in der Hand vor dunklem Hintergrund).
// Vorher war sie fast ganz durchsichtig und wirkte auf dem hellen Filz einfach weiß.
uniform vec3 base_color : source_color = vec3(0.07, 0.08, 0.16);

void fragment() {
	vec4 c = texture(tex, UV) * tint;
	vec3 col = mix(base_color, c.rgb, c.a);
	ALBEDO = col;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	EMISSION = card_emission(col, UV, view_vec, TIME);
}
