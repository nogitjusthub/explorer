// Водоворот: спираль пены из трёх рукавов, тёмная воронка в центре, кольцо пены; grow 0…1 — телеграф (круги) и появление.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 foam : source_color;
uniform vec4 deep : source_color;
uniform float grow = 0.0;
uniform float spin = 0.0;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	// Три рукава пены по логарифмической спирали, к центру — тёмная воронка, по краю — кольцо пены.
	float arms = step(0.15, sin(a * 3.0 + log(r + 0.04) * 5.0 + spin));
	float inner = step(0.12 + 0.5 * (1.0 - grow), r);
	float rim = step(0.84, r) * step(r, 0.95);
	float rings = step(0.8, sin(r * 22.0 - spin * 1.5)) * (1.0 - grow) * step(r, 0.95);
	float hole = 1.0 - step(0.3 * grow, r);
	float f = max(max(arms * inner * grow, rim), rings);
	ALBEDO = mix(deep.rgb, foam.rgb, f);
	ALPHA = clamp(max(f * 0.95, max(hole * 0.95, 0.35 * grow)) * min(grow * 3.0, 1.0), 0.0, 1.0);
}
