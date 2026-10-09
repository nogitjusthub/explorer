// Рельеф: цвет материала из COLOR.rgb, плоское освещение по производным, страты на стенках.
// COLOR.a: стенка — 1; верх: 0 — обычный грунт, 0.12 — неровный (контрастные точки камней),
// 0.24 — зыбучий (влажный, по нему течёт рябь).
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

// Неровный грунт: в каждой из 4×4 клеток тайла — камешек (светлая точка с тенью) с вероятностью 70%.
vec3 rough_stones(vec3 albedo, vec2 p) {
	vec2 cell = floor(p * 4.0);
	vec2 local = fract(p * 4.0);
	if (vhash(cell) < 0.3) {
		return albedo * 0.93;
	}
	vec2 c = vec2(0.3, 0.3) + 0.4 * vec2(vhash(cell + 3.1), vhash(cell + 7.7));
	float r = 0.17 + 0.13 * vhash(cell + 11.3);
	float stone = step(length(local - c), r);
	float shadow = step(length(local - c - vec2(0.09, 0.09)), r) * (1.0 - stone);
	return albedo * (0.93 - 0.33 * shadow) + (albedo * 0.55 + vec3(0.07)) * stone;
}

// Зыбучий грунт: темнее и холоднее (влажный), по нему медленно текут волнистые тёмные штрихи.
vec3 mire_ripples(vec3 albedo, vec2 p) {
	vec3 wet = albedo * vec3(0.8, 0.82, 0.92);
	float ph = (p.x + p.y) * 6.0 + sin((p.x - p.y) * 2.6) * 1.4 - TIME * 1.2;
	float w = sin(ph);
	return wet * (w > 0.8 ? 0.7 : (w < -0.9 ? 1.12 : 1.0));
}

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
		if (COLOR.a > 0.06 && COLOR.a < 0.18) {
			albedo = rough_stones(albedo, world_pos.xz);
		} else if (COLOR.a >= 0.18) {
			albedo = mire_ripples(albedo, world_pos.xz);
		}
	} else {
		// Стенка: полоса цвета по абсолютному ярусу — высота читается по числу полос.
		float tier = floor(world_pos.y / tier_h + 0.001);
		float k = mod(tier, 3.0);
		vec3 s = k < 0.5 ? strata_a.rgb : (k < 1.5 ? strata_b.rgb : strata_c.rgb);
		albedo = s * (0.92 + 0.08 * fract(tier * 0.37));
	}
	float hidden = vis_hidden(world_pos);
	ALBEDO = weather_grade(albedo) * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = weather_color(world_pos) * hidden;
}
