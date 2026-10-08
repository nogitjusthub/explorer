// Рельеф: цвет материала из COLOR.rgb, плоское освещение по производным, страты на стенках.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 strata_a : source_color = vec4(0.46, 0.36, 0.38, 1.0);
uniform vec4 strata_b : source_color = vec4(0.58, 0.44, 0.36, 1.0);
uniform vec4 strata_c : source_color = vec4(0.38, 0.36, 0.48, 1.0);
uniform float grid_strength = 0.12;   // насколько темнее край тайла — ромбы сетки читаются
uniform float grid_width = 0.05;      // ширина линии в долях тайла (~1 пиксель)
uniform float tier_h = 0.65;          // высота яруса — ставит TerrainMaterials из Grid.TIER_H

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Нормаль грани из производных позиции; разворачиваем к камере, чтобы не зависеть от знака dFdy.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 albedo = COLOR.rgb;
	if (COLOR.a < 0.5) {
		// Верх тайла: тонкая тёмная кромка по краям — изометрическая сетка ромбов.
		vec2 f = fract(world_pos.xz);
		float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		albedo *= 1.0 - grid_strength * (1.0 - step(grid_width, edge));
	} else {
		// Стенка: полоса цвета по абсолютному ярусу — высота читается по числу полос.
		float tier = floor(world_pos.y / tier_h + 0.001);
		float k = mod(tier, 3.0);
		vec3 s = k < 0.5 ? strata_a.rgb : (k < 1.5 ? strata_b.rgb : strata_c.rgb);
		albedo = s * (0.92 + 0.08 * fract(tier * 0.37));
	}
	float hidden = vis_hidden(world_pos);
	ALBEDO = weather_grade(albedo) * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = vis_color.rgb * hidden;
}
