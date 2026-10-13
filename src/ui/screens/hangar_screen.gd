class_name HangarScreen
extends CanvasLayer
## Экран перед забегом (GDD §2): трюм челнока на орбите. Три машины стоят на люках в ряд вдоль задней
## стены; выбранная — под прожектором и медленно поворачивается, остальные — тёмные силуэты.
## Под выбранной — характеристики значками (1–5); ни названий классов, ни текстовых описаний.
## Выбор: A / D, стрелки, тап по машине или кнопкам; старт — F / Enter / кнопка: люк раскрывается,
## машина уходит вниз по шахте — дальше сцена десанта. Нужен и вебу: звук включается после действия игрока.
## Выбор и старт щёлкают механическим тумблером; на старте лязгает люк и гудит гидропривод подъёмника. Справа от названия — версия; в правом верхнем углу —
## кнопка-динамик с окошком громкости (VolumeSlider; пока открыто, A / D — громкость, Esc — закрыть).
## Трюм — отдельный мир в SubViewport: свой свет и окружение, игровой мир под экраном не трогаем; под ним —
## непрозрачная подложка, чтобы до первого кадра трюма не просвечивал мир.

signal started

var waiting := false               ## мир ещё грузится: после «Высадки» держим затемнение с надписью
var _loading: Label
signal vehicle_changed(id: StringName)

const VIEW := Vector2i(480, 320)
const SPACING := 1.6                     ## между люками вдоль задней стены
const CAM_SIZE := 3.7
const CAM_ELEVATION_DEG := 38.0
const CAM_YAW_DEG := 15.0                ## почти фронтально: ряд люков на экране почти горизонтален
const BACK_Z := -1.0                     ## задняя стена; люки — по z = 0
const LEFT_X := -(SPACING + 1.1)         ## левая стена
const COLOR_BAY_ON := Color(0.35, 1.0, 0.45)
const COLOR_BAY_OFF := Color(0.45, 0.3, 0.08)
const SPIN := 0.5                        ## рад/с — выбранная машина на поворотном круге
const SPOT_ON := 3.0
const SPOT_FADE_S := 0.18
const SINK_S := 0.7                      ## старт: машина уходит в люк
const FADE_S := 0.3                      ## затемнение до и после
const COLOR_SPOT := Color(1.0, 0.93, 0.8)
const COLOR_STRIP := Color(0.35, 0.6, 1.0)
const COLOR_HAZARD := Color(0.95, 0.72, 0.15)
const PICK_RADIUS_PX := 44.0
const CAPTION := "выбор машины"
const DISPLAY_ORDER: Array[StringName] = [&"tank", &"rover", &"hover"]   ## универсал — в центре
const DEFAULT_ID := &"rover"             ## выбран при открытии трюма
const CAPTION_Y := 52.0                  ## строка «выбор машины» между кнопками «<» и «>»
const HOLE_R := 0.57                     ## проём в полу под створкой: чуть меньше её — без щелей по краю
const SHAFT_SIDES := 8                   ## шахта под люком — восьмигранный колодец
const SHAFT_R := 0.6                     ## радиус, вписанный в грани
const SHAFT_DEPTH := 2.6                 ## дна не видно: сквозь люк глубже ~0,9 не заглянуть
const SHAFT_STEP := 0.25                 ## шаг колец-уступов; огни на направляющих — между ними
const RING_IN := 0.07                    ## уступ кольца внутрь (машины — до 0,53 от оси: не задевают)
const RAIL_IN := 0.04                    ## направляющие на гранях по бокам от дальней
const COLOR_GLOW := Color(1.0, 0.42, 0.12)   ## зарево снизу: там отсек сброса и вход в атмосферу
const GLOW_ON := 1.6

