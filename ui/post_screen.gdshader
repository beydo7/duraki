shader_type canvas_item;
// Bild-Nachbearbeitung über dem ganzen Spiel (Autoload Settings, CanvasLayer 120):
// leichtes Nachschärfen (Unsharp-Mask) für ein klareres Bild.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sharpen = 0.35;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 col = texture(screen_tex, uv).rgb;
	vec3 n = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb + texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
	COLOR = vec4(clamp(col + (col * 4.0 - n) * sharpen * 0.25, 0.0, 1.0), 1.0);
}
