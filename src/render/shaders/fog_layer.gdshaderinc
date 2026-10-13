// Общее для слоёв облачного шума (MurkLayers): туман, пыль, тучи грозы. Узор привязан к миру и
// течёт со временем; плотность берётся из массы погоды (source 0) или из грозового фронта (source 1).
// Просвет у машины (см. weather_falloff) сдвинут на hole_offset — слой выше земли, и на экране просвет должен
// совпасть с машиной. Пиксель-арт: всё считается в центрах пикселей мира, плотность — 7 ступенями
// (art_snap, art_steps).
// Слои — во весь экран, их 3–5, а масса обычно занимает часть кадра: сначала плотность, и где слой не
// дотянет до первой ступени даже при самом густом облаке и без просвета — прозрачно, без шума облаков
// (vfbm — 4 октавы шума). Край просвета (тоже vfbm) — только у самого просвета. Картинка — та же.
uniform vec4 color : source_color = vec4(0.62, 0.66, 0.74, 1.0);
uniform float strength = 0.4;
uniform float scale = 0.08;
uniform vec2 drift = vec2(0.2, 0.1);
uniform int source = 0;
uniform float hole_r = 4.0;
uniform vec2 hole_offset = vec2(0.0);
uniform float fade = 1.0;

varying vec3 layer_pos;

// Край просвета гуляет по шуму не больше чем на столько тайлов: (vfbm − 0,47) × 3, vfbm ∈ [0; 0,9375].
const float HOLE_WOBBLE_MAX = 1.41;

float layer_alpha(vec3 p_in, out float n) {
	n = 0.0;
	if (fade <= 0.0) {
		return 0.0;
	}
	vec3 p = art_snap(p_in);
	float dens = fade * (source == 0 ? weather_density(p) : storm_shade(p) / max(storm_dark, 0.01));
	// Множители ниже (просвет и форма облака) не больше 1, art_steps не убывает: здесь 0 — и итог 0.
	if (art_steps(dens, 7.0, p_in) <= 0.0) {
		return 0.0;
	}
	n = vfbm(p.xz * scale + drift * TIME);
	float cloud = smoothstep(0.3, 0.72, n);
	// Рваный край дыры: радиус гуляет по шуму. Дальше hole_r + 3 + HOLE_WOBBLE_MAX просвета нет при любом
	// шуме (weather_falloff = 1) — шум не нужен.
	float r = length(p.xz - (vis_center.xz + hole_offset));
	float wobble = 0.0;
	if (r < hole_r + 3.0 + HOLE_WOBBLE_MAX + 0.1) {
		wobble = (vfbm(p.xz * 0.22 + vec2(TIME * 0.07, 0.0)) - 0.47) * 3.0;
	}
	float hole = weather_falloff(r - wobble, hole_r);
	// Клочья с чёткими террасами (ступени только у формы облаков), а спад к машине — плавный.
	float shape = floor(cloud * 4.0 + 0.5) / 4.0;
	return strength * art_steps(dens * hole * (0.25 + 0.75 * shape), 7.0, p_in);
}