const BEAM_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
uniform float intensity = 0.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float height = 4.0;
varying float k;
void vertex() { k = clamp(VERTEX.y / height + 0.5, 0.0, 1.0); }
void fragment() {
	float edge = abs(dot(NORMAL, VIEW));
	ALBEDO = tint.rgb;
	ALPHA = intensity * tint.a * mix(1.0, 0.25, k) * edge * edge;
}
"""
## Пол с круглыми проёмами под люками (по z = 0, в ряд с шагом hole_step): под створками — шахты.
const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.12, 0.11, 0.15);
uniform vec3 seam : source_color = vec3(0.07, 0.06, 0.09);
uniform float hole_r = 0.0;
uniform float hole_step = 1.0;
uniform float hole_n = 1.0;
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	float c = clamp(round(wp.x / hole_step + (hole_n - 1.0) * 0.5), 0.0, hole_n - 1.0);
	if (length(vec2(wp.x - (c - (hole_n - 1.0) * 0.5) * hole_step, wp.z)) < hole_r) discard;
	vec2 g = abs(fract(wp.xz * 0.5 + 0.5) - 0.5);
	float line = step(0.485, max(g.x, g.y));
	vec2 r = abs(fract(wp.xz * 2.0) - 0.5);
	float rivet = step(length(r), 0.06) * step(0.42, max(g.x, g.y));
	float tone = 0.92 + 0.08 * fract(sin(dot(floor(wp.xz * 0.5), vec2(12.9898, 78.233))) * 43758.5453);
	ALBEDO = mix(base * tone, seam, max(line, rivet * 0.6));
	ROUGHNESS = 0.45;
	METALLIC = 0.5;
}
"""
## Стены шахты: UV.x — метры по периметру, UV.y — глубина. Листы со швами, по верху — жёлтые полосы
## кромки люка; вглубь темнеет, а при спуске снизу разгорается зарево (heat 0..1).
const SHAFT_SHADER := """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.17, 0.16, 0.22);
uniform vec3 seam : source_color = vec3(0.05, 0.045, 0.07);
uniform vec3 hazard : source_color = vec3(0.95, 0.72, 0.15);
uniform vec3 glow : source_color = vec3(1.0, 0.42, 0.12);
uniform float panel = 0.25;
uniform float step_y = 0.25;
uniform float heat = 0.0;
void fragment() {
	float d = UV.y;
	float vx = abs(fract(UV.x / panel) - 0.5);
	float hy = fract(d / step_y + 0.5);
	float line = max(step(0.44, vx), step(0.92, hy));
	vec3 col = mix(base, seam, line);
	float band = step(d, 0.11) * step(0.5, fract((UV.x + d) * 6.0));
	col = mix(col, seam, step(d, 0.11));
	col = mix(col, hazard * 0.7, band);
	float deep = smoothstep(0.05, 1.0, d);
	ALBEDO = col * (1.0 - 0.8 * deep);
	EMISSION = vec3(0.07, 0.075, 0.13) * (1.0 - deep) + hazard * 0.2 * band + glow * heat * deep * deep * 0.45;
	ROUGHNESS = 0.6;
	METALLIC = 0.5;
}
"""
## Огни на направляющих: при старте (run — секунды с нажатия) загораются сверху вниз со вспышкой, по ним
## бежит вниз волна; до старта погашены. Уровень огня — по глубине (UV.y), огни целиком между кольцами.
const SHAFT_LAMP_SHADER := """
shader_type spatial;
render_mode unshaded, shadows_disabled;
uniform vec3 tint : source_color = vec3(0.35, 0.6, 1.0);
uniform float step_y = 0.25;
uniform float run = -1.0;
void fragment() {
	float lvl = floor(UV.y / step_y);
	float t = run - 0.1 - lvl * 0.07;
	float on = step(0.0, t) * step(0.0, run);
	float chase = step(fract(run * 2.2 - lvl * 0.3), 0.3);
	ALBEDO = tint * (0.1 + on * (0.45 + 0.55 * chase)) + vec3(0.8) * on * exp(-max(t, 0.0) * 12.0);
}
"""

var vehicle_ids: Array[StringName] = []
var selected := 0

var _vp: SubViewport
var _cam: Camera3D
var _models: Array[VehicleModels.Model] = []
var _spots: Array[SpotLight3D] = []
var _beams: Array[ShaderMaterial] = []
var _doors: Array[Node3D] = []
var _blobs: Array[Node3D] = []           ## пятна-тени на створках: уходят вместе со створкой
var _shaft_wall: ShaderMaterial          ## общие на все шахты: открывается только люк выбранной
var _shaft_lamps: ShaderMaterial
var _shaft_glow: OmniLight3D             ## зарево снизу в шахте выбранной — подсвечивает машину на спуске
var _light_k: PackedFloat32Array = []    ## яркость прожектора над каждой машиной 0..1
var _ui: Control
var _vol_button: Button                  ## динамик в правом верхнем углу: открывает окошко громкости
var _vol_panel: Control                  ## окошко с регулятором (пока открыто — A / D крутят громкость)
var _vol_slider: VolumeSlider
var _fade: ColorRect
var _toggle_snd: AudioStreamPlayer
var _lift_snd: AudioStreamPlayer          ## старт: лязг люка и гул гидропривода подъёмника
var _leave_t := -1.0
var _emitted := false
var _time := 0.0
var _blinkers: Array[StandardMaterial3D] = []
var _bay_lamps: Array[StandardMaterial3D] = []


func _ready() -> void:
	name = "HangarScreen"
	layer = 20
	# Непрозрачная подложка: пока трюм не отрисовал первый кадр (в браузере — дольше), сквозь пустую
	# картинку SubViewport не видно мира игры за ним.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.03, 0.025, 0.06)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)
	var box := SubViewportContainer.new()
	box.stretch = true
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_vp = SubViewport.new()
	_vp.size = VIEW
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	box.add_child(_vp)
	_build_hold()
	_build_ui()
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	_toggle_snd = AudioStreamPlayer.new()             # выбор машины — щелчок механического тумблера (_click)
	_toggle_snd.volume_db = -10.0
	add_child(_toggle_snd)
	_lift_snd = AudioStreamPlayer.new()
	Sfx.prepare([&"toggle", &"hatch_lift"], true)    # синтез в фоне, первыми (нужны по нажатию, см. _click, _start)
	_lift_snd.volume_db = -6.0
	add_child(_lift_snd)
	_light_k.resize(vehicle_ids.size())
	for i in _light_k.size():
		_light_k[i] = 1.0 if i == selected else 0.0
	_apply_lights(0.0)


