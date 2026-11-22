shader_type canvas_item;
// Stempel-/Tinteneffekt: Farbe ungleichmäßig aufgetragen (Körnung aus ink_grain.png).

uniform sampler2D grain : filter_linear, repeat_enable;
uniform float amount = 0.45;
uniform float scale = 220.0;

void fragment() {
	vec4 c = COLOR;
	float g = texture(grain, FRAGCOORD.xy / scale).r;
	float keep = smoothstep(amount - 0.18, amount + 0.12, g);
	c.a *= mix(0.25, 1.0, keep);
	COLOR = c;
}
