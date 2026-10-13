// Следы колёс и гусениц (VehicleTrail): отпечаток — плоский квад на земле, затемняет её умножением.
// Пиксели — сетка рельефа (1/16 тайла по мировым XZ): каждый тексель берётся по своему центру, поэтому края
// следа и рисунок протектора ложатся ступеньками в пиксели текстуры земли, как будто след — её часть.
// INSTANCE_CUSTOM: x — вид (0 — колесо, 1 — гусеница), y — путь вдоль колеи до начала отпечатка, z — его
// длина, w — время появления. Гаснет за mark_s секунд и дальше far тайлов от машины (center); где
// земля скрыта погодой — не виден.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform float now = 0.0;
uniform float mark_s = 16.0;
uniform float far = 13.0;
uniform vec3 center = vec3(0.0);

const float TEXELS = 16.0;              // текселей рельефа на тайл

varying vec3 world_pos;
varying mat4 to_local;                  // мир → квад отпечатка; в fragment() MODEL_MATRIX — без экземпляра
varying flat vec4 info;
varying flat float depth;               // сила следа: 0…1 (материал), в COLOR.a

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	to_local = inverse(MODEL_MATRIX);
	info = INSTANCE_CUSTOM;
	depth = COLOR.a;
}

void fragment() {
	vec2 c = (floor(world_pos.xz * TEXELS) + 0.5) / TEXELS;      // центр текселя рельефа
	vec3 local = (to_local * vec4(c.x, world_pos.y, c.y, 1.0)).xyz;
	if (abs(local.x) > 0.5 || local.z < -0.5 || local.z >= 0.5) {
		discard;
	}
	float along = info.y + (local.z + 0.5) * info.z;
	float step_t = floor(along * TEXELS);
	float dark;
	if (info.x < 0.5) {
		dark = mod(step_t, 3.0) == 0.0 ? 0.5 : 0.66;           // колесо: шашки протектора
	} else {
		dark = mod(step_t, 2.0) == 0.0 ? 0.48 : 0.7;           // гусеница: траки поперёк
	}
	float age = now - info.w;
	float fade = (1.0 - smoothstep(mark_s * 0.6, mark_s, age))
			* (1.0 - smoothstep(far - 3.0, far, distance(world_pos.xz, center.xz)));
	fade = floor(fade * 4.0 + 0.999) / 4.0;                   // гаснет ступенями — без плавных полутонов
	float k = mix(1.0, dark, depth * fade * (1.0 - vis_hidden(world_pos)));
	ALBEDO = vec3(k);
}
