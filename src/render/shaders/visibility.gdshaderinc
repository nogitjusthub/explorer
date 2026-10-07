// Круг видимости вокруг машины (туман, пылевая буря): за радиусом — сплошной цвет погоды.
// Глобальные параметры объявлены в project.godot ([shader_globals]), их ставит узел Visibility.
global uniform vec3 vis_center;
global uniform float vis_radius;
global uniform vec4 vis_color;

// 0 — видно, 1 — полностью скрыто погодой.
float vis_hidden(vec3 world_pos) {
	float d = length(world_pos.xz - vis_center.xz);
	return smoothstep(vis_radius - 1.5, vis_radius, d);
}