# --- Трюм ---------------------------------------------------------------------------------------

func _build_hold() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.018, 0.035)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.4, 0.62)
	env.ambient_light_energy = 0.05
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# Камера — изометрия, но трюм развёрнут почти фронтально: ряд люков вдоль задней стены идёт
	# по экрану почти горизонтально, слева видна боковая стена.
	var yaw := deg_to_rad(CAM_YAW_DEG)
	var el := deg_to_rad(CAM_ELEVATION_DEG)
	var dir := Vector3(sin(yaw) * cos(el), sin(el), cos(yaw) * cos(el))
	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = CAM_SIZE
	_cam.near = 0.5
	_cam.far = 60.0
	var basis := Basis.looking_at(-dir, Vector3.UP)
	var focus := Vector3(0, 0.35, 0) - basis.y * 0.25        # машины чуть выше центра кадра
	_cam.transform = Transform3D(basis, focus + dir * 20.0)
	_vp.add_child(_cam)

	# Контровой свет сверху-сзади: обводит силуэты, пол и стены почти не трогает.
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.55, 1.0)
	rim.light_energy = 0.22
	_vp.add_child(rim)
	rim.look_at_from_position(Vector3(-1.0, 3.0, BACK_Z), Vector3(0, 0, 0.6))

	_build_room()

	# Под каждым люком — шахта (сетка общая); зарево в ней загорается при старте — под выбранной.
	var shaft := _shaft_mesh()
	_shaft_glow = OmniLight3D.new()
	_shaft_glow.light_color = COLOR_GLOW
	_shaft_glow.omni_range = 1.8                       # до пола и стен трюма не достаёт
	_shaft_glow.shadow_enabled = false
	_shaft_glow.visible = false
	_vp.add_child(_shaft_glow)

	var toward := Vector3(dir.x, 0, dir.z).normalized()
	for i in vehicle_ids.size():
		var at := Vector3(SPACING * (i - (vehicle_ids.size() - 1) * 0.5), 0, 0)
		_build_bay(at)
		var well := MeshInstance3D.new()
		well.mesh = shaft
		well.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		well.position = at
		well.rotation.y = yaw                          # дальняя грань — прямо к камере
		_vp.add_child(well)
		var m := VehicleModels.build_plain(vehicle_ids[i])
		m.root.position = at + Vector3(0, m.hover_height, 0)
		var face := toward + Vector3(0.6, 0, 0)        # три четверти: нос к зрителю и чуть вправо
		m.root.rotation.y = atan2(-face.x, -face.z)
		_vp.add_child(m.root)
		_models.append(m)


