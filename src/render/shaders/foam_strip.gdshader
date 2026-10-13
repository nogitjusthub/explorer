// Пена полосой (Несса: V-след, полоса удара): UV.y — доля длины. Штрихи сдвигаются вдоль полосы (flow),
// к концу пена сходит на нет (tail), полоса открывается от начала (grow). Пиксели — по сетке рельефа,
// прозрачность — ступенями.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

const float ART_PX = 0.0625;
varying vec3 world_pos;
varying mat4 to_local;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	to_local = inverse(MODEL_MATRIX);
}

uniform vec4 foam : source_color = vec4(0.86, 0.97, 0.94, 1.0);
uniform float alpha = 1.0;
uniform float grow = 1.0;
uniform float flow = 0.0;
uniform float dashes = 5.0;
uniform float tail = 1.0;

void fragment() {
	vec2 c = (floor(world_pos.xz / ART_PX) + 0.5) * ART_PX;
	float v = clamp((to_local * vec4(c.x, world_pos.y, c.y, 1.0)).z, 0.0, 1.0);   // полоса: z меша — 0…1
	if (v > grow) {
		discard;
	}
	float dash = step(0.4, fract(v * dashes - flow));
	ALBEDO = foam.rgb;
	ALPHA = floor(clamp(alpha * mix(1.0, 1.0 - v, tail) * mix(0.6, 1.0, dash), 0.0, 1.0) * 4.0 + 0.5) / 4.0;
}
