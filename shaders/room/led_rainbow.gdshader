// Бегущая RGB-лента для LED-полос. Ориентации не важны:
// волна идёт по мировым (x + z), поэтому одинакова на всех полосах.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 color_a : source_color = vec4(1.0, 0.15, 0.75, 1.0);
uniform vec4 color_b : source_color = vec4(0.15, 0.75, 1.0, 1.0);
uniform float speed = 2.0;
uniform float scale = 2.5;
uniform float glow = 2.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = (wpos.x + wpos.z) * scale - TIME * speed;
	float k = 0.5 + 0.5 * sin(t * 6.28318);
	vec3 col = mix(color_a.rgb, color_b.rgb, k);
	ALBEDO = col;
	EMISSION = col * glow;
}
