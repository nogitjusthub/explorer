// Расходящийся круг по воде или илу (илозуб: след макушки) — частица-квад лицом вверх, кольцо рисуется
// пикселями мира. Радиус — масштаб частицы (кривая роста от r0 до r1), округлённый до целого пикселя
// рельефа: круг растёт шагами в пиксель, центр — в центре пикселя. Толщина — width_px пикселей. Чем шире
// круг, тем он прозрачнее — ступенями по четверти, без плавного угасания; у r1 гаснет совсем.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;

const float ART_PX = 0.0625;

uniform vec4 tint : source_color = vec4(1.0);
uniform float width_px = 1.0;
uniform float r0 = 0.15;
uniform float r1 = 0.5;
uniform float alpha = 0.8;

varying vec3 world_pos;
varying vec2 center;
varying float ring_r;
varying float fade;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	center = (floor(MODEL_MATRIX[3].xz / ART_PX) + 0.5) * ART_PX;
	float r = length(MODEL_MATRIX[0].xyz);                      // кольцо — радиуса 1 в осях меша (квад 2,5×2,5 — с запасом): радиус = масштаб
	ring_r = max(round(r / ART_PX), width_px + 1.0) * ART_PX;
	fade = alpha * (1.0 - clamp((r - r0) / max(r1 - r0, 0.001), 0.0, 1.0));
}

void fragment() {
	vec2 c = (floor(world_pos.xz / ART_PX) + 0.5) * ART_PX;
	float d = length(c - center);
	float a = floor(fade * 4.0 + 0.5) / 4.0;
	if (d > ring_r + 0.001 || d <= ring_r - width_px * ART_PX + 0.001 || a <= 0.0) {
		discard;
	}
	ALBEDO = tint.rgb;
	ALPHA = a;
}
