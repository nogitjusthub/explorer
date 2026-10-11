// Знак посадки челнока: круг размером с корпус, косые полосы и обод; pulse — мерцание, flow — бег полос.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 color : source_color;
uniform float pulse = 1.0;
uniform float flow = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float stripes = step(0.5, fract((p.x + p.y) * 2.2 + flow));
	float rim = step(0.84, r);
	ALBEDO = color.rgb;
	ALPHA = color.a * max(rim, 0.22 + stripes * 0.5) * pulse;
}
