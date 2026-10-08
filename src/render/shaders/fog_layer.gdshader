// Слой облачного шума поверх сцены (без теста глубины): туман и пыль над землёй, тучи грозы.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, blend_mix, shadows_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"
#include "res://src/render/shaders/fog_layer.gdshaderinc"

void vertex() {
	layer_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n;
	ALPHA = layer_alpha(layer_pos, n);
	ALBEDO = color.rgb * (0.9 + 0.15 * n);
}
