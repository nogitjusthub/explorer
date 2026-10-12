class_name ShuttleCraft
extends Node3D
## Челнок на сцене (основной и аварийный) из примитивов: спуск с неба, посадка на землю, взлёт.
## Основной (десантный) — между американским шаттлом 70–80-х, челноками Star Trek и первым вариантом
## игры: угловатый корпус с фасками (шире внизу, выше прежнего), чёрный нос, лобовое стекло на скосе,
## низкие треугольные крылья с тёмным низом, киль, швы створок грузового отсека на крыше, три сопла в
## корме; стоит, как прежде, на двух гондолах тормозных двигателей под крыльями и передней стойке.
## Аварийный — маленький оранжевый «кирпич» на гондолах (первый вариант).
## Звуки — сигналом EventBus.shuttle_sound (спуск и взлёт — тот же реактивный рёв, что у капсулы
## десанта; касание; луч захвата при эвакуации), играет AudioDirector.
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
const COLOR_GLASS := Color(0.2, 0.35, 0.5)
const COLOR_NOSE := Color(0.16, 0.16, 0.19)      ## чёрный нос и низ крыльев, как у шаттла
## Сечения корпуса основного вдоль Z (нос — −Z): [z, полуширина низа, полуширина верха, низ, высота].
## Сечение — трапеция с фасками. NOSE — чёрный носовой обтекатель, HULL — остальной корпус.
const NOSE_SECTIONS := [[-1.05, 0.26, 0.2, 0.42, 0.2], [-0.85, 0.44, 0.36, 0.34, 0.38]]
const HULL_SECTIONS := [[-0.85, 0.44, 0.36, 0.34, 0.38], [-0.55, 0.54, 0.44, 0.32, 0.54],
		[0.75, 0.54, 0.44, 0.32, 0.54], [0.95, 0.5, 0.4, 0.34, 0.5]]
const HULL_CHAMFER := 0.06


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
var quiet := false                       ## без звуков (образец прогрева шейдеров)
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
	_sound(&"descend", _dur)


## Сел на землю: двигатели стихают, пыль; знак гаснет, у основного — зона погрузки пунктиром.
func touch_down() -> void:
	_anim = Anim.NONE
	_model.position.y = 0.0
	_hazard.visible = false
	_zone.visible = kind == Kind.MAIN
	_set_flames(false)
	dust(hull_r + 0.3)
	_sound(&"land", 0.0)


## Эвакуация: из люка бьёт луч и втягивает машину (target — её узел), до взлёта.
func tractor(target: Node3D, seconds: float = 1.0) -> void:
	_tractor_target = target
	_beam.visible = true
	_update_beam()
	_sound(&"tractor", seconds)


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
	_sound(&"ascend", 0.0)


func _sound(event: StringName, seconds: float) -> void:
	if not quiet:
		EventBus.shuttle_sound.emit(event, position, kind == Kind.EMERGENCY, seconds)


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
	if kind == Kind.MAIN:
		_build_main()
	else:
		_build_emergency()
	_build_common()


