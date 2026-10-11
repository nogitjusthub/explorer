// Пена полосой (Несса: V-след, полоса удара): UV.y — доля длины. Штрихи сдвигаются вдоль полосы (flow),
// к концу пена сходит на нет (tail), полоса открывается от начала (grow).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 foam : source_color = vec4(0.86, 0.97, 0.94, 1.0);
uniform float alpha = 1.0;
uniform float grow = 1.0;
uniform float flow = 0.0;
uniform float dashes = 5.0;
uniform float tail = 1.0;

void fragment() {
	float v = UV.y;
	if (v > grow) {
		discard;
	}
	float dash = step(0.4, fract(v * dashes - flow));
	ALBEDO = foam.rgb;
	ALPHA = clamp(alpha * mix(1.0, 1.0 - v, tail) * mix(0.6, 1.0, dash), 0.0, 1.0);
}
