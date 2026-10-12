// Водоворот: тёмная вода на весь круг; волны пены — шесть рукавов спирали под ~15° к окружности
// (среднее между прежней крутой спиралью и кольцами); рукав, если идти по нему к центру, уходит в
// сторону вращения — как сток. Сами рукава стоят, по ним к центру бегут рваные клочья пены — в ту же
// сторону, куда крутится пена по краю и тянет машину (к убыванию угла atan(z, x)). Чёрная воронка в
// центре, едва заметная кромка пены по краю. grow 0…1 — телеграф (бледные рукава) и появление; spin растёт.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform vec4 foam : source_color;
uniform vec4 deep : source_color;
uniform float grow = 0.0;
uniform float spin = 0.0;
const float ARMS = 6.0;
const float WIND = 22.0;                 // ARMS / WIND ≈ tg 15° — наклон рукава к окружности
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	if (r > 1.0) discard;
	float a = atan(p.y, p.x);
	float lr = log(max(r, 0.02));
	// Рукав — линия постоянной фазы: r растёт с углом.
	float ph = (WIND * lr - ARMS * a) / 6.2831853;
	float arm = smoothstep(0.7, 0.84, fract(ph)) * (1.0 - smoothstep(0.88, 1.0, fract(ph)));
	// Клочья бегут по рукавам внутрь: вдоль рукава фаза убывает со временем, угол — тоже.
	float flow = sin(9.0 * lr + 3.0 * a + spin);
	arm *= 0.35 + 0.65 * smoothstep(-0.3, 0.5, flow);
	arm *= smoothstep(0.16, 0.32, r) * (1.0 - smoothstep(0.86, 0.96, r));
	float rim = smoothstep(0.84, 0.9, r) * (1.0 - smoothstep(0.93, 0.99, r));
	float hole = 1.0 - smoothstep(0.16, 0.3, r / max(grow, 0.01));
	float f = max(arm * (0.35 + 0.65 * grow), rim * 0.3);       // кромка — приглушённая
	// Вода темнеет к центру — воронка уходит вглубь.
	vec3 water = deep.rgb * mix(0.4, 1.0, smoothstep(0.1, 0.9, r));
	ALBEDO = mix(water, foam.rgb, f * 0.85);
	float body = 0.7 * grow * (1.0 - smoothstep(0.82, 1.0, r));
	ALPHA = clamp(max(max(body, f * 0.9), hole * 0.97 * grow), 0.0, 1.0) * min(grow * 3.0 + 0.25, 1.0);
}
