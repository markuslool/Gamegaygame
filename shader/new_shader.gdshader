shader_type canvas_item;

// Настройки цвета и энергии
uniform vec4 base_color : source_color = vec4(0.0, 0.4, 0.8, 0.3);
uniform vec4 hex_color : source_color = vec4(0.0, 0.9, 1.0, 1.0);
uniform vec4 wave_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

// Параметры сетки
uniform float hex_scale : hint_range(5.0, 100.0) = 25.0;
uniform float line_thickness : hint_range(0.01, 0.2) = 0.06;

// Анимация волны энергии
uniform float wave_speed : hint_range(0.1, 10.0) = 2.0;
uniform float wave_frequency : hint_range(1.0, 20.0) = 8.0;

// Математика для генерации шестиугольной сетки (Hex grid)
vec4 hex_coords(vec2 uv) {
    vec2 r = vec2(1.0, 1.7320508); // 1.7320508 approx sqrt(3)
    vec2 h = r * 0.5;
    vec2 a = mod(uv, r) - h;
    vec2 b = mod(uv - h, r) - h;
    vec2 gv = dot(a, a) < dot(b, b) ? a : b;
    vec2 id = uv - gv;
    
    // Вычисление расстояния до ребер шестиугольника
    vec2 p = abs(gv);
    float d = max(dot(p, normalize(r)), p.x);
    
    return vec4(gv, id.x * 11.0 + id.y, 0.5 - d);
}

void fragment() {
    // Берём альфа-канал исходной текстуры (если применили к спрайту)
    vec4 tex = texture(TEXTURE, UV);
    
    // Центрируем UV для правильного масштабирования
    vec2 centered_uv = (UV - vec2(0.5)) * hex_scale;
    
    // Получаем координаты и дистанцию до края соты
    vec4 hex = hex_coords(centered_uv);
    float dist_to_edge = hex.w;

    // --- 1. Рисуем границы сот ---
    float edge = smoothstep(0.0, line_thickness, dist_to_edge);
    float hex_lines = 1.0 - edge;

    // --- 2. Динамическая волна энергии ---
    // Бегущая волна от центра к краям
    float dist_from_center = length(UV - vec2(0.5));
    float wave = sin(dist_from_center * wave_frequency - TIME * wave_speed);
    wave = smoothstep(0.4, 0.9, wave); // Делаем пики волны чёткими и яркими

    // --- 3. Искажение и мерцание отдельных сот ---
    float cell_noise = sin(hex.z * 12.0 + TIME * 3.0) * 0.5 + 0.5;

    // --- 4. Компоновка без Bloom ---
    // Смешиваем базовый цвет фона сотов, линий и проходящей волны
    vec3 final_rgb = mix(base_color.rgb, hex_color.rgb, hex_lines);
    final_rgb = mix(final_rgb, wave_color.rgb, wave * (hex_lines + cell_noise * 0.3));

    // Прозрачность зависит от границ объекта, сетки и волны
    float final_alpha = base_color.a + (hex_lines * hex_color.a) + (wave * 0.6);
    final_alpha *= tex.a; // Учитываем форму спрайта

    COLOR = vec4(final_rgb, final_alpha);
}