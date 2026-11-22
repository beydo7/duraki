shader_type canvas_item;
// Farbiger Schein an den Bildrändern (Gefahr beim Verteidigen, Gold beim Ziel).

uniform vec4 glow_color : source_color = vec4(1.0, 0.25, 0.3, 1.0);
uniform float strength = 0.0;
uniform float width = 0.22;

void fragment() {
	vec2 d = abs(UV - 0.5) * 2.0;
	float edge = max(d.x * 0.85, d.y);
	float g = smoothstep(1.0 - width, 1.0, edge);
	float wobble = 0.85 + 0.15 * sin(TIME * 3.1 + UV.y * 6.0);
	COLOR = vec4(glow_color.rgb, g * strength * wobble);
}