## Трюм: задняя стена (z = BACK_Z) и левая (x = LEFT_X), рёбра шпангоутов, светящаяся полоса,
## огоньки, ящики в дальнем правом углу. Люки — в ряд вдоль задней стены.
func _build_room() -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = _shader(FLOOR_SHADER)
	if not vehicle_ids.is_empty():
		floor_mat.set_shader_parameter("hole_r", HOLE_R)
		floor_mat.set_shader_parameter("hole_step", SPACING)
		floor_mat.set_shader_parameter("hole_n", float(vehicle_ids.size()))
	_box(Vector3(12, 0.2, 10), Vector3(1.0, -0.1, 3.0), floor_mat)

	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.17, 0.16, 0.22)
	wall.roughness = 0.8
	wall.emission_enabled = true
	wall.emission = Color(0.09, 0.1, 0.18)                 # стены чуть светлее силуэтов
	var rib := StandardMaterial3D.new()
	rib.albedo_color = Color(0.2, 0.19, 0.25)
	rib.roughness = 0.6
	rib.metallic = 0.4
	var strip := StandardMaterial3D.new()
	strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip.albedo_color = COLOR_STRIP
	var hazard := StandardMaterial3D.new()
	hazard.albedo_color = COLOR_HAZARD.darkened(0.45)
	hazard.roughness = 0.7

	const H := 3.2
	_box(Vector3(12, H, 0.2), Vector3(1.0, H * 0.5, BACK_Z - 0.1), wall)
	_box(Vector3(0.2, H, 10), Vector3(LEFT_X - 0.1, H * 0.5, BACK_Z + 5.0), wall)
	# Нижний отбойник и светящаяся полоса по обеим стенам.
	_box(Vector3(12, 0.16, 0.05), Vector3(1.0, 0.08, BACK_Z + 0.025), hazard)
	_box(Vector3(0.05, 0.16, 10), Vector3(LEFT_X + 0.025, 0.08, BACK_Z + 5.0), hazard)
	_box(Vector3(12, 0.05, 0.03), Vector3(1.0, 1.9, BACK_Z + 0.015), strip)
	_box(Vector3(0.03, 0.05, 10), Vector3(LEFT_X + 0.015, 1.9, BACK_Z + 5.0), strip)
	# Шпангоуты: на задней стене — между люками, на левой — с шагом.
	for i in 4:
		_box(Vector3(0.12, H, 0.1), Vector3((i - 1.5) * SPACING, H * 0.5, BACK_Z + 0.05), rib)
	for i in 4:
		_box(Vector3(0.1, H, 0.12), Vector3(LEFT_X + 0.05, H * 0.5, BACK_Z + 1.4 + i * 1.6), rib)
	# Огоньки на левой стене — мигают вразнобой.
	for i in 3:
		var lamp := StandardMaterial3D.new()
		lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lamp.albedo_color = Color(1.0, 0.3, 0.2) if i % 2 == 0 else Color(0.3, 1.0, 0.5)
		_blinkers.append(lamp)
		_box(Vector3(0.03, 0.06, 0.06), Vector3(LEFT_X + 0.02, 1.3, BACK_Z + 0.7 + i * 1.6), lamp)
	# Ящики в дальнем правом углу.
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.3, 0.27, 0.22)
	crate.roughness = 0.9
	var cx := SPACING * 1.5 + 0.15
	_box(Vector3(0.45, 0.35, 0.45), Vector3(cx, 0.175, BACK_Z + 0.3), crate)
	_box(Vector3(0.35, 0.28, 0.35), Vector3(cx + 0.02, 0.49, BACK_Z + 0.3), crate, Vector3(0, 0.3, 0))
	_box(Vector3(0.4, 0.3, 0.4), Vector3(cx + 0.1, 0.15, BACK_Z + 0.85), crate, Vector3(0, -0.2, 0))


## Люк под машиной: жёлтое кольцо, створка над проёмом в полу (уходит при старте, под ней — шахта,
## см. _shaft_mesh); пятно тени, прожектор сверху (без теней — они давали артефакты на гранях) и видимый
## конус луча; над люком на задней стене — лампа отсека: у выбранной горит зелёным.
func _build_bay(at: Vector3) -> void:
	var door := StandardMaterial3D.new()
	door.albedo_color = Color(0.22, 0.21, 0.27)
	door.roughness = 0.5
	door.metallic = 0.5
	_doors.append(_disc(0.58, at + Vector3(0, 0.008, 0), door))
	var blob := StandardMaterial3D.new()
	blob.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	blob.albedo_color = Color(0, 0, 0, 0.55)
	_blobs.append(_disc(0.42, at + Vector3(0, 0.012, 0), blob))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.58
	ring.outer_radius = 0.7
	ring.rings = 24
	ring.ring_segments = 4
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = COLOR_HAZARD
	ring_mat.roughness = 0.6
	ring_mat.emission_enabled = true
	ring_mat.emission = COLOR_HAZARD * 0.2           # кольцо видно и в темноте — по нему читается силуэт
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = ring_mat
	ring_mi.position = at + Vector3(0, 0.01, 0)
	ring_mi.scale = Vector3(1, 0.08, 1)
	_vp.add_child(ring_mi)

	var bay_lamp := StandardMaterial3D.new()
	bay_lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_box(Vector3(0.22, 0.07, 0.03), Vector3(at.x, 0.45, BACK_Z + 0.02), bay_lamp)
	_bay_lamps.append(bay_lamp)

	var spot := SpotLight3D.new()
	spot.light_color = COLOR_SPOT
	spot.spot_range = 8.0
	spot.spot_angle = 17.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = false
	spot.light_energy = 0.0
	_vp.add_child(spot)
	spot.look_at_from_position(at + Vector3(0, 5.0, 0), at, Vector3.FORWARD)
	_spots.append(spot)

	const BEAM_H := 4.6
	var cone := CylinderMesh.new()
	cone.top_radius = 0.1
	cone.bottom_radius = 0.95
	cone.height = BEAM_H
	cone.radial_segments = 20
	cone.rings = 1
	cone.cap_top = false
	cone.cap_bottom = false
	var beam := ShaderMaterial.new()
	beam.shader = _shader(BEAM_SHADER)
	beam.set_shader_parameter("tint", Color(COLOR_SPOT, 0.22))
	beam.set_shader_parameter("height", BEAM_H)
	var beam_mi := MeshInstance3D.new()
	beam_mi.mesh = cone
	beam_mi.material_override = beam
	beam_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	beam_mi.position = at + Vector3(0, BEAM_H * 0.5, 0)
	_vp.add_child(beam_mi)
	_beams.append(beam)


