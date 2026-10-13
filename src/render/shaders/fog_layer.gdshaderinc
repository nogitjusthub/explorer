// Общее для слоёв облачного шума (MurkLayers): туман, пыль, тучи грозы. Узор привязан к миру и
// течёт со временем; плотность берётся из массы погоды (source 0) или из грозового фронта (source 1).
// Просвет у машины (см. weather_falloff) сдвинут на hole_offset — слой выше земли, и на экране просвет должен
// совпасть с машиной. Пиксель-арт: всё считается в центрах пикселей мира, плотность — 7 ступенями
// (art_snap, art_steps).
uniform vec4 color : source_color = vec4(0.62, 0.66, 0.74, 1.0);
uniform float strength = 0.4;
uniform float scale = 0.08;
uniform vec2 drift = vec2(0.2, 0.1);
uniform int source = 0;
uniform float hole_r = 4.0;
uniform vec2 hole_offset = vec2(0.0);
uniform float fade = 1.0;

varying vec3 layer_pos;

float layer_alpha(vec3 p_in, out float n) {
	vec3 p = art_snap(p_in);
	float dens = source == 0 ? weather_density(p) : storm_shade(p) / max(storm_dark, 0.01);
	n = vfbm(p.xz * scale + drift * TIME);
	if (dens <= 0.0) {
		return 0.0;
	}
	float cloud = smoothstep(0.3, 0.72, n);
	// Рваный край дыры: радиус гуляет по шуму.
	float wobble = (vfbm(p.xz * 0.22 + vec2(TIME * 0.07, 0.0)) - 0.47) * 3.0;
	float hole = weather_falloff(length(p.xz - (vis_center.xz + hole_offset)) - wobble, hole_r);
	// Клочья с чёткими террасами (ступени только у формы облаков), а спад к машине — плавный.
	float shape = floor(cloud * 4.0 + 0.5) / 4.0;
	return strength * art_steps(fade * dens * hole * (0.25 + 0.75 * shape), 7.0, p_in);
}
