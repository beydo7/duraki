shader_type canvas_item;
// Weichgezeichneter, abgedunkelter 3D-Raum als Hintergrund für Menüs.

uniform float blur = 2.5;
uniform float darken = 0.55;
uniform float vignette = 0.9;
uniform vec3 tint : source_color = vec3(0.92, 0.88, 1.0);

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE * blur;
	vec3 c = vec3(0.0);
	float wsum = 0.0;
	for (int x = -2; x <= 2; x++) {
		for (int y = -2; y <= 2; y++) {
			float w = exp(-float(x * x + y * y) / 4.0);
			c += texture(TEXTURE, UV + vec2(float(x), float(y)) * px).rgb * w;
			wsum += w;
		}
	}
	c /= wsum;
	c *= tint * (1.0 - darken);
	vec2 d = UV - 0.5;
	c *= 1.0 - dot(d, d) * vignette * 2.0;
	COLOR = vec4(c, 1.0);
}
