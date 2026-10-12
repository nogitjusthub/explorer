// Мелочь на земле (M5): пиксельные спрайты травы, кустиков, камней, осколков (MultiMesh на чанк).
// Квад стоит вертикально и разворачивается к камере вокруг Y (цилиндрический билборд) — пиксели не
// заваливаются. Спрайт из атласа по INSTANCE_CUSTOM.x, зеркалится по INSTANCE_CUSTOM.y; цвет — цвет
// экземпляра × оттенок спрайта (серый × GAIN). Прозрачность — отсечением (непрозрачный проход).
// Свет — как у земли (нормаль вверх), погода и туман войны — как у рельефа. Теней не отбрасывает:
// тень у основания нарисована в самом спрайте.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_disabled, world_vertex_coords;

#include "res://src/render/shaders/visibility.gdshaderinc"

uniform sampler2D atlas : hint_default_white, filter_nearest, repeat_disable;

const float SPRITES = 8.0;
const float GAIN = 1.5;

varying vec3 world_pos;
varying flat float idx;
varying flat float flip;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 local = VERTEX - origin;                         // квад без поворота: смещение = локальные x, y
	vec3 right = normalize(vec3(INV_VIEW_MATRIX[0].x, 0.0, INV_VIEW_MATRIX[0].z));
	VERTEX = origin + right * local.x + vec3(0.0, local.y, 0.0);
	world_pos = VERTEX;
	NORMAL = vec3(0.0, 1.0, 0.0);
	idx = INSTANCE_CUSTOM.x;
	flip = INSTANCE_CUSTOM.y;
}

void fragment() {
	float u = clamp(flip > 0.5 ? 1.0 - UV.x : UV.x, 0.001, 0.999);
	vec4 t = texture(atlas, vec2((floor(idx + 0.5) + u) / SPRITES, clamp(UV.y, 0.001, 0.999)));
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	NORMAL = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
	vec3 albedo = COLOR.rgb * t.r * GAIN;
	float hidden = vis_hidden(world_pos);
	ALBEDO = weather_grade(albedo) * (1.0 - hidden) * (1.0 - storm_shade(world_pos));
	EMISSION = weather_color(world_pos) * hidden;
}
