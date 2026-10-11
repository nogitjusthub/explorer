class_name ShuttleCraft
extends Node3D
## Челнок на сцене (основной и аварийный) из примитивов: спуск с неба, посадка на землю, взлёт.
## До касания под местом посадки горит предупреждающий знак — круг с косыми полосами размером с корпус:
## кто там окажется в момент касания, будет раздавлен. После посадки вокруг основного — зона погрузки
## пунктиром; при эвакуации луч из люка втягивает машину. Корпус стоящего челнока — препятствие
## (ShuttleController передаёт его кинематике). Анимации — в _process, интерполяция физики выключена.

enum Kind { MAIN, EMERGENCY }
enum Anim { NONE, DESCEND, ASCEND }

const DROP_HEIGHT := 24.0
const FLY_S := 3.0
const MAIN_HULL_R := 1.2           ## тайлов — радиус корпуса основного: зона урона при посадке и препятствие
const EMERGENCY_HULL_R := 0.75
const HATCH_Y := 0.55              ## высота люка над землёй — откуда бьёт луч эвакуации
const COLOR_MAIN := Color(0.78, 0.82, 0.9)
const COLOR_EMERGENCY := Color(0.95, 0.35, 0.22)
const COLOR_ENGINE := Color(1.0, 0.6, 0.2)
const COLOR_BEAM := Color(0.4, 0.95, 1.0, 0.45)
const COLOR_RING := Color(0.45, 1.0, 0.95, 0.9)
const COLOR_HAZARD := Color(1.0, 0.25, 0.12, 0.85)
const ZONE_DASHES := 18
const ZONE_SPIN := 0.25            ## рад/с — пунктир зоны погрузки медленно бежит по кругу
const HAZARD_SHADER := preload("res://src/render/shaders/landing_hazard.gdshader")


var kind: Kind
var zone_r := 2.0
var hull_r := MAIN_HULL_R

var _model: Node3D
var _flames: Array[Node3D] = []
var _beam: MeshInstance3D
var _beam_mat: StandardMaterial3D
var _zone: Node3D
var _zone_mat: StandardMaterial3D
var _hazard: MeshInstance3D
var _hazard_mat: ShaderMaterial
var _tractor_target: Node3D = null     ## эвакуация: луч тянется к машине
var _anim := Anim.NONE
var _t := 0.0
var _dur := FLY_S
var _time := 0.0


func _init(craft_kind: Kind, zone_radius: float = 2.0) -> void:
	kind = craft_kind
	zone_r = zone_radius
	hull_r = MAIN_HULL_R if kind == Kind.MAIN else EMERGENCY_HULL_R
	name = "MainShuttle" if kind == Kind.MAIN else "EmergencyShuttle"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_build()
	visible = false


## Площадка объявлена: на месте посадки — предупреждающий знак, самого челнока ещё нет.
func show_marker(ground: Vector3) -> void:
	position = ground
	visible = true
	_model.visible = false
	_hazard.visible = true
	_zone.visible = false


## Спуск к точке ground за seconds: касание земли — к концу спуска. Знак горит до касания.
func descend(ground: Vector3, seconds: float = FLY_S) -> void:
	position = ground
	visible = true
	_model.visible = true
	_model.position.y = DROP_HEIGHT
	_hazard.visible = true
	_set_flames(true)
	_anim = Anim.DESCEND
	_t = 0.0
	_dur = maxf(seconds, 0.1)


## Сел на землю: двигатели стихают, пыль; знак гаснет, у основного — зона погрузки пунктиром.
func touch_down() -> void:
	_anim = Anim.NONE
	_model.position.y = 0.0
	_hazard.visible = false
	_zone.visible = kind == Kind.MAIN
	_set_flames(false)
	dust(hull_r + 0.3)


## Эвакуация: из люка бьёт луч и втягивает машину (target — её узел), до взлёта.
func tractor(target: Node3D) -> void:
	_tractor_target = target
	_beam.visible = true
	_update_beam()


func ascend() -> void:
	_tractor_target = null
	_anim = Anim.ASCEND
	_t = 0.0
	_dur = FLY_S
	_beam.visible = false
	_zone.visible = false
	_hazard.visible = false
	_set_flames(true)
	dust(hull_r + 0.6)


## Пыль кольцом из-под челнока (касание, взлёт).
func dust(radius: float) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.8
	p.amount = 70 if kind == Kind.MAIN else 36
	p.lifetime = 1.6
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.4
	p.emission_ring_height = 0.1
	p.direction = Vector3.UP
	p.spread = 75.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
	p.gravity = Vector3(0, -3.0, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.22, 0.22)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.58, 0.5, 0.7)
	q.material = m
	p.mesh = q
	p.position = Vector3(0, 0.1, 0)
	add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)


func is_flying() -> bool:
	return _anim != Anim.NONE


