// Ночной город с мерцающими окнами. Текстура города + TIME.
shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D city;
uniform float glow = 1.1;
uniform float speed = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 c = texture(city, UV).rgb;
	// Мерцают только светлые пиксели (окна, луна).
	float lum = (c.r + c.g + c.b) / 3.0;
	float gate = smoothstep(0.25, 0.6, lum);
	vec2 g = floor(UV * vec2(42.0, 32.0));
	float tw = 0.75 + 0.25 * sin(TIME * (1.0 + hash(g) * 2.0) * speed + hash(g.yx) * 6.28318);
	c *= mix(1.0, tw, gate);
	ALBEDO = c;
	EMISSION = c * glow;
}