## Основной: корпус-лофт с фасками и чёрным носом, лобовое стекло, треугольные крылья, киль, швы
## створок отсека, три сопла в корме; тормозные гондолы под крыльями и передняя стойка — опоры.
func _build_main() -> void:
	var body := _shaded(COLOR_MAIN)
	var dark := _shaded(COLOR_MAIN.darkened(0.35))
	var nose_mat := _shaded(COLOR_NOSE)
	var glass := _shaded(COLOR_GLASS)
	var engine := _unshaded(COLOR_ENGINE)
	for part in [[NOSE_SECTIONS, nose_mat], [HULL_SECTIONS, body]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _loft(part[0], HULL_CHAMFER)
		mi.material_override = part[1]
		_model.add_child(mi)
	# Лобовое стекло — по скосу от носа (z −0.85, верх 0.72) к крыше (z −0.55, верх 0.86).
	var shield := _mesh(_model, _box(Vector3(0.6, 0.02, 0.3)), Vector3(0, 0.8, -0.7), glass)
	shield.rotation.x = atan2(0.86 - 0.72, 0.85 - 0.55)
	# Швы створок грузового отсека на крыше.
	for sx: float in [-1.0, 1.0]:
		_mesh(_model, _box(Vector3(0.02, 0.012, 1.15)), Vector3(sx * 0.15, 0.865, 0.15), dark)
	# Низкие треугольные крылья: сверху — цвет корпуса, снизу — чёрные.
	for sx: float in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(0.48 * sx, -0.4), Vector2(1.2 * sx, 0.5), Vector2(1.2 * sx, 0.85),
				Vector2(0.48 * sx, 0.9)])
		MeshKit.prism(_model, wing, 0.37, 0.05, body)
		MeshKit.prism(_model, wing, 0.33, 0.04, nose_mat)
	# Киль: контур (вверх, z) выдавлен по X — узел повёрнут на 90° вокруг Z.
	var fin := MeshKit.prism(_model, PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.0, 0.95),
			Vector2(0.56, 1.0), Vector2(0.5, 0.62)]), -0.035, 0.07, _shaded(COLOR_MAIN.darkened(0.15)))
	fin.position = Vector3(0, 0.84, 0)
	fin.rotation.z = PI * 0.5
	# Три сопла в корме, свечение — в полёте.
	for at: Vector3 in [Vector3(0, 0.7, 0.98), Vector3(-0.18, 0.52, 0.98), Vector3(0.18, 0.52, 0.98)]:
		var bell := CylinderMesh.new()
		bell.top_radius = 0.06
		bell.bottom_radius = 0.1
		bell.height = 0.12
		bell.radial_segments = 8
		bell.rings = 0
		_mesh(_model, bell, at, dark).rotation.x = PI * 0.5
		var glow := CylinderMesh.new()
		glow.top_radius = 0.07
		glow.bottom_radius = 0.07
		glow.height = 0.01
		glow.radial_segments = 8
		glow.rings = 0
		var g := _mesh(_model, glow, at + Vector3(0, 0, 0.065), engine)
		g.rotation.x = PI * 0.5
		_flames.append(g)
	# Тормозные гондолы под крыльями (на них и стоит) и пламя под ними.
	for sx: float in [-1.0, 1.0]:
		var pod := CylinderMesh.new()
		pod.top_radius = 0.15
		pod.bottom_radius = 0.18
		pod.height = 0.32
		pod.radial_segments = 8
		pod.rings = 0
		_mesh(_model, pod, Vector3(sx * 0.78, 0.17, 0.45), dark)
		var flame := CylinderMesh.new()
		flame.top_radius = 0.13
		flame.bottom_radius = 0.04
		flame.height = 0.28
		flame.radial_segments = 6
		flame.rings = 0
		_flames.append(_mesh(_model, flame, Vector3(sx * 0.78, -0.13, 0.45), engine))
	# Передняя стойка.
	_mesh(_model, _box(Vector3(0.06, 0.36, 0.06)), Vector3(0, 0.18, -0.68), dark)
	_mesh(_model, _box(Vector3(0.2, 0.03, 0.14)), Vector3(0, 0.015, -0.7), dark)


## Лофт по сечениям вдоль Z: каждое — [z, полуширина низа, полуширина верха, низ, высота], трапеция с
## фасками chamfer; торцы закрыты. Грани плоские.
static func _loft(sections: Array, chamfer: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array[PackedVector3Array] = []
	for s: Array in sections:
		var z: float = s[0]
		var wb: float = s[1]
		var wt: float = s[2]
		var y0: float = s[3]
		var y1: float = s[3] + s[4]
		var c := minf(chamfer, s[4] * 0.3)
		rings.append(PackedVector3Array([Vector3(-wb + c, y0, z), Vector3(wb - c, y0, z), Vector3(wb, y0 + c, z),
				Vector3(wt, y1 - c, z), Vector3(wt - c, y1, z), Vector3(-wt + c, y1, z), Vector3(-wt, y1 - c, z),
				Vector3(-wb, y0 + c, z)]))
	for j in rings.size() - 1:
		var r0 := rings[j]
		var r1 := rings[j + 1]
		var inside := Vector3(0, (r0[0].y + r0[4].y) * 0.5, (r0[0].z + r1[0].z) * 0.5)
		for i in r0.size():
			var n := (i + 1) % r0.size()
			MeshKit.tri_out(st, r0[i], r0[n], r1[i], inside)
			MeshKit.tri_out(st, r0[n], r1[n], r1[i], inside)
	for r in [rings[0], rings[rings.size() - 1]]:
		var center := Vector3.ZERO
		for v in r:
			center += v
		center /= r.size()
		var out := Vector3(0, 0, -1.0 if r == rings[0] else 1.0)
		for i in r.size():
			MeshKit.tri(st, center, r[i], r[(i + 1) % r.size()], out)
	return st.commit()


## Аварийный: маленький «кирпич» на гондолах двигателей и передней опоре.
func _build_emergency() -> void:
	var body_color := COLOR_EMERGENCY
	var s := 0.55
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


## Общее: луч эвакуации, зона погрузки, знак посадки.
func _build_common() -> void:
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
