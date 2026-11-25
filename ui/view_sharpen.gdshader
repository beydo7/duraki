shader_type canvas_item;
// Nachschärfen (Unsharp-Mask) nur für die 3D-Ansichten (SubViewportContainer).
// Texte und HUD liegen darüber und bleiben unangetastet – dadurch keine Lichthöfe an der Schrift.
uniform float sharpen = 0.35;

void fragment() {
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec4 c = texture(TEXTURE, UV);
	vec3 n = texture(TEXTURE, UV + vec2(px.x, 0.0)).rgb + texture(TEXTURE, UV - vec2(px.x, 0.0)).rgb
		+ texture(TEXTURE, UV + vec2(0.0, px.y)).rgb + texture(TEXTURE, UV - vec2(0.0, px.y)).rgb;
	COLOR = vec4(clamp(c.rgb + (c.rgb * 4.0 - n) * sharpen * 0.25, 0.0, 1.0), c.a);
}
