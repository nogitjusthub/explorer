// Деревья (MultiMesh): цвет экземпляра в COLOR, светящиеся кроны через glow.
// Пиксельный узор (M5) — по координатам самого меша (узор держится на дереве), квантованным в сетку
// PX: pattern 1 — кора (продольные бороздки с разрывами, сучки; на торцах поваленного ствола — годичные
// кольца), 2 — коралловая крона (светлые бугорки-полипы, тёмные поры), 3 — грибовидная крона (сверху
// светлые крапины, снизу радиальные пластинки). Узор только меняет яркость цвета — палитра прежняя.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform float glow = 0.0;
uniform int pattern = 0;

const float PX = 0.03;                  // шаг пиксельной сетки узора (в единицах меша)

varying vec3 world_pos;
varying vec3 obj_pos;
varying vec3 obj_nrm;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	obj_pos = VERTEX;
	obj_nrm = NORMAL;
}

float h2(vec2 p) {
	return vhash(p);
}

// Кора: столбцы по окружности ствола — часть из них бороздки (темнее) с разрывами, редкие сучки;
// торцы — годичные кольца.
float bark(vec3 p, vec3 n) {
	if (abs(n.y) > 0.7) {
		float ring = floor(length(p.xz) / (PX * 0.8));
		return mod(ring, 2.0) < 0.5 ? 0.85 : 1.05;
	}
	float col = floor((atan(p.z, p.x) / 6.2831853 + 0.5) * 10.0);
	float row = floor(p.y / PX);
	float k = 1.0;
	if (h2(vec2(col, 3.7)) < 0.4 && h2(vec2(col, row)) > 0.15) {
		k = 0.8;
	}
	if (h2(vec2(col * 1.3, row * 0.7)) > 0.97) {
		k = 0.65;
	}
	return k;
}

// Коралл: ячейки поверхности — светлые полипы и тёмные поры.
float coral(vec3 p) {
	vec3 q = floor(p / PX);
	float r = h2(q.xz + q.y * 17.3);
	return r > 0.88 ? 1.18 : (r < 0.12 ? 0.8 : 1.0);
}

// Гриб: верх шляпки — крапины 2×2 пикселя, низ — радиальные пластинки.
float shroom(vec3 p, vec3 n) {
	if (n.y > 0.4) {
		vec2 c = floor(p.xz / (PX * 2.0));
		return h2(c + 5.1) > 0.82 ? 1.22 : 1.0;
	}
	float col = floor((atan(p.z, p.x) / 6.2831853 + 0.5) * 18.0);
	return mod(col, 2.0) < 0.5 ? 0.82 : 0.98;
}

void fragment() {
	float k = 1.0;
	if (pattern == 1) {
		k = bark(obj_pos, obj_nrm);
	} else if (pattern == 2) {
		k = coral(obj_pos);
	} else if (pattern == 3) {
		k = shroom(obj_pos, obj_nrm);
	}
	vec3 albedo = base_color.rgb * COLOR.rgb * k;
	float hidden = vis_hidden(world_pos);
	albedo = weather_grade(albedo);
	ALBEDO = albedo * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = albedo * glow * (1.0 - hidden) + weather_color(world_pos) * hidden;
}
