// Круг видимости вокруг машины (туман, пылевая буря): за радиусом — сплошной цвет погоды.
// Глобальные параметры объявлены в project.godot ([shader_globals]), их ставит узел Visibility.
global uniform vec3 vis_center;
global uniform float vis_radius;
global uniform vec4 vis_color;

// Тень грозового фронта: круг с рваным краем, его ставит StormFront (storm_radius 0 — фронта нет).
global uniform vec3 storm_center;
global uniform float storm_radius;

// Насколько темнее под облаками: 0 — вне тени, до 0.38 — в глубине.
float storm_shade(vec3 world_pos) {
	if (storm_radius <= 0.0) {
		return 0.0;
	}
	vec2 d = world_pos.xz - storm_center.xz;
	float a = atan(d.y, d.x);
	float edge = storm_radius + 1.2 * sin(a * 5.0 + storm_center.x * 0.3) + 0.7 * sin(a * 11.0 - storm_center.z * 0.2);
	return 0.38 * (1.0 - smoothstep(edge - 2.5, edge, length(d)));
}

// 0 — видно, 1 — полностью скрыто погодой.
float vis_hidden(vec3 world_pos) {
	float d = length(world_pos.xz - vis_center.xz);
	return smoothstep(vis_radius - 1.5, vis_radius, d);
}