func _process(dt: float) -> void:
	if not visible:
		return
	_time += dt
	if _hazard.visible:
		# Знак мерцает тем чаще, чем ближе касание; полосы текут.
		var k := clampf(_t / _dur, 0.0, 1.0) if _anim == Anim.DESCEND else 0.0
		var rate := lerpf(3.0, 14.0, k * k)
		_hazard_mat.set_shader_parameter(&"pulse", 0.7 + 0.3 * sin(_time * rate))
		_hazard_mat.set_shader_parameter(&"flow", _time * 0.8)
	if _zone.visible:
		_zone.rotation.y += ZONE_SPIN * dt
		_zone_mat.albedo_color.a = 0.65 + 0.3 * sin(_time * 4.0)
	if _beam.visible:
		_beam_mat.albedo_color.a = COLOR_BEAM.a + 0.2 * sin(_time * 30.0)
		_update_beam()
	match _anim:
		Anim.DESCEND:
			_t += dt
			var k := clampf(_t / _dur, 0.0, 1.0)
			_model.position.y = lerpf(DROP_HEIGHT, 0.0, 1.0 - pow(1.0 - k, 3.0))
		Anim.ASCEND:
			_t += dt
			var k := clampf(_t / _dur, 0.0, 1.0)
			_model.position.y = lerpf(0.0, DROP_HEIGHT, k * k)
			if k >= 1.0:
				_anim = Anim.NONE
				visible = false


## Луч от люка к машине: усечённый конус, растянутый по длине.
func _update_beam() -> void:
	if _tractor_target == null or not is_instance_valid(_tractor_target):
		_beam.visible = false
		return
	var a := global_position + Vector3(0, HATCH_Y, 0)
	var b := _tractor_target.global_position + Vector3(0, 0.25, 0)
	var d := b - a
	if d.length() < 0.05:
		return
	var basis := Basis(Quaternion(Vector3.UP, d.normalized())) * Basis.from_scale(Vector3(1.0, d.length(), 1.0))
	_beam.global_transform = Transform3D(basis, (a + b) * 0.5)


func _set_flames(on: bool) -> void:
	for f in _flames:
		f.visible = on


func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	var main := kind == Kind.MAIN
	var body_color := COLOR_MAIN if main else COLOR_EMERGENCY
	var s := 1.0 if main else 0.55
	var body := _shaded(body_color)
	var dark := _shaded(body_color.darkened(0.3))
	# Стоит на гондолах двигателей и передней опоре.
	_mesh(_model, _box(Vector3(1.3, 0.45, 2.1) * s), Vector3(0, 0.45 * s, 0), body)
	_mesh(_model, _box(Vector3(2.4, 0.12, 0.8) * s), Vector3(0, 0.4 * s, 0.35 * s), body)
	var glass := _shaded(Color(0.35, 0.8, 1.0))
	_mesh(_model, _box(Vector3(0.7, 0.25, 0.5) * s), Vector3(0, 0.75 * s, -0.7 * s), glass)
	_mesh(_model, _box(Vector3(0.08, 0.25, 0.08) * s), Vector3(0, 0.12 * s, -0.75 * s), dark)
	_mesh(_model, _box(Vector3(0.3, 0.04, 0.2) * s), Vector3(0, 0.02 * s, -0.78 * s), dark)
	var engine := _unshaded(COLOR_ENGINE)
	for x: float in [-0.95, 0.95]:
		var pod := CylinderMesh.new()
		pod.top_radius = 0.2 * s
		pod.bottom_radius = 0.24 * s
		pod.height = 0.5 * s
		pod.radial_segments = 8
		pod.rings = 0
		_mesh(_model, pod, Vector3(x * s, 0.25 * s, 0.4 * s), dark)
		var flame := CylinderMesh.new()
		flame.top_radius = 0.16 * s
		flame.bottom_radius = 0.05 * s
		flame.height = 0.25 * s
		flame.radial_segments = 6
		flame.rings = 0
		_flames.append(_mesh(_model, flame, Vector3(x * s, -0.1 * s, 0.4 * s), engine))

	var beam := CylinderMesh.new()
	beam.top_radius = 0.45
	beam.bottom_radius = 0.12
	beam.height = 1.0
	beam.radial_segments = 10
	beam.rings = 0
	beam.cap_top = false
	beam.cap_bottom = false
	_beam_mat = _unshaded(COLOR_BEAM)
	_beam = _mesh(self, beam, Vector3.ZERO, _beam_mat)
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false

	# Зона погрузки — пунктирное кольцо на земле.
	_zone = Node3D.new()
	_zone.position = Vector3(0, 0.05, 0)
	add_child(_zone)
	_zone_mat = _unshaded(COLOR_RING)
	var arc := TAU * zone_r / ZONE_DASHES
	for i in ZONE_DASHES:
		var a := TAU * i / ZONE_DASHES
		var dash := _mesh(_zone, _box(Vector3(0.1, 0.03, arc * 0.55)), Vector3(cos(a), 0, sin(a)) * zone_r, _zone_mat)
		dash.rotation.y = -a
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.visible = false

	# Знак посадки: круг размером с корпус, косые полосы, мерцает.
	_hazard_mat = ShaderMaterial.new()
	_hazard_mat.shader = HAZARD_SHADER
	_hazard_mat.set_shader_parameter(&"color", COLOR_HAZARD)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * hull_r * 2.0
	_hazard = _mesh(self, plane, Vector3(0, 0.04, 0), _hazard_mat)
	_hazard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hazard.visible = false


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
