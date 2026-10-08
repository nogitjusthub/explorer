class_name ShuttleCraft
extends Node3D
## Челнок на сцене (основной и аварийный) из примитивов: спуск с неба, ожидание, взлёт.
## Основной висит над площадкой и светит лучом в зону; до посадки над центром площадки мигает
## указатель — «ёлочка» из трёх стрелок вниз, огни бегут сверху вниз.
## Аварийный садится на тайл. Анимации — в _process, интерполяция физики для узла выключена.

enum Kind { MAIN, EMERGENCY }
enum Anim { NONE, DESCEND, ASCEND }

const DROP_HEIGHT := 24.0
const FLY_S := 3.0
const MAIN_HOVER := 2.2            ## основной челнок висит над площадкой
const COLOR_MAIN := Color(0.78, 0.82, 0.9)
const COLOR_EMERGENCY := Color(0.95, 0.35, 0.22)
const COLOR_ENGINE := Color(1.0, 0.6, 0.2)
const COLOR_BEAM := Color(0.4, 0.95, 1.0, 0.22)
const COLOR_RING := Color(0.45, 1.0, 0.95, 0.9)
const COLOR_ARROW := Color(0.45, 1.0, 0.95, 0.9)
const ARROW_DIM := 0.25                ## яркость (альфа) погашенной стрелки
const ARROW_STEP_S := 0.22             ## огонь переходит на следующую стрелку
const ARROW_BASE := 0.9                ## высота нижней стрелки над площадкой
const ARROW_GAP := 0.6

var kind: Kind
var hover := 0.0
var zone_r := 2.0

var _model: Node3D
var _beam: MeshInstance3D
var _ring: MeshInstance3D
var _arrows: Node3D
var _arrow_mats: Array[StandardMaterial3D] = []
var _ring_mat: StandardMaterial3D
var _beam_mat: StandardMaterial3D
var _tractor := false                  ## эвакуация: луч втягивает машину — ярче и пульсирует
var _anim := Anim.NONE
var _t := 0.0
var _dur := FLY_S
var _time := 0.0


func _init(craft_kind: Kind, zone_radius: float = 2.0) -> void:
	kind = craft_kind
	zone_r = zone_radius
	name = "MainShuttle" if kind == Kind.MAIN else "EmergencyShuttle"
	hover = MAIN_HOVER if kind == Kind.MAIN else 0.0
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()
	visible = false


## Площадка объявлена: маяк и кольцо зоны, самого челнока ещё нет.
func show_marker(ground: Vector3) -> void:
	position = ground
	visible = true
	_model.visible = false
	_beam.visible = false
	_ring.visible = true
	_arrows.visible = true


## Спуск к точке ground за seconds (касание — к концу спуска).
func descend(ground: Vector3, seconds: float = FLY_S) -> void:
	position = ground
	visible = true
	_model.visible = true
	_model.position.y = DROP_HEIGHT
	_anim = Anim.DESCEND
	_t = 0.0
	_dur = maxf(seconds, 0.1)


## Сдвиг по горизонтали во время спуска (аварийный следует за машиной).
func retarget(ground: Vector3) -> void:
	position = position.lerp(ground, 0.2)


## Сел: у основного — луч в зону.
func touch_down() -> void:
	_anim = Anim.NONE
	_model.position.y = hover
	_arrows.visible = false
	_beam.visible = kind == Kind.MAIN
	_ring.visible = kind == Kind.MAIN


## Эвакуация: луч разгорается и втягивает машину (до взлёта).
func tractor() -> void:
	_tractor = true
	_beam.visible = true


func ascend() -> void:
	_tractor = false
	_beam_mat.albedo_color.a = COLOR_BEAM.a
	_anim = Anim.ASCEND
	_t = 0.0
	_dur = FLY_S
	_beam.visible = false
	_ring.visible = false
	_arrows.visible = false


## Взлёт с площадки — пыль кольцом из-под челнока.
func takeoff_dust() -> void:
	var dust := CPUParticles3D.new()
	dust.one_shot = true
	dust.explosiveness = 0.8
	dust.amount = 70
	dust.lifetime = 1.6
	dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	dust.emission_ring_axis = Vector3.UP
	dust.emission_ring_radius = zone_r
	dust.emission_ring_inner_radius = 0.5
	dust.emission_ring_height = 0.1
	dust.direction = Vector3.UP
	dust.spread = 75.0
	dust.initial_velocity_min = 1.5
	dust.initial_velocity_max = 4.0
	dust.gravity = Vector3(0, -3.0, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.58, 0.5, 0.7)
	q.material = m
	dust.mesh = q
	dust.position = Vector3(0, 0.1, 0)
	add_child(dust)
	dust.emitting = true


func is_flying() -> bool:
	return _anim != Anim.NONE


