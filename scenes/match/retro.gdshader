shader_type canvas_item;
// Retro-Look: wenige Farbstufen + geordnetes Dithering (Bayer 4x4) + Vignette.
// Wird auf den SubViewportContainer gelegt, der die 3D-Welt in niedriger Auflösung zeigt.

uniform float color_levels = 18.0;
uniform float dither_strength = 0.9;
uniform float pixel_size = 3.0; // = stretch_shrink des Containers
uniform float vignette = 0.55;
uniform vec3 tint : source_color = vec3(1.0, 0.94, 0.88);

float bayer(ivec2 p) {
	int m[16] = int[](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return float(m[(p.y & 3) * 4 + (p.x & 3)]) / 16.0 - 0.5;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	ivec2 cell = ivec2(floor(FRAGCOORD.xy / pixel_size));
	vec3 col = c.rgb * tint;
	col += bayer(cell) * dither_strength / color_levels;
	col = floor(col * color_levels + 0.5) / color_levels;
	vec2 d = UV - 0.5;
	col *= 1.0 - dot(d, d) * vignette * 2.0;
	COLOR = vec4(col, 1.0);
}