func _box(size: Vector3, pos: Vector3, mat: Material, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	_vp.add_child(mi)
	return mi


func _disc(radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.004
	mesh.radial_segments = 24
	mesh.rings = 0
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_vp.add_child(mi)
	return mi


## Шахта под люком — одна сетка на все люки (и материалы общие: открывается только люк выбранной).
## Восьмигранный колодец глубиной SHAFT_DEPTH, дальняя грань (−Z) — к камере. Стены — листы со швами
## и жёлтой кромкой поверху (SHAFT_SHADER); кольца-уступы с шагом SHAFT_STEP ловят свет прожектора
## сверху и зарево снизу; на гранях по бокам от дальней — направляющие с огнями между кольцами.
func _shaft_mesh() -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var down := Vector3(0, -SHAFT_DEPTH, 0)
	var w := 2.0 * SHAFT_R * tan(PI / SHAFT_SIDES)    # ширина грани
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in range(-SHAFT_SIDES / 2, SHAFT_SIDES / 2):  # развёртка UV.x без шва на видной стороне
		var a := _corner(k, -1.0, SHAFT_R)
		var b := _corner(k, 1.0, SHAFT_R)
		_quad(st, a, b, b + down, a + down, -_face(k), k * w, (k + 1) * w)
	st.commit(mesh)
	_shaft_wall = ShaderMaterial.new()
	_shaft_wall.shader = _shader(SHAFT_SHADER)
	_shaft_wall.set_shader_parameter("panel", w * 0.5)
	_shaft_wall.set_shader_parameter("step_y", SHAFT_STEP)
	_shaft_wall.set_shader_parameter("glow", COLOR_GLOW)
	mesh.surface_set_material(0, _shaft_wall)

	# Кольца и направляющие — кусками по шагу колец: цвет вершин темнеет вглубь, как стены.
	var rings := int(SHAFT_DEPTH / SHAFT_STEP)
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in range(1, rings + 1):
		var top := Vector3(0, -SHAFT_STEP * j, 0)
		var bot := top - Vector3(0, 0.04, 0)
		for k in SHAFT_SIDES:
			var oa := _corner(k, -1.0, SHAFT_R)
			var ob := _corner(k, 1.0, SHAFT_R)
			var ia := _corner(k, -1.0, SHAFT_R - RING_IN)
			var ib := _corner(k, 1.0, SHAFT_R - RING_IN)
			_quad(st, oa + top, ob + top, ib + top, ia + top, Vector3.UP)
			_quad(st, ia + top, ib + top, ib + bot, ia + bot, -_face(k))
			_quad(st, ia + bot, ib + bot, ob + bot, oa + bot, Vector3.DOWN)
	const RAIL_HW := 0.035
	for k: int in [1, SHAFT_SIDES - 1]:
		var n := _face(k)
		var t := Vector3.UP.cross(n) * RAIL_HW
		var back := n * SHAFT_R
		var front := n * (SHAFT_R - RAIL_IN)
		for j in rings + 1:
			var y0 := Vector3(0, -SHAFT_STEP * j, 0)
			var y1 := Vector3(0, -minf(SHAFT_STEP * (j + 1), SHAFT_DEPTH), 0)
			_quad(st, front - t + y0, front + t + y0, front + t + y1, front - t + y1, -n)
			_quad(st, back + t + y0, front + t + y0, front + t + y1, back + t + y1, t.normalized())
			_quad(st, front - t + y0, back - t + y0, back - t + y1, front - t + y1, -t.normalized())
	st.commit(mesh)
	var rib := StandardMaterial3D.new()
	rib.albedo_color = Color(0.26, 0.25, 0.32)
	rib.roughness = 0.5
	rib.metallic = 0.4
	rib.vertex_color_use_as_albedo = true
	mesh.surface_set_material(1, rib)

	# Огни — на направляющих, посередине между кольцами.
	st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k: int in [1, SHAFT_SIDES - 1]:
		var n := _face(k)
		var t := Vector3.UP.cross(n) * 0.026
		var up := Vector3(0, 0.035, 0)
		for j in rings:
			var c := n * (SHAFT_R - RAIL_IN - 0.004) + Vector3(0, -SHAFT_STEP * (j + 0.5), 0)
			_quad(st, c - t + up, c + t + up, c + t - up, c - t - up, -n)
	st.commit(mesh)
	_shaft_lamps = ShaderMaterial.new()
	_shaft_lamps.shader = _shader(SHAFT_LAMP_SHADER)
	_shaft_lamps.set_shader_parameter("tint", COLOR_STRIP)
	_shaft_lamps.set_shader_parameter("step_y", SHAFT_STEP)
	mesh.surface_set_material(2, _shaft_lamps)
	return mesh


## Направление на середину грани k шахты: 0 — дальняя (−Z), дальше — вправо (к +X).
static func _face(k: float) -> Vector3:
	var a := k * TAU / SHAFT_SIDES
	return Vector3(sin(a), 0, -cos(a))


## Угол грани k: side −1 — левый, +1 — правый (если смотреть на грань изнутри); r — до середины грани.
static func _corner(k: int, side: float, r: float) -> Vector3:
	return _face(k + side * 0.5) * (r / cos(PI / SHAFT_SIDES))


## Четырёхугольник a-b-c-d с нормалью n; лицевая сторона в Godot — обход по часовой, порядок треугольников
## подбирается по нормали. UV.x — от u0 (a, d) до u1 (b, c), UV.y — глубина; цвет вершины — затемнение
## вглубь (как у стен в SHAFT_SHADER).
static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		u0: float = 0.0, u1: float = 0.0) -> void:
	var pts := PackedVector3Array([a, b, c, d])
	var us := PackedFloat32Array([u0, u1, u1, u0])
	var cw := (b - a).cross(c - a).dot(n) < 0.0
	var order := PackedInt32Array([0, 1, 2, 0, 2, 3] if cw else [0, 2, 1, 0, 3, 2])
	st.set_normal(n)
	for i in order:
		var depth := -pts[i].y
		var dim := 1.0 - 0.8 * smoothstep(0.05, 1.0, depth)
		st.set_color(Color(dim, dim, dim))
		st.set_uv(Vector2(us[i], depth))
		st.add_vertex(pts[i])


static func _shader(code: String) -> Shader:
	var s := Shader.new()
	s.code = code
	return s


# --- Интерфейс ----------------------------------------------------------------------------------

func _build_ui() -> void:
	_ui = Control.new()
	_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ui.draw.connect(_draw_ui)
	add_child(_ui)
	var go := UiKit.button("ВЫСАДКА", "F")
	go.pressed.connect(_start)
	_place(go, Vector2(VIEW.x * 0.5, CAPTION_Y + 16), true)        # сразу под строкой выбора
	var help := UiKit.button("Справка", "F1")
	help.pressed.connect(_open_help)
	_place(help, Vector2(VIEW.x * 0.5, VIEW.y - 12), true)
	# Стрелки — по бокам от строки «выбор машины».
	var half := UiKit.FONT.get_string_size(CAPTION, HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TEXT).x * 0.5 + 8.0
	var prev := UiKit.button("<", "A")
	prev.pressed.connect(_step.bind(-1))
	_place(prev, Vector2(VIEW.x * 0.5 - half, CAPTION_Y - 3), false, true)
	var next := UiKit.button("", "")
	next.text = "[D]   >"
	next.pressed.connect(_step.bind(1))
	_place(next, Vector2(VIEW.x * 0.5 + half, CAPTION_Y - 3), false)
	_build_volume()


## Громкость: кнопка-динамик в правом верхнем углу; по нажатию под ней — окошко с регулятором.
func _build_volume() -> void:
	_vol_button = UiKit.button("", "")
	_vol_button.custom_minimum_size = Vector2(22, 17)
	_vol_button.draw.connect(_draw_speaker_button)
	_vol_button.pressed.connect(_toggle_volume)
	_place(_vol_button, Vector2(VIEW.x - 10, 16), false, true)
	_vol_panel = Control.new()
	_vol_panel.draw.connect(func() -> void:
		var r := Rect2(Vector2.ZERO, _vol_panel.size)
		_vol_panel.draw_rect(r, UiKit.COLOR_PANEL)
		_vol_panel.draw_rect(r, UiKit.COLOR_EDGE, false, 1.0)
		UiKit.text(_vol_panel, Vector2(8, 15), "ГРОМКОСТЬ", UiKit.TEXT, UiKit.COLOR_DIM)
		UiKit.text(_vol_panel, Vector2(8, 43), "A / D, колесо", UiKit.TEXT, UiKit.COLOR_DIM))
	add_child(_vol_panel)
	_vol_slider = VolumeSlider.new()
	_vol_panel.add_child(_vol_slider)
	_vol_slider.changed.connect(func(_v: float) -> void: _vol_button.queue_redraw())
	_vol_slider.position = Vector2(8, 20)
	_vol_panel.size = Vector2(_vol_slider.size.x + 16.0, 50)
	_vol_panel.position = Vector2(_vol_button.position.x + _vol_button.size.x - _vol_panel.size.x,
			_vol_button.position.y + _vol_button.size.y + 3.0)
	_vol_panel.visible = false


func _toggle_volume() -> void:
	_vol_panel.visible = not _vol_panel.visible
	_vol_button.queue_redraw()


func _draw_speaker_button() -> void:
	var o := (_vol_button.size - Vector2(11, 9)) * 0.5
	o = o.floor()
	var level := roundi(Settings.master_volume * VolumeSlider.STEPS)
	var c := UiKit.COLOR_MARK if _vol_panel != null and _vol_panel.visible else (UiKit.COLOR_TEXT if level > 0 else UiKit.COLOR_DIM)
	_vol_button.draw_rect(Rect2(o + Vector2(0, 3), Vector2(2, 3)), c)
	_vol_button.draw_colored_polygon(PackedVector2Array([o + Vector2(2, 3), o + Vector2(5, 0), o + Vector2(5, 9),
			o + Vector2(2, 6)]), c)
	if level == 0:
		for i in 4:
			_vol_button.draw_rect(Rect2(o + Vector2(7 + i, 2 + i), Vector2.ONE), c)
			_vol_button.draw_rect(Rect2(o + Vector2(10 - i, 2 + i), Vector2.ONE), c)
		return
	_vol_button.draw_rect(Rect2(o + Vector2(7, 3), Vector2(1, 3)), c)
	if level > VolumeSlider.STEPS / 2:
		_vol_button.draw_rect(Rect2(o + Vector2(9, 1), Vector2(1, 7)), c)


## Кнопку — в точку: по вертикали всегда центром; по горизонтали — центром (center), правым краем
## (from_right) или левым.
func _place(b: Button, at: Vector2, center: bool, from_right: bool = false) -> void:
	add_child(b)
	b.reset_size()
	var x := at.x - b.size.x * 0.5 if center else (at.x - b.size.x if from_right else at.x)
	b.position = Vector2(x, at.y - b.size.y * 0.5)


## Порядок машин в трюме: DISPLAY_ORDER, неизвестные классы — в конце.
static func display_order(ids: Array[StringName]) -> Array[StringName]:
	var out: Array[StringName] = []
	for id in DISPLAY_ORDER:
		if ids.has(id):
			out.append(id)
	for id in ids:
		if not out.has(id):
			out.append(id)
	return out


func _draw_ui() -> void:
	var w := float(VIEW.x)
	UiKit.text(_ui, Vector2(0, 26), "EXPLORER", UiKit.TITLE, UiKit.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	# Версия — мелко правее заголовка, по его нижней линии (application/config/version).
	var title_w := UiKit.FONT.get_string_size("EXPLORER", HORIZONTAL_ALIGNMENT_LEFT, -1, UiKit.TITLE).x
	UiKit.text(_ui, Vector2(roundf((w + title_w) * 0.5) + 4.0, 26), "v" + str(ProjectSettings.get_setting(
			"application/config/version", "")), UiKit.TEXT, UiKit.COLOR_DIM)
	UiKit.text(_ui, Vector2(0, CAPTION_Y), CAPTION, UiKit.TEXT, UiKit.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
	if vehicle_ids.is_empty():
		return
	var cls := Balance.vehicle(vehicle_ids[selected])
	var stats := UiKit.stats_of(cls)
	var x0 := w * 0.5 - 112.0
	var y0 := 226.0
	for i in stats.size():
		var col := i % 2
		var row := i / 2
		UiKit.stat_row(_ui, Vector2(x0 + col * 124.0, y0 + row * 13.0), i as UiKit.Stat, stats[i])


# --- Ввод и анимация ----------------------------------------------------------------------------

func _process(dt: float) -> void:
	_time += dt
	for i in _blinkers.size():
		_blinkers[i].albedo_color.a = 1.0
		_blinkers[i].albedo_color.v = 1.0 if fmod(_time * (0.7 + i * 0.23) + i * 0.37, 1.0) < 0.55 else 0.25
	if _leave_t >= 0.0:
		_leave(dt)
		return
	if not HelpScreen.shown(get_tree()):     # справка поверх — клавиши её (и Esc, закрывший её в этом кадре)
		_keys()
	_models[selected].root.rotation.y += SPIN * dt
	for m in _models:
		for rotor in m.spinners:
			rotor.rotation.z += 6.0 * dt * float(m == _models[selected])
	_apply_lights(dt)
	_ui.queue_redraw()


## Клавиши трюма: A / D — машина, F / Enter — высадка. Пока открыто окошко громкости: A / D — громкость,
## Esc — закрыть; выбор машины и высадка ждут.
func _keys() -> void:
	if _vol_panel.visible:
		if Input.is_action_just_pressed(&"move_left") or Input.is_action_just_pressed(&"ui_left"):
			_vol_slider.nudge(-1)
			_vol_button.queue_redraw()
		elif Input.is_action_just_pressed(&"move_right") or Input.is_action_just_pressed(&"ui_right"):
			_vol_slider.nudge(1)
			_vol_button.queue_redraw()
		elif Input.is_action_just_pressed(&"pause") or Input.is_action_just_pressed(&"ui_cancel"):
			_toggle_volume()
		return
	if Input.is_action_just_pressed(&"move_left") or Input.is_action_just_pressed(&"ui_left"):
		_step(-1)
	elif Input.is_action_just_pressed(&"move_right") or Input.is_action_just_pressed(&"ui_right"):
		_step(1)
	elif Input.is_action_just_pressed(&"radio") or Input.is_action_just_pressed(&"ui_accept"):
		_start()


## Тап или клик по машине — выбрать её.
func _unhandled_input(event: InputEvent) -> void:
	if _leave_t >= 0.0 or HelpScreen.shown(get_tree()) or not UiKit.is_click(event):
		return
	if _vol_panel.visible:
		_toggle_volume()                     # клик мимо окошка громкости — закрыть его
		get_viewport().set_input_as_handled()
		return
	var p: Vector2 = (event as InputEventMouseButton).position
	for i in _models.size():
		var sp := _cam.unproject_position(_models[i].root.position + Vector3(0, 0.25, 0))
		if sp.distance_to(p) < PICK_RADIUS_PX:
			get_viewport().set_input_as_handled()
			if i != selected:
				_select(i)
			return


func _step(d: int) -> void:
	if _leave_t < 0.0 and vehicle_ids.size() > 1 and not HelpScreen.shown(get_tree()):
		_select(wrapi(selected + d, 0, vehicle_ids.size()))


func _select(i: int) -> void:
	selected = i
	_click()
	vehicle_changed.emit(vehicle_ids[selected])


## Прожектор выбранной машины разгорается с парой мерцаний, у прочих гаснет.
func _apply_lights(dt: float) -> void:
	for i in _spots.size():
		var target := 1.0 if i == selected else 0.0
		_light_k[i] = move_toward(_light_k[i], target, dt / SPOT_FADE_S) if dt > 0.0 else target
		var k := _light_k[i]
		var flick := 1.0
		if i == selected and k < 1.0:
			flick = 0.4 if fmod(k * 3.0, 1.0) < 0.35 else 1.0
		_spots[i].light_energy = SPOT_ON * k * flick
		_spots[i].visible = k > 0.0
		_beams[i].set_shader_parameter("intensity", k * flick)
		_bay_lamps[i].albedo_color = COLOR_BAY_OFF.lerp(COLOR_BAY_ON, k * flick)


## Щелчок тумблера: звук берётся при нажатии — не успел в фоне, досинтезируется сейчас (~5 мс, один раз).
func _click() -> void:
	_toggle_snd.stream = Sfx.toggle()
	_toggle_snd.play()


func _start() -> void:
	if _leave_t >= 0.0 or HelpScreen.shown(get_tree()):
		return
	_leave_t = 0.0
	_click()
	_lift_snd.stream = Sfx.hatch_lift()               # не успел в фоне — досинтезируется сейчас
	_lift_snd.play()
	_shaft_glow.position = Vector3(_doors[selected].position.x, -1.5, 0)
	_shaft_glow.light_energy = 0.0
	_shaft_glow.visible = true


func _open_help() -> void:
	var help := get_tree().root.find_child("HelpScreen", true, false) as HelpScreen
	if help != null:
		help.open()


## Старт: створка люка уходит (с ней — пятно тени), огни шахты загораются сверху вниз, снизу разгорается
## зарево, машина опускается мимо колец и огней; затемнение, сигнал, проявление мира.
func _leave(dt: float) -> void:
	_leave_t += dt
	var door := _doors[selected]
	door.scale = Vector3.ONE * maxf(1.0 - _leave_t / 0.25, 0.0)
	_blobs[selected].scale = door.scale
	_shaft_lamps.set_shader_parameter("run", _leave_t)
	var heat := clampf(_leave_t / (0.2 + SINK_S), 0.0, 1.0)
	_shaft_wall.set_shader_parameter("heat", heat)
	_shaft_glow.light_energy = GLOW_ON * heat
	var m := _models[selected]
	var k := clampf((_leave_t - 0.2) / SINK_S, 0.0, 1.0)
	m.root.position.y = m.hover_height - 1.0 * k * k
	var fade_in := clampf((_leave_t - 0.2 - SINK_S + FADE_S) / FADE_S, 0.0, 1.0)
	var fade_out := clampf((_leave_t - 0.2 - SINK_S - 0.1) / FADE_S, 0.0, 1.0)
	_fade.color.a = fade_in * (1.0 - fade_out)
	if not _emitted and _leave_t >= 0.2 + SINK_S + 0.05:
		_emitted = true
		for c in get_children():
			if c != _fade and c is CanvasItem:
				(c as CanvasItem).visible = false
		started.emit()
	if waiting and _emitted:
		_leave_t = minf(_leave_t, 0.2 + SINK_S + 0.1)   # затемнение не уходит, пока мир не готов
		_fade.color.a = 1.0
		_show_loading()
		return
	if _loading != null:
		_loading.visible = false
	if fade_out >= 1.0:
		queue_free()


## Надпись «загрузка мира…» поверх затемнения (точки бегут).
func _show_loading() -> void:
	if _loading == null:
		_loading = Label.new()
		_loading.add_theme_font_size_override(&"font_size", UiKit.TEXT)
		_loading.add_theme_color_override(&"font_color", Color(0.75, 0.72, 0.8))
		_loading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_loading.position = Vector2(0, 152)
		_loading.size = Vector2(480, 16)
		add_child(_loading)
	_loading.visible = true
	_loading.text = "загрузка мира" + ".".repeat(Time.get_ticks_msec() / 400 % 4)
