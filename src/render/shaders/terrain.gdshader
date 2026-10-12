// Рельеф: цвет материала из COLOR.rgb, плоское освещение по производным, страты на стенках.
// COLOR.a: стенка — 1; верх: 0 — обычный грунт, 0.12 — неровный, 0.24 — зыбучий (по нему течёт рябь).
// Верх тайла — пиксельная текстура (M5): атлас tops — по клетке 64×64 текселя на строку (материал,
// неровный, зыбучий — строка из UV.x); клетка накрывает TOPS_TILES × TOPS_TILES тайлов и бесшовна, берётся
// по мировым XZ — узор идёт сквозь тайлы без швов. Значение × TOPS_GAIN умножает цвет материала —
// палитра и погода прежние. Фильтр nearest, без мипмапов.
// Стенка — пласт: цвет по абсолютному ярусу (как раньше) × пиксельная текстура пласта (атлас walls,
// 16×10 текселей на тайл × ярус: кромка сверху, тень у основания, прослойки, трещины, камешки);
// по горизонтали — вдоль стенки, вариант — по хэшу места и яруса.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 strata_a : source_color = vec4(0.46, 0.36, 0.38, 1.0);
uniform vec4 strata_b : source_color = vec4(0.58, 0.44, 0.36, 1.0);
uniform vec4 strata_c : source_color = vec4(0.38, 0.36, 0.48, 1.0);
uniform float grid_strength = 0.12;   // насколько темнее край тайла — ромбы сетки читаются
uniform float grid_width = 0.05;      // ширина линии в долях тайла (~1 пиксель)
uniform float tier_h = 0.65;          // высота яруса — ставит TerrainMaterials из Grid.TIER_H
uniform sampler2D tops : hint_default_white, filter_nearest, repeat_disable;
uniform sampler2D walls : hint_default_white, filter_nearest, repeat_disable;
const float WALL_VARIANTS = 4.0;
const float TOPS_ROWS = 6.0;             // строк (видов поверхности) в атласе
const float TOPS_TILES = 4.0;            // клетка атласа накрывает 4×4 тайла
const float TOPS_GAIN = 1.5;

varying vec3 world_pos;

// Пиксельная текстура верха: бесшовная клетка 4×4 тайла по мировым XZ, строка — вид поверхности.
float tops_detail(vec2 p, float row) {
	vec2 f = clamp(fract(p / TOPS_TILES), 0.0005, 0.9995);
	vec2 uv = vec2(f.x, (row + f.y) / TOPS_ROWS);
	return texture(tops, uv).r * TOPS_GAIN;
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
		albedo *= tops_detail(world_pos.xz, floor(UV.x + 0.5));
		if (COLOR.a >= 0.18) {
			albedo = mire_ripples(albedo, world_pos.xz);
		}
	} else {
		// Стенка: полоса цвета по абсолютному ярусу — высота читается по числу полос; поверх — текстура
		// пласта. Вдоль стенки — мировая координата по оси, лежащей в её плоскости.
		float level = world_pos.y / tier_h + 0.001;
		float tier = floor(level);
		float k = mod(tier, 3.0);
		vec3 s = k < 0.5 ? strata_a.rgb : (k < 1.5 ? strata_b.rgb : strata_c.rgb);
		vec3 wn = (INV_VIEW_MATRIX * vec4(n, 0.0)).xyz;
		float along = abs(wn.x) > abs(wn.z) ? world_pos.z : world_pos.x;
		float variant = min(floor(vhash(vec2(floor(along), tier) + 0.71) * WALL_VARIANTS), WALL_VARIANTS - 1.0);
		vec2 wuv = vec2((variant + clamp(fract(along), 0.001, 0.999)) / WALL_VARIANTS, clamp(1.0 - fract(level), 0.001, 0.999));
		albedo = s * (0.92 + 0.08 * fract(tier * 0.37)) * texture(walls, wuv).r * TOPS_GAIN;
	}
	float hidden = vis_hidden(world_pos);
	ALBEDO = weather_grade(albedo) * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = weather_color(world_pos) * hidden;
}
