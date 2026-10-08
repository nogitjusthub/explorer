// Деревья (MultiMesh): цвет экземпляра в COLOR, светящиеся кроны через glow.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform float glow = 0.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 albedo = base_color.rgb * COLOR.rgb;
	float hidden = vis_hidden(world_pos);
	ALBEDO = albedo * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = albedo * glow * (1.0 - hidden) + vis_color.rgb * hidden;
}
