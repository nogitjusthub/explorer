// Погода в шейдерах. Параметры — глобальные (project.godot, [shader_globals]), их ставят угрозы.
//
// Плохая видимость (туман, кислотный туман, пылевая буря) — масса с рваным краем, которая ползёт по
// карте: её центр weather_center, радиус weather_radius (0 — массы нет). Внутри массы видно только
// пузырь weather_clear вокруг машины (vis_center), дальше — цвет погоды vis_color, не глухо
// (weather_max), с медленными разводами. Кислотный туман стелется низом: выше weather_gas_y его нет.
global uniform vec3 vis_center;
global uniform vec4 vis_color;
global uniform vec3 weather_center;
global uniform float weather_radius;
global uniform float weather_clear;
global uniform float weather_gas_y;
global uniform float weather_max;
global uniform float weather_gloom;     // 0…1: насколько приглушены цвета сцены (машина внутри массы)

// Тень грозового фронта: круг с рваным краем, его ставит StormFront (storm_radius 0 — фронта нет).
global uniform vec3 storm_center;
global uniform float storm_radius;
global uniform float storm_dark;

// Пиксель мира (Grid.ART_PX) — тексель рельефа: плавные поля (туман, тень туч, пелена) считаются в центрах
// этих пикселей и ступенями — пиксель-арт без плавных градиентов.
const float ART_PX = 0.0625;

vec3 art_snap(vec3 p) {
	return vec3((floor(p.x / ART_PX) + 0.5) * ART_PX, p.y, (floor(p.z / ART_PX) + 0.5) * ART_PX);
}

// Уровень v (0…1) — ступенями (levels): плоские полосы с краем по пикселям мира, без полутонов. Дизеринг
// не берём — слои тумана в шахматку по пикселю складываются в мелкую сетку. p — на будущее (узор ступеней).
float art_steps(float v, float levels, vec3 p) {
	return clamp(floor(v * levels + 0.5) / levels, 0.0, 1.0);
}

// Шум для облаков и разводов: дешёвый value noise и fbm из 4 октав (≈ 0…0.94).
float vhash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(vhash(i), vhash(i + vec2(1.0, 0.0)), u.x), mix(vhash(i + vec2(0.0, 1.0)), vhash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float vfbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.3);
		a *= 0.5;
	}
	return s;
}

// Приглушённые цвета внутри непогоды: сцена серее и темнее, машина (обычные материалы) — нет.
vec3 weather_grade(vec3 c) {
	float g = dot(c, vec3(0.3, 0.59, 0.11));
	return mix(c, vec3(g), 0.55 * weather_gloom) * (1.0 - 0.28 * weather_gloom);
}

// Насколько темнее под тучами: 0 — вне тени, до storm_dark — в глубине.
float storm_shade(vec3 world_pos) {
	if (storm_radius <= 0.0) {
		return 0.0;
	}
	vec3 q = art_snap(world_pos);
	float wob = (vfbm(q.xz * 0.045 + storm_center.xz * 0.01) - 0.47) * 14.0;
	float d = length(q.xz - storm_center.xz) + wob;
	return storm_dark * art_steps(1.0 - smoothstep(storm_radius - 8.0, storm_radius, d), 4.0, world_pos);
}

// Плотность массы плохой видимости в точке (0…1). CPU-копия — WeatherFront.density().
float weather_density(vec3 p) {
	if (weather_radius <= 0.0) {
		return 0.0;
	}
	// Рваный край: шум в мировых координатах — на большом радиусе край не выглядит ровной дугой.
	float wob = (vfbm(p.xz * 0.045 + weather_center.xz * 0.01) - 0.47) * 14.0;
	float dens = 1.0 - smoothstep(weather_radius - 12.0, weather_radius, length(p.xz - weather_center.xz) + wob);
	if (weather_gas_y > -500.0) {
		dens *= 1.0 - smoothstep(weather_gas_y - 0.2, weather_gas_y + 0.9, p.y);
	}
	return dens;
}

// Как гуще пелена с расстоянием r от машины: лёгкая дымка до clear_r − 2, внятно видно до clear_r,
// полная пелена с clear_r + 2.5 (внешняя треть кадра). Плавно, без ступени.
float weather_falloff(float r, float clear_r) {
	float t = clamp((r - (clear_r - 2.0)) / 4.5, 0.0, 1.0);
	return mix(0.22, 1.0, t * t * (3.0 - 2.0 * t));
}

// Цвет пелены: не ровная заливка, а клубы — светлее и темнее, медленно текут.
vec3 weather_color(vec3 p) {
	float n = vfbm(art_snap(p).xz * 0.07 + vec2(-TIME * 0.06, TIME * 0.045));
	return vis_color.rgb * (0.7 + 0.42 * art_steps(n, 4.0, p));
}

// 0 — видно, до weather_max — скрыто погодой.
float vis_hidden(vec3 p_in) {
	vec3 world_pos = art_snap(p_in);
	float dens = weather_density(world_pos);
	if (dens <= 0.0) {
		return 0.0;
	}
	float r = length(world_pos.xz - vis_center.xz) - (vfbm(world_pos.xz * 0.22 + vec2(TIME * 0.07, 0.0)) - 0.47) * 3.0;
	float bubble = weather_falloff(r, weather_clear);
	// Рваная пелена: местами гуще, местами сквозь неё проглядывает рельеф.
	float billow = 0.55 + 0.45 * smoothstep(0.22, 0.7, vfbm(world_pos.xz * 0.08 + vec2(TIME * 0.05, -TIME * 0.035)));
	// Разводы — в переходной зоне; дальше пелена сплошная (переход широкий — без ступеньки).
	float solid = smoothstep(weather_clear - 0.5, weather_clear + 5.0, r);
	return art_steps(clamp(dens * weather_max * mix(bubble * billow, 1.0, solid), 0.0, 1.0), 6.0, p_in);
}
