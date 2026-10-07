// Рельеф: цвет материала из COLOR.rgb, плоское освещение по производным, страты на стенках.
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform vec4 strata_a : source_color = vec4(0.46, 0.36, 0.38, 1.0);
uniform vec4 strata_b : source_color = vec4(0.58, 0.44, 0.36, 1.0);
uniform vec4 strata_c : source_color = vec4(0.38, 0.36, 0.48, 1.0);

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Нормаль грани из производных позиции; разворачиваем к камере, чтобы не зависеть от знака dFdy.
	vec3 n = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(n, VIEW) < 0.0) {
		n = -n;
	}
	NORMAL = n;
	vec3 albedo = COLOR.rgb;
	if (COLOR.a > 0.5) {
		// Стенка: полоса цвета по абсолютному ярусу — высота читается по числу полос.
		float tier = floor(world_pos.y / 0.5 + 0.001);
		float k = mod(tier, 3.0);
		vec3 s = k < 0.5 ? strata_a.rgb : (k < 1.5 ? strata_b.rgb : strata_c.rgb);
		albedo = s * (0.92 + 0.08 * fract(tier * 0.37));
	}
	float hidden = vis_hidden(world_pos);
	ALBEDO = albedo * (1.0 - hidden);
	EMISSION = vis_color.rgb * hidden;
}
