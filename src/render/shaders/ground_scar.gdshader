// Временные следы угроз на земле (GroundScars): смерч — полоса содранного грунта, молния — выжженное пятно.
// Плоский квад на земле затемняет её умножением; пиксели — сетка рельефа (1/16 тайла по мировым XZ), край рваный
// по хэшу текселя — след ложится в пиксели текстуры земли. INSTANCE_CUSTOM: x — вид (0 — полоса, 1 — пятно),
// y — зерно рисунка, w — время появления. Гаснет за life_s ступенями; где земля скрыта погодой — не виден.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform float now = 0.0;
uniform float life_s = 30.0;

const float TEXELS = 16.0;              // текселей рельефа на тайл

varying vec3 world_pos;
varying mat4 to_local;                  // мир → квад следа; в fragment() MODEL_MATRIX — без экземпляра
varying flat vec4 info;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	to_local = inverse(MODEL_MATRIX);
	info = INSTANCE_CUSTOM;
}

float scar_hash(vec2 c, float s) {
	return fract(sin(dot(c, vec2(12.9898, 78.233)) + s * 17.31) * 43758.5453);
}

void fragment() {
	vec2 c = (floor(world_pos.xz * TEXELS) + 0.5) / TEXELS;      // центр текселя рельефа
	vec3 local = (to_local * vec4(c.x, world_pos.y, c.y, 1.0)).xyz;
	float n = scar_hash(floor(world_pos.xz * TEXELS), info.y);
	float dark;
	if (info.x < 0.5) {
		// Полоса: поперёк — край рваный (до четверти ширины), внутри — содранный грунт пятнами двух тонов.
		if (local.z < -0.5 || local.z >= 0.5 || abs(local.x) > 0.5 - 0.22 * n) {
			discard;
		}
		dark = n < 0.35 ? 0.5 : 0.66;
	} else {
		// Пятно: подпалина с сильно рваным краем, к центру темнее — три ступени; не чёрное (иначе читалось как яма).
		float r = length(local.xz) * 2.0;
		if (r > 1.0 - 0.45 * n) {
			discard;
		}
		dark = r < 0.3 ? 0.46 : (r < 0.62 ? 0.6 : 0.74);
	}
	float age = now - info.w;
	float fade = 1.0 - smoothstep(life_s * 0.6, life_s, age);
	fade = floor(fade * 4.0 + 0.999) / 4.0;                   // гаснет ступенями — без плавных полутонов
	float k = mix(1.0, dark, fade * (1.0 - vis_hidden(world_pos)));
	ALBEDO = vec3(k);
}
