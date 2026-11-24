shader_type canvas_item;
// Bild-Nachbearbeitung über dem ganzen Spiel (Autoload Settings, CanvasLayer 120):
//  - Schärfe: leichtes Nachschärfen (Unsharp-Mask) für ein klareres Bild
//  - Retro (wie Balatro): leichte Röhrenwölbung, feine Zeilen, Farbsaum, dunkle Ecken.
//    Die groben Pixel macht nur die 3D-Welt (UIKit.fit_viewport) – Texte bleiben lesbar.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sharpen = 0.35;
uniform float retro = 0.0;

vec3 sharpened(vec2 uv, vec2 px, float amount) {
	vec3 col = texture(screen_tex, uv).rgb;
	if (amount <= 0.0) return col;
	vec3 n = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb + texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
	return clamp(col + (col * 4.0 - n) * amount * 0.25, 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	if (retro > 0.5) {
		vec2 c = uv * 2.0 - 1.0;
		c *= 1.0 + dot(c, c) * 0.022;
		uv = c * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		} else {
			float ca = 0.0008;
			vec3 col = sharpened(uv, px, 0.3);
			col.r = mix(col.r, texture(screen_tex, uv + vec2(ca, 0.0)).r, 0.6);
			col.b = mix(col.b, texture(screen_tex, uv - vec2(ca, 0.0)).b, 0.6);
			float rows = 1.0 / px.y / 3.0;                                 // eine Zeile je 3 Bildpunkte
			col *= 0.92 + 0.08 * sin(uv.y * rows * 6.28318);
			vec2 v = uv * (1.0 - uv);
			col *= clamp(pow(v.x * v.y * 18.0, 0.2), 0.0, 1.0);
			col = col * vec3(1.03, 1.0, 0.95) * 1.06;
			COLOR = vec4(col, 1.0);
		}
	} else {
		COLOR = vec4(sharpened(uv, px, sharpen), 1.0);
	}
}
