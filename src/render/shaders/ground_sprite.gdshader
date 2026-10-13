// Мелочь на земле (M5): пиксельные спрайты травы, кустиков, камней, осколков (MultiMesh на чанк).
// Квад смотрит прямо в камеру, низом на земле (наклонён назад): пиксель спрайта на экране квадратный и
// одного размера с пикселем мира (Grid.ART_PX), как у частиц; стоя вертикально, он был бы сжат по высоте
// и мельче остального. Основание привязано к пиксельной сетке экрана — пиксели не дрожат. Спрайт из атласа по INSTANCE_CUSTOM.x, зеркалится по INSTANCE_CUSTOM.y; цвет — цвет
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
	// Основание — в центр пикселя экрана (орто-камера: пиксель = 2 / (P[1][1] · высота кадра)).
	vec3 o_view = (VIEW_MATRIX * vec4(origin, 1.0)).xyz;
	float pix = 2.0 / (PROJECTION_MATRIX[1][1] * VIEWPORT_SIZE.y);
	o_view.xy = round(o_view.xy / pix) * pix;
	origin = (INV_VIEW_MATRIX * vec4(o_view, 1.0)).xyz;
	VERTEX = origin + INV_VIEW_MATRIX[0].xyz * local.x + INV_VIEW_MATRIX[1].xyz * local.y;
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
