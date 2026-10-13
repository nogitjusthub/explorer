// «Огни святого Эльма» — знак скорого удара молнии: голубая корона с дрожащими лучами, мерцает.
// Билборд, аддитивное смешение (светится поверх сцены). Пиксели — по пикселю мира, яркость — ступенями.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float intensity = 1.0;
uniform float seed = 0.0;

const float ART_PX = 0.0625;
varying flat float cells;               // пикселей мира на сторону билборда

void vertex() {
	cells = max(floor(length(MODEL_MATRIX[0].xyz) / ART_PX), 4.0);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
		INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
		INV_VIEW_MATRIX[2],
		MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = (floor(UV * cells) + 0.5) / cells * 2.0 - 1.0;
	float r = length(uv);
	float a = atan(uv.y, uv.x);
	float rays = abs(sin(a * 3.0 + seed + TIME * 17.0)) * abs(sin(a * 5.0 - seed * 1.3 + TIME * 23.0));
	rays = rays * rays * (1.0 - smoothstep(0.1, 1.0, r));
	float core = exp(-r * r * 16.0);
	float halo = exp(-r * r * 3.5) * 0.4;
	float flick = 0.55 + 0.45 * sin(TIME * 47.0 + seed) * sin(TIME * 31.0 + seed * 2.0);
	vec3 col = vec3(0.62, 0.74, 1.0) * (core * 1.6 + rays) + vec3(0.55, 0.35, 0.95) * halo;
	ALBEDO = col;
	ALPHA = floor(clamp((core + halo + rays) * intensity * flick, 0.0, 1.0) * 4.0 + 0.5) / 4.0;
}