func _process(dt: float) -> void:
	if not visible:
		return
	_time += dt
	_ring_mat.albedo_color.a = 0.55 + 0.35 * sin(_time * 4.0)
	if _tractor:
		_beam_mat.albedo_color.a = 0.45 + 0.2 * sin(_time * 30.0)
	if _arrows.visible:
		_update_arrows()
	match _anim:
		Anim.DESCEND:
			_t += dt
			var k := clampf(_t / _dur, 0.0, 1.0)
			_model.position.y = lerpf(DROP_HEIGHT, hover, 1.0 - pow(1.0 - k, 3.0))
		Anim.ASCEND:
			_t += dt
			var k := clampf(_t / _dur, 0.0, 1.0)
			_model.position.y = lerpf(hover, DROP_HEIGHT, k * k)
			if k >= 1.0:
				_anim = Anim.NONE
				visible = false
		_:
			if kind == Kind.MAIN and _model.visible:
				_model.position.y = hover + sin(_time * 1.5) * 0.06


func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	var main := kind == Kind.MAIN
	var body_color := COLOR_MAIN if main else COLOR_EMERGENCY
	var s := 1.0 if main else 0.55
	var body := _shaded(body_color)
	_mesh(_model, _box(Vector3(1.3, 0.45, 2.1) * s), Vector3(0, 0.45 * s, 0), body)
	_mesh(_model, _box(Vector3(2.4, 0.12, 0.8) * s), Vector3(0, 0.4 * s, 0.35 * s), body)
	var glass := _shaded(Color(0.35, 0.8, 1.0))
	_mesh(_model, _box(Vector3(0.7, 0.25, 0.5) * s), Vector3(0, 0.75 * s, -0.7 * s), glass)
	var engine := _unshaded(COLOR_ENGINE)
	for x in [-0.95, 0.95]:
		var pod := CylinderMesh.new()
		pod.top_radius = 0.2 * s
		pod.bottom_radius = 0.24 * s
		pod.height = 0.5 * s
		pod.radial_segments = 8
		pod.rings = 0
		_mesh(_model, pod, Vector3(x * s, 0.25 * s, 0.4 * s), _shaded(body_color.darkened(0.3)))
		var flame := CylinderMesh.new()
		flame.top_radius = 0.16 * s
		flame.bottom_radius = 0.05 * s
		flame.height = 0.25 * s
		flame.radial_segments = 6
		flame.rings = 0
		_mesh(_model, flame, Vector3(x * s, -0.1 * s, 0.4 * s), engine)

	var beam := CylinderMesh.new()
	beam.top_radius = 0.7
	beam.bottom_radius = zone_r
	beam.height = MAIN_HOVER
	beam.radial_segments = 16
	beam.rings = 0
	beam.cap_top = false
	beam.cap_bottom = false
	_beam_mat = _unshaded(COLOR_BEAM)
	_beam = _mesh(self, beam, Vector3(0, MAIN_HOVER * 0.5, 0), _beam_mat)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var ring := TorusMesh.new()
	ring.inner_radius = zone_r - 0.12
	ring.outer_radius = zone_r
	ring.rings = 24
	ring.ring_segments = 4
	_ring_mat = _unshaded(COLOR_RING)
	_ring = _mesh(self, ring, Vector3(0, 0.05, 0), _ring_mat)
	_ring.scale = Vector3(1, 0.3, 1)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_arrows = Node3D.new()
	_arrows.position = Vector3(0, ARROW_BASE, 0)
	add_child(_arrows)
	for i in 3:     # 0 — верхняя
		var mat := _unshaded(COLOR_ARROW)
		_arrow_mats.append(mat)
		_chevron(_arrows, Vector3(0, (2 - i) * ARROW_GAP, 0), mat)
	_beam.visible = false
	_ring.visible = false
	_arrows.visible = false


## Стрелка «V» остриём вниз из двух брусков (в плоскости XY узла).
static func _chevron(parent: Node3D, tip: Vector3, mat: Material) -> void:
	const ARM := 0.75
	for side in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = _box(Vector3(ARM, 0.15, 0.06))
		arm.material_override = mat
		arm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var dir := Vector3(side, 1.0, 0.0).normalized()
		arm.position = tip + dir * ARM * 0.45
		arm.rotation.z = atan2(dir.y, dir.x)
		parent.add_child(arm)


## Стрелки всегда смотрят в камеру; огонь бежит сверху вниз — к центру круга.
func _update_arrows() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam != null:
		_arrows.global_basis = cam.global_basis
	var lit := int(_time / ARROW_STEP_S) % 3
	for i in 3:
		_arrow_mats[i].albedo_color.a = 0.9 if i == lit else ARROW_DIM


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


static func _shaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	return m


static func _unshaded(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
