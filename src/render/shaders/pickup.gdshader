// Находки: вращаются, покачиваются и вспыхивают (анимация в шейдере — без скриптов на каждую).
// Без освещения сцены: собственное простое затенение, чтобы цвет читался на любом грунте;
// тёмный контур — вторым проходом (pickup_outline.gdshader).
// Пиксельный узор (M5) — по координатам меша до поворота (держится на находке), сетка — пиксель мира:
// 1 — кристалл (искры внутри, блик у вершины), 2 — образец (тёмный поясок со светлой меткой),
// 3 — ядро (светлые кольца-разряды бегут снизу вверх), 4 — шестерёнка (тёмная ступица, светлая фаска
// зубьев), 5 — канистра (выпуклый крест на боках, тёмная крышка горлышка).
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform float glow = 0.5;
uniform int pattern = 0;
uniform float size = 0.3;               // размер находки (PickupKind.size): узор — в долях от него

varying vec3 world_pos;
varying vec3 obj_pos;
varying vec3 obj_nrm;
varying float shade;
varying float flash;

void vertex() {
	// Фаза от позиции экземпляра — соседние находки не мигают в такт.
	vec3 origin = MODEL_MATRIX[3].xyz;
	obj_pos = VERTEX / size;
	obj_nrm = NORMAL;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
	float a = TIME * 1.6 + phase;
	mat2 r = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xz = r * VERTEX.xz;
	NORMAL.xz = r * NORMAL.xz;
	VERTEX.y += sin(TIME * 2.2 + phase) * 0.05;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	shade = 0.55 + 0.45 * max(dot(n, normalize(vec3(-0.4, 0.8, 0.3))), 0.0);
	flash = pow(max(sin(TIME * 2.5 + phase), 0.0), 12.0);
}

// Яркость узора в точке p (координаты меша в долях size), n — нормаль меша.
float detail(vec3 p, vec3 n) {
	float PX = 0.0625 / size;                         // пиксель мира (Grid.ART_PX) в долях size
	vec3 q = floor(p / PX);
	if (pattern == 1) {                               // кристалл
		if (p.y > 0.55) {
			return 1.25;
		}
		return vhash(q.xz + q.y * 7.1) > 0.9 ? 1.2 : 1.0;
	} else if (pattern == 2) {                        // образец
		if (abs(p.y) < 0.12) {
			float col = floor((atan(p.z, p.x) / 6.2831853 + 0.5) * 8.0);
			return col == 0.0 && abs(p.y) < 0.06 ? 1.3 : 0.55;
		}
		return 1.0;
	} else if (pattern == 3) {                        // ядро
		return fract(p.y * 2.5 - TIME * 0.8) < 0.14 ? 1.4 : 0.95;
	} else if (pattern == 4) {                        // шестерёнка
		float r = length(p.xz);
		if (r < 0.26) {
			return 0.62;
		}
		return n.y > 0.5 && r > 0.5 ? 1.15 : 1.0;
	} else if (pattern == 5) {                        // канистра
		if (p.y > 0.47) {
			return p.x > 0.15 ? 0.45 : 1.0;           // крышка горлышка; ручка — как бак
		}
		if (abs(n.z) > 0.7) {
			float x = abs(p.x) / 0.36;
			float y = abs(p.y) / 0.45;
			return abs(x - y) < 0.14 && x < 0.85 ? 1.18 : 1.0;
		}
		return 1.0;
	}
	return 1.0;
}

void fragment() {
	vec3 c = base_color.rgb * shade * (0.85 + 0.3 * glow) * detail(obj_pos, obj_nrm);
	c = mix(c, vec3(1.0), flash * 0.7);
	ALBEDO = mix(weather_grade(c) * (1.0 - 0.5 * storm_shade(world_pos)), weather_color(world_pos), vis_hidden(world_pos));
}
