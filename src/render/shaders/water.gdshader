// Вода: полупрозрачная, цвет по глубине (COLOR.r — доля от 4 ярусов), лёгкая рябь.
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque, specular_schlick_ggx;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 shallow : source_color = vec4(0.30, 0.78, 0.72, 0.55);
uniform vec4 deep : source_color = vec4(0.04, 0.30, 0.36, 0.88);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec4 c = mix(shallow, deep, COLOR.r);
	float ripple = sin(world_pos.x * 1.7 + TIME * 1.3) * sin(world_pos.z * 1.3 - TIME * 1.1);
	float hidden = vis_hidden(world_pos);
	ALBEDO = (c.rgb + ripple * 0.03) * (1.0 - hidden);
	EMISSION = vis_color.rgb * hidden;
	ALPHA = mix(c.a, 1.0, hidden);
	ROUGHNESS = 0.2;
}
