shader_type canvas_item;
// Bild-Look der 3D-Welt: warme Tönung, Vignette und feines Filmkorn.

uniform float vignette = 0.55;
uniform float grain = 0.025;
uniform vec3 tint : source_color = vec3(1.0, 0.95, 0.9);

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec3 col = texture(TEXTURE, UV).rgb * tint;
	vec2 d = UV - 0.5;
	col *= 1.0 - dot(d, d) * vignette * 2.0;
	col += (rand(FRAGCOORD.xy + fract(TIME) * 100.0) - 0.5) * grain;
	COLOR = vec4(col, 1.0);
}
