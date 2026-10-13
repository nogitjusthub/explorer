// Знак посадки челнока: круг размером с корпус, косые полосы и обод; pulse — мерцание, flow — бег полос.
// Пиксели — по сетке рельефа (каждый пиксель мира — по своему центру), мерцание — ступенями.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color;
uniform float pulse = 1.0;
uniform float flow = 0.0;
uniform float size = 2.4;                // сторона плоскости (PlaneMesh)
const float ART_PX = 0.0625;
varying vec3 world_pos;
varying mat4 to_local;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	to_local = inverse(MODEL_MATRIX);
}
void fragment() {
	vec2 c = (floor(world_pos.xz / ART_PX) + 0.5) * ART_PX;
	vec2 p = (to_local * vec4(c.x, world_pos.y, c.y, 1.0)).xz / (size * 0.5);
	float r = length(p);
	if (r > 1.0) discard;
	float stripes = step(0.5, fract((p.x + p.y) * 2.2 + flow));
	float rim = step(0.84, r);
	ALBEDO = color.rgb;
	ALPHA = floor(color.a * max(rim, 0.22 + stripes * 0.5) * pulse * 5.0 + 0.5) / 5.0;
}
