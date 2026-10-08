class_name HangarScreen
extends CanvasLayer
## Экран перед забегом (GDD §2): трюм челнока на орбите. Три машины стоят на люках; выбранная —
## под прожектором и медленно поворачивается, остальные — тёмные силуэты на фоне подсвеченных стен.
## Под выбранной — характеристики значками (1–5) и одна строка о характере; названий классов нет.
## Выбор: A / D, стрелки, тап по машине или кнопкам; старт — F / Enter / кнопка: люк раскрывается,
## машина уходит вниз — дальше сцена десанта. Нужен и вебу: звук включается после действия игрока.
## Трюм — отдельный мир в SubViewport: свой свет и окружение, игровой мир под экраном не трогаем.

signal started
signal vehicle_changed(id: StringName)

const VIEW := Vector2i(480, 320)
const SPACING := 1.6                    ## между машинами, вдоль горизонтали экрана
const CAM_SIZE := 3.7
const CAM_ELEVATION_DEG := 38.0
const SPIN := 0.5                        ## рад/с — выбранная машина на поворотном круге
const SPOT_ON := 9.0
const SPOT_FADE_S := 0.18
const SINK_S := 0.7                      ## старт: машина уходит в люк
const FADE_S := 0.3                      ## затемнение до и после
const COLOR_SPOT := Color(1.0, 0.93, 0.8)
const COLOR_STRIP := Color(0.35, 0.6, 1.0)
const COLOR_HAZARD := Color(0.95, 0.72, 0.15)
const PICK_RADIUS_PX := 44.0

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
const FLOOR_SHADER := """
shader_type spatial;
uniform vec3 base : source_color = vec3(0.12, 0.11, 0.15);
uniform vec3 seam : source_color = vec3(0.07, 0.06, 0.09);
varying vec3 wp;
void vertex() { wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
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

var vehicle_ids: Array[StringName] = []
var selected := 0

var _vp: SubViewport
var _cam: Camera3D
var _models: Array[VehicleModels.Model] = []
var _spots: Array[SpotLight3D] = []
var _beams: Array[ShaderMaterial] = []
var _doors: Array[Node3D] = []
var _light_k: PackedFloat32Array = []    ## яркость прожектора над каждой машиной 0..1
var _ui: Control
var _fade: ColorRect
var _clunk: AudioStreamPlayer
var _leave_t := -1.0
var _emitted := false
var _time := 0.0
var _blinkers: Array[StandardMaterial3D] = []


func _ready() -> void:
	name = "HangarScreen"
	layer = 20
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
	_clunk = AudioStreamPlayer.new()
	_clunk.stream = Sfx.hit(0.12)
	_clunk.volume_db = -12.0
	add_child(_clunk)
	_light_k.resize(vehicle_ids.size())
	for i in _light_k.size():
		_light_k[i] = 1.0 if i == selected else 0.0
	_apply_lights(0.0)


# --- Трюм ---------------------------------------------------------------------------------------

func _build_hold() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.025, 0.05)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.4, 0.62)
	env.ambient_light_energy = 0.08
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)

	# Камера — как в игре: изометрия, ортогональная проекция; трюм развёрнут углом к зрителю.
	var yaw := deg_to_rad(45.0)
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
	var right := Vector3(basis.x.x, 0, basis.x.z).normalized()
	var toward := Vector3(dir.x, 0, dir.z).normalized()

	# Контровой свет из глубины трюма: обводит силуэты, пол и стены почти не трогает.
	var rim := DirectionalLight3D.new()
	rim.light_color = Color(0.45, 0.55, 1.0)
	rim.light_energy = 0.3
	_vp.add_child(rim)
	rim.look_at_from_position(Vector3(-3, 2.5, -3), Vector3(0, 0, 0))

	_build_room()

	for i in vehicle_ids.size():
		var at := right * SPACING * (i - (vehicle_ids.size() - 1) * 0.5)
		_build_bay(at)
		var m := VehicleModels.build_plain(vehicle_ids[i])
		m.root.position = at + Vector3(0, m.hover_height, 0)
		var face := toward + right * 0.55              # три четверти: нос к зрителю и чуть вправо
		m.root.rotation.y = atan2(-face.x, -face.z)
		_vp.add_child(m.root)
		_models.append(m)


func _build_room() -> void:
	var floor_mat := ShaderMaterial.new()
	floor_mat.shader = _shader(FLOOR_SHADER)
	_box(Vector3(12, 0.2, 12), Vector3(1.5, -0.1, 1.5), floor_mat)

	var wall := StandardMaterial3D.new()
	wall.albedo_color = Color(0.2, 0.19, 0.26)
	wall.roughness = 0.8
	wall.emission_enabled = true
	wall.emission = Color(0.16, 0.17, 0.3)                 # стены светлее силуэтов
	var rib := StandardMaterial3D.new()
	rib.albedo_color = Color(0.2, 0.19, 0.25)
	rib.roughness = 0.6
	rib.metallic = 0.4
	var strip := StandardMaterial3D.new()
	strip.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip.albedo_color = COLOR_STRIP
	var hazard := StandardMaterial3D.new()
	hazard.albedo_color = COLOR_HAZARD.darkened(0.35)
	hazard.roughness = 0.7

	const W := 1.85         # стены — по x = −W и z = −W: угол трюма сразу за средней машиной
	const H := 3.2
	_box(Vector3(0.2, H, 9.0), Vector3(-W - 0.1, H * 0.5, 1.5), wall)
	_box(Vector3(9.0, H, 0.2), Vector3(1.5, H * 0.5, -W - 0.1), wall)
	# Нижний отбойник, светящаяся полоса, рёбра шпангоутов.
	_box(Vector3(0.06, 0.18, 9.0), Vector3(-W + 0.03, 0.09, 1.5), hazard)
	_box(Vector3(9.0, 0.18, 0.06), Vector3(1.5, 0.09, -W + 0.03), hazard)
	_box(Vector3(0.04, 0.05, 9.0), Vector3(-W + 0.02, 2.2, 1.5), strip)
	_box(Vector3(9.0, 0.05, 0.04), Vector3(1.5, 2.2, -W + 0.02), strip)
	for i in 6:
		var s := -W + 0.6 + i * 1.4
		_box(Vector3(0.1, H, 0.12), Vector3(-W + 0.05, H * 0.5, s), rib)
		_box(Vector3(0.12, H, 0.1), Vector3(s, H * 0.5, -W + 0.05), rib)
	# Огоньки на стенах: мигают вразнобой.
	for i in 5:
		var lamp := StandardMaterial3D.new()
		lamp.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lamp.albedo_color = Color(1.0, 0.3, 0.2) if i % 2 == 0 else Color(0.3, 1.0, 0.5)
		_blinkers.append(lamp)
		var s := -W + 1.3 + i * 1.4
		if i % 2 == 0:
			_box(Vector3(0.03, 0.06, 0.06), Vector3(-W + 0.02, 1.4, s), lamp)
		else:
			_box(Vector3(0.06, 0.06, 0.03), Vector3(s, 1.4, -W + 0.02), lamp)
	# Ящики в углу.
	var crate := StandardMaterial3D.new()
	crate.albedo_color = Color(0.3, 0.27, 0.22)
	crate.roughness = 0.9
	_box(Vector3(0.45, 0.35, 0.45), Vector3(-1.5, 0.175, -1.5), crate)
	_box(Vector3(0.35, 0.28, 0.35), Vector3(-1.5, 0.49, -1.48), crate, Vector3(0, 0.3, 0))
	_box(Vector3(0.4, 0.3, 0.4), Vector3(-0.95, 0.15, -1.55), crate, Vector3(0, -0.2, 0))


## Люк под машиной: жёлтое кольцо, створка (уходит при старте), под ней — темнота шахты; прожектор
## сверху и видимый конус его луча.
func _build_bay(at: Vector3) -> void:
	var hole := StandardMaterial3D.new()
	hole.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole.albedo_color = Color(0.01, 0.01, 0.02)
	_disc(0.58, at + Vector3(0, 0.004, 0), hole)
	var door := StandardMaterial3D.new()
	door.albedo_color = Color(0.22, 0.21, 0.27)
	door.roughness = 0.5
	door.metallic = 0.5
	_doors.append(_disc(0.58, at + Vector3(0, 0.008, 0), door))
	var ring := TorusMesh.new()
	ring.inner_radius = 0.58
	ring.outer_radius = 0.7
	ring.rings = 24
	ring.ring_segments = 4
	var ring_mat := StandardMaterial3D.new()
	ring_mat.albedo_color = COLOR_HAZARD
	ring_mat.roughness = 0.6
	ring_mat.emission_enabled = true
	ring_mat.emission = COLOR_HAZARD * 0.25          # кольцо видно и в темноте — по нему читается силуэт
	var ring_mi := MeshInstance3D.new()
	ring_mi.mesh = ring
	ring_mi.material_override = ring_mat
	ring_mi.position = at + Vector3(0, 0.01, 0)
	ring_mi.scale = Vector3(1, 0.08, 1)
	_vp.add_child(ring_mi)

	var spot := SpotLight3D.new()
	spot.light_color = COLOR_SPOT
	spot.spot_range = 8.0
	spot.spot_angle = 17.0
	spot.spot_attenuation = 0.6
	spot.shadow_enabled = true
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
	var go := UiKit.button("ВЫСАДКА", "F", 8)
	go.pressed.connect(_start)
	_place(go, Vector2(VIEW.x * 0.5, VIEW.y - 18), true)
	var help := UiKit.button("?", "F1")
	help.pressed.connect(_open_help)
	_place(help, Vector2(VIEW.x - 10, 10), false, true)
	var prev := UiKit.button("<", "A")
	prev.pressed.connect(_step.bind(-1))
	_place(prev, Vector2(10, 142), false)
	var next := UiKit.button(">", "D")
	next.pressed.connect(_step.bind(1))
	_place(next, Vector2(VIEW.x - 10, 142), false, true)


## Кнопку — в точку: по центру (center) или от левого/правого края (from_right).
func _place(b: Button, at: Vector2, center: bool, from_right: bool = false) -> void:
	add_child(b)
	b.reset_size()
	var x := at.x - b.size.x * 0.5 if center else (at.x - b.size.x if from_right else at.x)
	b.position = Vector2(x, at.y - b.size.y * 0.5 if center else at.y)


func _draw_ui() -> void:
	var w := float(VIEW.x)
	UiKit.text(_ui, Vector2(0, 26), "EXPLORER", 16, UiKit.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)
	UiKit.text(_ui, Vector2(0, 38), "трюм челнока · выбор машины", 8, UiKit.COLOR_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, w)
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
	UiKit.text(_ui, Vector2(0, y0 + 40), cls.blurb, 8, UiKit.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, w)


# --- Ввод и анимация ----------------------------------------------------------------------------

func _process(dt: float) -> void:
	_time += dt
	for i in _blinkers.size():
		_blinkers[i].albedo_color.a = 1.0
		_blinkers[i].albedo_color.v = 1.0 if fmod(_time * (0.7 + i * 0.23) + i * 0.37, 1.0) < 0.55 else 0.25
	if _leave_t >= 0.0:
		_leave(dt)
		return
	if not HelpScreen.is_open:
		if Input.is_action_just_pressed(&"move_left") or Input.is_action_just_pressed(&"ui_left"):
			_step(-1)
		elif Input.is_action_just_pressed(&"move_right") or Input.is_action_just_pressed(&"ui_right"):
			_step(1)
		elif Input.is_action_just_pressed(&"radio") or Input.is_action_just_pressed(&"ui_accept"):
			_start()
	_models[selected].root.rotation.y += SPIN * dt
	for m in _models:
		for rotor in m.spinners:
			rotor.rotation.z += 6.0 * dt * float(m == _models[selected])
	_apply_lights(dt)
	_ui.queue_redraw()


## Тап или клик по машине — выбрать её.
func _unhandled_input(event: InputEvent) -> void:
	if _leave_t >= 0.0 or HelpScreen.is_open or not UiKit.is_click(event):
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
	if _leave_t < 0.0 and vehicle_ids.size() > 1 and not HelpScreen.is_open:
		_select(wrapi(selected + d, 0, vehicle_ids.size()))


func _select(i: int) -> void:
	selected = i
	_clunk.play()
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


func _start() -> void:
	if _leave_t >= 0.0 or HelpScreen.is_open:
		return
	_leave_t = 0.0
	_clunk.play()


func _open_help() -> void:
	var help := get_tree().root.find_child("HelpScreen", true, false) as HelpScreen
	if help != null:
		help.open()


## Старт: створка люка уходит, машина опускается в шахту, затемнение, сигнал, проявление мира.
func _leave(dt: float) -> void:
	_leave_t += dt
	var door := _doors[selected]
	door.scale = Vector3.ONE * maxf(1.0 - _leave_t / 0.25, 0.0)
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
	if fade_out >= 1.0:
		queue_free()
