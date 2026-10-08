// Находки: вращаются, покачиваются и вспыхивают (анимация в шейдере — без скриптов на каждую).
// Без освещения сцены: собственное простое затенение, чтобы цвет читался на любом грунте;
// тёмный контур — вторым проходом (pickup_outline.gdshader).
shader_type spatial;
render_mode unshaded, cull_back;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform float glow = 0.5;

varying vec3 world_pos;
varying float shade;
varying float flash;

void vertex() {
	// Фаза от позиции экземпляра — соседние находки не мигают в такт.
	vec3 origin = MODEL_MATRIX[3].xyz;
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

void fragment() {
	vec3 c = base_color.rgb * shade * (0.85 + 0.3 * glow);
	c = mix(c, vec3(1.0), flash * 0.7);
	ALBEDO = mix(c * (1.0 - 0.5 * storm_shade(world_pos)), vis_color.rgb, vis_hidden(world_pos));
}
