// Фейковый световой конус под лампой (volumetric-look за копейки).
// Ярко у колбы, гаснет книзу + мягкий силуэт через френеля.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, fog_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.85, 0.65, 1.0);
uniform float intensity = 0.35;
uniform float height = 2.3;

varying float h;

void vertex() {
	// VERTEX во фрагменте — view-space, поэтому высоту снимаем здесь (model-space).
	h = clamp(VERTEX.y / height + 0.5, 0.0, 1.0);
}

void fragment() {
	float fade = h * h;
	float fr = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float a = fade * fr * intensity;
	ALBEDO = color.rgb * a;
	EMISSION = color.rgb * a;
}
