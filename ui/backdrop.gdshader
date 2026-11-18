shader_type canvas_item;
// Gemeinsamer Hintergrund: Nachtblau-Verlauf, violetter Lichtkreis mit Ring,
// Scanlines und Vignette.

uniform vec3 top_color : source_color = vec3(0.05, 0.04, 0.10);
uniform vec3 bottom_color : source_color = vec3(0.03, 0.025, 0.06);
uniform vec3 glow_color : source_color = vec3(0.27, 0.19, 0.55);
uniform vec3 ring_color : source_color = vec3(0.55, 0.45, 0.9);
uniform vec2 center = vec2(0.5, 0.5);
uniform float ring_radius = 0.43; // in Bildschirmhöhen
uniform float aspect = 1.7778;
uniform float scanline_strength = 0.07;

void fragment() {
	vec3 col = mix(top_color, bottom_color, UV.y);
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float d = length(p);
	// weiches Leuchten innerhalb des Kreises
	col += glow_color * smoothstep(ring_radius * 1.05, 0.0, d) * 0.85;
	// Ring + Halo
	float ring = smoothstep(0.004, 0.0, abs(d - ring_radius));
	float halo = smoothstep(0.05, 0.0, abs(d - ring_radius)) * 0.25;
	col += ring_color * (ring * 0.55 + halo);
	// Scanlines
	float line = step(0.5, fract(FRAGCOORD.y / 3.0));
	col *= 1.0 - line * scanline_strength;
	// Vignette
	vec2 v = UV - 0.5;
	col *= 1.0 - dot(v, v) * 1.1;
	COLOR = vec4(col, 1.0);
}
