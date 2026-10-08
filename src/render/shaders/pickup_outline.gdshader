// Контур находок: копия меша, раздутая по нормалям, рисуется изнанкой тёмным цветом.
// Анимация повторяет pickup.gdshader, иначе контур отстанет от фигуры.
shader_type spatial;
render_mode unshaded, cull_front;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 outline_color : source_color = vec4(0.08, 0.04, 0.1, 1.0);
uniform float width = 0.03;

varying vec3 world_pos;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	float phase = fract(sin(dot(origin.xz, vec2(12.9898, 78.233))) * 43758.5453) * 6.2832;
	float a = TIME * 1.6 + phase;
	mat2 r = mat2(vec2(cos(a), -sin(a)), vec2(sin(a), cos(a)));
	VERTEX.xz = r * VERTEX.xz;
	NORMAL.xz = r * NORMAL.xz;
	VERTEX += normalize(NORMAL) * width;
	VERTEX.y += sin(TIME * 2.2 + phase) * 0.05;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	ALBEDO = mix(outline_color.rgb, vis_color.rgb, vis_hidden(world_pos));
}
