shader_type canvas_item;
// Bild-Nachbearbeitung über dem ganzen Spiel (Autoload Settings, CanvasLayer 120):
//  - Schärfe: leichtes Nachschärfen (Unsharp-Mask) für ein klareres Bild
//  - Retro (wie Balatro): grobere Pixel, leichte Röhrenwölbung, Zeilen, Farbsaum, weniger Farbstufen
uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sharpen = 0.35;
uniform float retro = 0.0;
uniform float pixel_rows = 360.0; // Retro: so viele „Pixel“-Zeilen hat das Bild

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	if (retro > 0.5) {
		// leichte Wölbung wie ein Röhrenbildschirm
		vec2 c = uv * 2.0 - 1.0;
		c *= 1.0 + dot(c, c) * 0.028;
		uv = c * 0.5 + 0.5;
		if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
			COLOR = vec4(0.0, 0.0, 0.0, 1.0);
		} else {
			float aspect = px.y / px.x;
			vec2 grid = vec2(pixel_rows * aspect, pixel_rows);
			vec2 puv = (floor(uv * grid) + 0.5) / grid;
			float ca = 0.0012;
			vec3 col;
			col.r = texture(screen_tex, puv + vec2(ca, 0.0)).r;
			col.g = texture(screen_tex, puv).g;
			col.b = texture(screen_tex, puv - vec2(ca, 0.0)).b;
			col = floor(col * 28.0 + 0.5) / 28.0;                       // weniger Farbstufen
			float line = 0.86 + 0.14 * sin(uv.y * grid.y * 6.28318);     // Zeilen
			col *= line;
			vec2 v = uv * (1.0 - uv);
			col *= clamp(pow(v.x * v.y * 18.0, 0.22), 0.0, 1.0);        // dunkle Ecken
			col = mix(col, col * vec3(1.03, 1.0, 0.95), 0.6) * 1.08;     // etwas wärmer und heller
			COLOR = vec4(col, 1.0);
		}
	} else {
		vec3 col = texture(screen_tex, uv).rgb;
		if (sharpen > 0.0) {
			vec3 n = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb + texture(screen_tex, uv - vec2(px.x, 0.0)).rgb
				+ texture(screen_tex, uv + vec2(0.0, px.y)).rgb + texture(screen_tex, uv - vec2(0.0, px.y)).rgb;
			col = clamp(col + (col * 4.0 - n) * sharpen * 0.25, 0.0, 1.0);
		}
		COLOR = vec4(col, 1.0);
	}
}
