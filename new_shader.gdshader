shader_type canvas_item;

uniform vec4 scope_color : source_color = vec4(0.04, 0.05, 0.07, 1.0);
uniform float inner_radius : hint_range(0.1, 0.6) = 0.38;
uniform float vignette_softness : hint_range(0.01, 0.2) = 0.04;
uniform vec4 reticle_color : source_color = vec4(0.08, 0.08, 0.08, 0.95);

void fragment() {
    // Приводим экранные координаты к квадратному соотношению с центром в (0, 0)
    vec2 resolution = 1.0 / SCREEN_PIXEL_SIZE;
    vec2 uv = (FRAGCOORD.xy - resolution * 0.5) / min(resolution.x, resolution.y);

    float dist = length(uv);

    // Маска черного круга (виньетка снайпера)
    float mask = smoothstep(inner_radius, inner_radius + vignette_softness, dist);

    // Тонкие риски прицела (сетка)
    float line_width = 0.0012;
    float h_line = step(abs(uv.y), line_width) * step(dist, inner_radius);
    float v_line = step(abs(uv.x), line_width) * step(dist, inner_radius);
    float reticle = clamp(h_line + v_line, 0.0, 1.0);

    // Центр-точка
    float center_dot = step(dist, 0.0035);

    // Финальный цвет
    vec4 final_color = scope_color;
    final_color.a = mask;

    if (dist < inner_radius) {
        if (reticle > 0.5 || center_dot > 0.5) {
            final_color = reticle_color;
        } else {
            final_color.a = 0.0; // Внутри линзы полная прозрачность для обзора
        }
    }

    COLOR = final_color;
}