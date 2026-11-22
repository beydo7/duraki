// Gemeinsamer Teil der Kartenvorderseite (siehe card_face.gdshader / card_face_glass.gdshader).
// - Folienglanz (foil): ein Lichtband wandert je nach Blickwinkel und Zeit über die Karte
//   (Trumpf leicht, Goldkarte kräftig, Glückskarte grün, Glas irisierend).
// - Lichtreflex (shine): weicher Glanzpunkt an der Mausposition, wenn die Karte gehovert wird.
// - glow: leichtes Leuchten für spielbare Karten.

uniform sampler2D tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float foil = 0.0;
uniform vec3 foil_color : source_color = vec3(1.0, 0.85, 0.5);
uniform float rainbow = 0.0;
uniform vec2 shine_uv = vec2(0.5, 0.5);
uniform float shine = 0.0;
uniform float glow = 0.0;
uniform vec3 glow_color : source_color = vec3(1.0, 0.9, 0.62);
uniform float rough = 0.8;

varying vec3 view_vec;

void vertex() {
	vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	view_vec = INV_VIEW_MATRIX[3].xyz - world_pos;
}

// view: Richtung zur Kamera (Welt), time: TIME (Built-ins gibt es nur in vertex/fragment)
vec3 card_emission(vec3 base, vec2 uv, vec3 view, float time) {
	vec3 e = vec3(0.0);
	if (foil > 0.0) {
		vec3 v = normalize(view);
		float phase = dot(v, vec3(0.8, 0.25, 0.55)) * 7.0 + (uv.x * 1.3 + uv.y * 0.9) * 3.2 + time * 0.45;
		float band = pow(max(0.0, sin(phase)), 10.0);
		float band2 = pow(max(0.0, sin(phase * 0.5 + 1.7)), 24.0) * 0.6;
		float lum = dot(base, vec3(0.299, 0.587, 0.114));
		vec3 col = foil_color;
		if (rainbow > 0.0) {
			vec3 rb = 0.55 + 0.45 * cos(6.2831 * (phase * 0.12 + vec3(0.0, 0.33, 0.67)));
			col = mix(col, rb, rainbow);
		}
		e += col * (band + band2) * foil * (0.25 + lum * 1.2);
	}
	if (shine > 0.0) {
		vec2 d = (uv - shine_uv) * vec2(1.0, 1.4);
		e += glow_color * shine * exp(-dot(d, d) * 14.0) * 0.55;
	}
	e += glow_color * glow * 0.1;
	return e;
}
