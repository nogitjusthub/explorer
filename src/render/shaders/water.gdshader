// Вода (M5 — пиксель-арт): цвет по глубине (COLOR.r — доля от 4 ярусов) ступенями, без плавного
// градиента; рябь — перебором палитры: текстура cycle хранит в каждом из 16×16 текселей тайла фазу
// волны, шейдер сдвигает её со временем и берёт оттенок из короткой палитры WAVE — гребни бегут по
// воде пиксельными полосами. Глубже 1,2 яруса вода быстро мутнеет: с 2 ярусов дна почти не видно —
// иначе на дне читались тени (ховера, лодки) вдали от них.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 shallow : source_color = vec4(0.30, 0.78, 0.72, 0.55);
uniform vec4 deep : source_color = vec4(0.04, 0.30, 0.36, 0.88);
uniform sampler2D cycle : hint_default_black, filter_nearest, repeat_enable;

const float CYCLE = 8.0;
const float CYCLE_SPEED = 4.0;          // шагов палитры в секунду
const float DEPTH_STEPS = 4.0;          // ступеней цвета по глубине
// Палитра волны: впадина темнее, узкий светлый гребень.
const float WAVE[8] = float[8](1.0, 0.98, 0.95, 0.93, 0.95, 0.99, 1.04, 1.1);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float depth = floor(COLOR.r * DEPTH_STEPS + 0.5) / DEPTH_STEPS;
	vec4 c = mix(shallow, deep, depth);
	float idx = floor(texture(cycle, world_pos.xz).r * CYCLE);
	int step = int(mod(idx + floor(TIME * CYCLE_SPEED), CYCLE));
	float hidden = vis_hidden(world_pos);
	ALBEDO = weather_grade(c.rgb * WAVE[step]) * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = weather_color(world_pos) * hidden;
	float murk = mix(c.a, 0.96, smoothstep(0.3, 0.5, COLOR.r));
	ALPHA = mix(murk, 1.0, hidden);
	ROUGHNESS = 0.2;
}
