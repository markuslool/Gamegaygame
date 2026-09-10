// Живой экран: мерцающие колонки кода, сканлайны, бегущая полоса, виньетка.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform vec4 tint : source_color = vec4(0.45, 0.85, 1.0, 1.0);
uniform float speed = 1.0;
uniform float glow = 1.4;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	// Мерцание колонок с разной частотой.
	float col = floor(uv.x * 40.0);
	float tw = 0.6 + 0.4 * sin(TIME * (1.0 + hash(vec2(col, 1.0)) * 3.0) * speed + hash(vec2(col, 2.0)) * 6.28318);
	// Сканлайны.
	float scan = 0.85 + 0.15 * sin(uv.y * 400.0);
	// Бегущая светлая полоса сверху вниз.
	float band = exp(-40.0 * abs(uv.y - fract(0.15 + TIME * 0.15 * speed)));
	vec3 c = tint.rgb * (0.35 + 0.65 * tw) * scan + tint.rgb * band * 0.8;
	// Виньетка по краям экрана.
	float vig = smoothstep(0.0, 0.08, uv.x) * smoothstep(1.0, 0.92, uv.x)
		* smoothstep(0.0, 0.1, uv.y) * smoothstep(1.0, 0.9, uv.y);
	c *= mix(0.4, 1.0, vig);
	ALBEDO = c;
	EMISSION = c * glow;
}
