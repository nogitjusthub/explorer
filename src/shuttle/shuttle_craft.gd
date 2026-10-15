class_name ShuttleCraft
extends Node3D
## Челнок на сцене (основной и аварийный) из примитивов. Садится, как челноки Star Trek: заход
## по-самолётному — носом вперёд по наклонной сзади, на маршевых двигателях (факелы из кормовых сопел); над
## площадкой зависает и опускается вертикально на факелах вниз (сопел в днище не видно — только
## пламя), выпуская посадочные стойки. Взлёт — вертикально, стойки убираются, затем разгон вперёд.
## Основной (десантный) — между американским шаттлом 70–80-х, челноками Star Trek и первым вариантом
## игры: угловатый корпус с фасками (шире внизу, выше прежнего), чёрный нос, лобовое стекло на скосе,
## низкие треугольные крылья с тёмным низом, киль, швы створок грузового отсека на крыше, три тёмных
## сопла в корме; на земле стоит на двух стойках под крыльями и передней.
## Аварийный — в том же стиле, короче и коренастее, оранжевый.
## Обшивка (M5, BodyMaterial.faces) — по граням, как у машин: кромка в пиксель, у основного — дверь
## экипажа и грузовой люк по бортам, рули на задних кромках крыльев; у аварийного — двери, люк и решётка
## на крыше, рули на крыльях.
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
const APPROACH_DIST := 30.0        ## заход — с этой дальности сзади по курсу…
const APPROACH_SHARE := 0.55       ## …за эту долю спуска; дальше — вертикально с высоты зависания
const HOVER_H := 2.5               ## высота зависания над площадкой
const CLIMB_SHARE := 0.4           ## взлёт: доля вертикального подъёма до HOVER_H, дальше — разгон вперёд
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
const COLOR_NOZZLE := Color(0.13, 0.13, 0.16)    ## сопла маршевых двигателей
const COLOR_GEAR := Color(0.32, 0.32, 0.36)      ## посадочные стойки
## Сечения корпуса основного вдоль Z (нос — −Z): [z, полуширина низа, полуширина верха, низ, высота].
## Сечение — трапеция с фасками. NOSE — чёрный носовой обтекатель, HULL — остальной корпус.
const NOSE_SECTIONS := [[-1.05, 0.26, 0.2, 0.42, 0.2], [-0.85, 0.44, 0.36, 0.34, 0.38]]
const HULL_SECTIONS := [[-0.85, 0.44, 0.36, 0.34, 0.38], [-0.55, 0.54, 0.44, 0.32, 0.54],
		[0.75, 0.54, 0.44, 0.32, 0.54], [0.95, 0.5, 0.4, 0.34, 0.5]]
const HULL_CHAMFER := 0.06
## Аварийный — те же сечения, короче и коренастее.
const EM_NOSE_SECTIONS := [[-0.66, 0.16, 0.12, 0.2, 0.12], [-0.48, 0.3, 0.24, 0.14, 0.26]]
const EM_HULL_SECTIONS := [[-0.48, 0.3, 0.24, 0.14, 0.26], [-0.3, 0.36, 0.28, 0.13, 0.36],
		[0.42, 0.36, 0.28, 0.13, 0.36], [0.56, 0.32, 0.25, 0.15, 0.32]]
const EM_CHAMFER := 0.04
const PX := Grid.ART_PX            ## пиксель обшивки — как у рельефа и машин


var kind: Kind
var query: TerrainQuery                  ## рельеф под челноком — цвет пыли (без него — цвет грунта по умолчанию)
var zone_r := 2.0
var hull_r := MAIN_HULL_R

var _model: Node3D
var _thrust: Array[Node3D] = []         ## факелы маршевых двигателей (полёт вперёд)
var _lift: Array[Node3D] = []           ## факелы вниз (зависание, вертикальные спуск и подъём)
var _legs: Array[Node3D] = []           ## шарниры посадочных стоек (у основания)
var _gear := 1.0                        ## выпуск стоек: 0 — убраны, 1 — выпущены
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
	_model.position = Vector3(0.0, DROP_HEIGHT, APPROACH_DIST)
	_hazard.visible = true
	_set_gear(0.0)
	_set_flames(true, false)
	_anim = Anim.DESCEND
	_t = 0.0
	_dur = maxf(seconds, 0.1)
	_sound(&"descend", _dur)


## Сел на землю: двигатели стихают, пыль; знак гаснет, у основного — зона погрузки пунктиром.
func touch_down() -> void:
	_anim = Anim.NONE
	_model.position = Vector3.ZERO
	_model.rotation = Vector3.ZERO
	_hazard.visible = false
	_zone.visible = kind == Kind.MAIN
	_set_gear(1.0)
	_set_flames(false, false)
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
	_set_flames(false, true)
	dust(hull_r + 0.6)
	_sound(&"ascend", 0.0)


func _sound(event: StringName, seconds: float) -> void:
	if not quiet:
		EventBus.shuttle_sound.emit(event, position, kind == Kind.EMERGENCY, seconds)


## Пыль кольцом из-под челнока (касание, взлёт).
func dust(radius: float) -> void:
	var p := PixelFx.dust(70 if kind == Kind.MAIN else 36, 1.6)     # как у всех (PixelFx), цвет грунта
	p.one_shot = true
	p.explosiveness = 0.8
	p.color = PixelFx.dust_color(query, global_position.x, global_position.z)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	p.emission_ring_axis = Vector3.UP
	p.emission_ring_radius = radius
	p.emission_ring_inner_radius = radius * 0.4
	p.emission_ring_height = 0.1
	p.spread = 75.0
	p.initial_velocity_min = 1.5
	p.initial_velocity_max = 4.0
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
		# Пунктир бежит шагом в пиксель мира по окружности, мерцает ступенями.
		_zone.rotation.y = snappedf(_time * ZONE_SPIN, PX / zone_r)
		_zone_mat.albedo_color.a = 0.65 + 0.3 * snappedf(sin(_time * 4.0), 0.5)
	if _beam.visible:
		_beam_mat.albedo_color.a = COLOR_BEAM.a + 0.2 * signf(sin(_time * 30.0))
		_update_beam()
	match _anim:
		Anim.DESCEND:
			_t += dt
			_descend_pose(clampf(_t / _dur, 0.0, 1.0))
		Anim.ASCEND:
			_t += dt
			var k := clampf(_t / _dur, 0.0, 1.0)
			_ascend_pose(k)
			if k >= 1.0:
				_anim = Anim.NONE
				visible = false


## Спуск, k — доля 0…1. Заход: по наклонной сзади, тормозя к зависанию; нос чуть опущен, к концу —
## задран (гасит скорость), факелы вниз включаются на торможении. Затем вертикально: стойки выходят,
## касание — с нулевой скоростью.
func _descend_pose(k: float) -> void:
	if k < APPROACH_SHARE:
		var a := k / APPROACH_SHARE
		var e := 1.0 - (1.0 - a) * (1.0 - a)
		_model.position = Vector3(0.0, lerpf(DROP_HEIGHT, HOVER_H, e), lerpf(APPROACH_DIST, 0.0, e))
		_model.rotation.x = lerpf(-0.15, 0.12, smoothstep(0.5, 1.0, a))
		_set_flames(true, a > 0.7)
		_set_gear(0.0)
		return
	var b := (k - APPROACH_SHARE) / (1.0 - APPROACH_SHARE)
	_model.position = Vector3(0.0, HOVER_H * (1.0 - smoothstep(0.0, 1.0, b)), 0.0)
	_model.rotation.x = lerpf(0.12, 0.0, smoothstep(0.0, 0.4, b))
	_set_flames(false, true)
	_set_gear(smoothstep(0.0, 0.6, b))


## Взлёт, k — доля 0…1: вертикально до высоты зависания (стойки убираются), затем разгон вперёд с набором
## высоты на маршевых, нос чуть вверх.
func _ascend_pose(k: float) -> void:
	if k < CLIMB_SHARE:
		var b := k / CLIMB_SHARE
		_model.position = Vector3(0.0, HOVER_H * smoothstep(0.0, 1.0, b), 0.0)
		_model.rotation.x = 0.0
		_set_flames(false, true)
		_set_gear(1.0 - smoothstep(0.3, 1.0, b))
		return
	var a := (k - CLIMB_SHARE) / (1.0 - CLIMB_SHARE)
	var e := a * a
	_model.position = Vector3(0.0, lerpf(HOVER_H, DROP_HEIGHT, e), lerpf(0.0, -APPROACH_DIST, e))
	_model.rotation.x = lerpf(0.0, 0.2, smoothstep(0.0, 0.3, a))
	_set_flames(true, a < 0.15)
	_set_gear(0.0)


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


func _set_flames(thrust: bool, lift: bool) -> void:
	for f in _thrust:
		f.visible = thrust
	for f in _lift:
		f.visible = lift


## Стойки: убраны — сложены назад под крыло и спрятаны, выпущены — вниз с небольшим развалом.
func _set_gear(g: float) -> void:
	_gear = g
	for leg in _legs:
		leg.rotation.x = -(1.0 - g) * PI * 0.5
		leg.visible = g > 0.02


func _build() -> void:
	_model = Node3D.new()
	add_child(_model)
	if kind == Kind.MAIN:
		_build_main()
	else:
		_build_emergency()
	BodyMaterial.map_faces(_model)
	_build_common()


## Основной: корпус-лофт с фасками и чёрным носом, лобовое стекло, треугольные крылья, киль, швы
## створок отсека, три тёмных сопла маршевых двигателей в корме; посадочные стойки под крыльями и
## передняя (выпускаются на вертикальном спуске), факелы вниз из днища.
func _build_main() -> void:
	var body := BodyMaterial.faces(COLOR_MAIN, PX)
	var dark := _shaded(COLOR_MAIN.darkened(0.35))
	var nose_mat := _shaded(COLOR_NOSE)
	var glass := _shaded(COLOR_GLASS)
	var engine := _unshaded(COLOR_ENGINE)
	var hull: MeshInstance3D
	for part in [[NOSE_SECTIONS, nose_mat], [HULL_SECTIONS, body]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _loft(part[0], HULL_CHAMFER)
		mi.material_override = part[1]
		_model.add_child(mi)
		hull = mi
	# По бортам (грань от низа 0,38 при полуширине 0,54 к верху 0,8 при 0,44): дверь экипажа за кабиной и
	# грузовой люк с петлями сверху.
	var side_x := func(y: float) -> float: return 0.54 - (y - 0.38) * 0.1 / 0.42
	var details: Array[Dictionary] = []
	for sx: float in [-1.0, 1.0]:
		details.append(BodyMaterial.detail(BodyMaterial.Detail.DOOR, Vector3(sx, 0.24, 0),
				Vector3(sx * side_x.call(0.44), 0.44, -0.45), Vector3(sx * side_x.call(0.74), 0.74, -0.22), Vector3.BACK))
		details.append(BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3(sx, 0.24, 0),
				Vector3(sx * side_x.call(0.48), 0.48, 0.12), Vector3(sx * side_x.call(0.72), 0.72, 0.6), Vector3.UP))
	hull.set_meta(&"details", details)
	# Лобовое стекло — по скосу от носа (z −0.85, верх 0.72) к крыше (z −0.55, верх 0.86).
	var shield := _mesh(_model, _box(Vector3(0.6, 0.02, 0.3)), Vector3(0, 0.8, -0.7), glass)
	shield.rotation.x = -atan2(0.86 - 0.72, 0.85 - 0.55)      # скат поднимается к корме
	# Швы створок грузового отсека на крыше.
	for sx: float in [-1.0, 1.0]:
		_mesh(_model, _box(Vector3(0.02, 0.012, 1.15)), Vector3(sx * 0.15, 0.865, 0.15), dark)
	# Низкие треугольные крылья: сверху — цвет корпуса, снизу — чёрные.
	for sx: float in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(0.48 * sx, -0.4), Vector2(1.2 * sx, 0.5), Vector2(1.2 * sx, 0.85),
				Vector2(0.48 * sx, 0.9)])
		var top := MeshKit.prism(_model, wing, 0.37, 0.05, body)
		top.set_meta(&"details", [BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3.UP,   # руль у задней кромки
				Vector3(0.62 * sx, 0.42, 0.68), Vector3(1.08 * sx, 0.42, 0.84), Vector3.FORWARD)])
		MeshKit.prism(_model, wing, 0.33, 0.04, nose_mat)
	# Киль: контур (вверх, z) выдавлен по X — узел повёрнут на 90° вокруг Z.
	var fin := MeshKit.prism(_model, PackedVector2Array([Vector2(0.0, 0.3), Vector2(0.0, 0.95),
			Vector2(0.56, 1.0), Vector2(0.5, 0.62)]), -0.035, 0.07, _shaded(COLOR_MAIN.darkened(0.15)))
	fin.position = Vector3(0, 0.84, 0)
	fin.rotation.z = PI * 0.5
	# Три сопла маршевых двигателей в корме; посадочные стойки под крыльями и передняя; факелы вниз из днища.
	var nozzle := _shaded(COLOR_NOZZLE)
	for at: Vector3 in [Vector3(0, 0.7, 0.98), Vector3(-0.18, 0.52, 0.98), Vector3(0.18, 0.52, 0.98)]:
		_nozzle(at, 0.06, 0.1, 0.12, nozzle, engine)
	# Основные стойки — у законцовок крыльев ближе к задней кромке, с развалом: камера сверху видит их лапы
	# из-за крыльев.
	var gear := _shaded(COLOR_GEAR)
	for sx: float in [-1.0, 1.0]:
		_leg(Vector3(sx * 0.98, 0.33, 0.72), 0.33 / cos(0.3), sx * 0.3, 0.035, 0.12, gear)
		for z: float in [-0.3, 0.5]:
			_lift_flame(Vector3(sx * 0.24, 0.32, z), 0.12, 1.1, engine)
	_leg(Vector3(0, 0.33, -0.68), 0.318, 0.0, 0.035, 0.09, gear)
	_lift_glow(3.5)

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


## Аварийный — в стиле основного, короче и коренастее: оранжевый корпус-лофт с фасками и чёрным носом,
## лобовое стекло на скосе, короткие треугольные крылья с тёмным низом и рулями, маленький киль, два сопла
## в корме; посадочные стойки под крыльями и передняя, факелы вниз. На обшивке — двери перед крыльями,
## на крыше люк (петли спереди) и решётка за ним.
func _build_emergency() -> void:
	var body := BodyMaterial.faces(COLOR_EMERGENCY, PX)
	var nose_mat := _shaded(COLOR_NOSE)
	var engine := _unshaded(COLOR_ENGINE)
	var hull: MeshInstance3D
	for part in [[EM_NOSE_SECTIONS, nose_mat], [EM_HULL_SECTIONS, body]]:
		var mi := MeshInstance3D.new()
		mi.mesh = _loft(part[0], EM_CHAMFER)
		mi.material_override = part[1]
		_model.add_child(mi)
		hull = mi
	# Борт — грань от низа 0,17 при полуширине 0,36 к верху 0,45 при 0,28.
	var side_x := func(y: float) -> float: return 0.36 - (y - 0.17) * 0.08 / 0.28
	var details: Array[Dictionary] = []
	for sx: float in [-1.0, 1.0]:
		details.append(BodyMaterial.detail(BodyMaterial.Detail.DOOR, Vector3(sx, 0.27, 0),
				Vector3(sx * side_x.call(0.2), 0.2, -0.29), Vector3(sx * side_x.call(0.43), 0.43, -0.12), Vector3.BACK))
	details.append(BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3.UP,
			Vector3(-0.13, 0.49, -0.2), Vector3(0.13, 0.49, 0.14), Vector3.FORWARD))
	details.append(BodyMaterial.detail(BodyMaterial.Detail.VENT, Vector3.UP,
			Vector3(-0.12, 0.49, 0.22), Vector3(0.12, 0.49, 0.36)))
	hull.set_meta(&"details", details)
	# Лобовое стекло — по скосу от носа (z −0.48, верх 0.4) к крыше (z −0.3, верх 0.49).
	var shield := _mesh(_model, _box(Vector3(0.4, 0.02, 0.19)), Vector3(0, 0.455, -0.39), _shaded(COLOR_GLASS))
	shield.rotation.x = -atan2(0.49 - 0.4, 0.48 - 0.3)
	# Короткие треугольные крылья: сверху — цвет корпуса с рулём у задней кромки, снизу — чёрные.
	for sx: float in [-1.0, 1.0]:
		var wing := PackedVector2Array([Vector2(0.3 * sx, -0.15), Vector2(0.62 * sx, 0.3), Vector2(0.62 * sx, 0.46),
				Vector2(0.3 * sx, 0.5)])
		var top := MeshKit.prism(_model, wing, 0.28, 0.04, body)
		top.set_meta(&"details", [BodyMaterial.detail(BodyMaterial.Detail.HATCH, Vector3.UP,
				Vector3(0.38 * sx, 0.32, 0.36), Vector3(0.58 * sx, 0.32, 0.47), Vector3.FORWARD)])
		MeshKit.prism(_model, wing, 0.25, 0.03, nose_mat)
	# Маленький киль: контур (вверх, z) выдавлен по X.
	var fin := MeshKit.prism(_model, PackedVector2Array([Vector2(0.0, 0.18), Vector2(0.0, 0.52),
			Vector2(0.26, 0.56), Vector2(0.22, 0.36)]), -0.025, 0.05, _shaded(COLOR_EMERGENCY.darkened(0.15)))
	fin.position = Vector3(0, 0.48, 0)
	fin.rotation.z = PI * 0.5
	# Два сопла маршевых двигателей в корме; посадочные стойки под крыльями и передняя; факелы вниз из днища.
	var nozzle := _shaded(COLOR_NOZZLE)
	for x: float in [-0.12, 0.12]:
		_nozzle(Vector3(x, 0.31, 0.58), 0.045, 0.075, 0.09, nozzle, engine)
	var gear := _shaded(COLOR_GEAR)
	for sx: float in [-1.0, 1.0]:
		_leg(Vector3(sx * 0.54, 0.25, 0.42), 0.25 / cos(0.3), sx * 0.3, 0.025, 0.08, gear)
		for z: float in [-0.18, 0.3]:
			_lift_flame(Vector3(sx * 0.15, 0.13, z), 0.08, 0.75, engine)
	_leg(Vector3(0, 0.135, -0.42), 0.126, 0.0, 0.025, 0.06, gear)
	_lift_glow(2.5)


## Сопло маршевого двигателя в корме (at — середина раструба, ось по Z): тёмный раструб, расширяется к
## срезу; в полёте — свечение среза и факел назад.
func _nozzle(at: Vector3, r_throat: float, r_exit: float, depth: float, mat: Material, engine: Material) -> void:
	var bell := CylinderMesh.new()
	bell.top_radius = r_exit
	bell.bottom_radius = r_throat
	bell.height = depth
	bell.radial_segments = 8
	bell.rings = 0
	_mesh(_model, bell, at, mat).rotation.x = PI * 0.5      # верх цилиндра — назад (+Z)
	var glow := CylinderMesh.new()
	glow.top_radius = r_exit * 0.85
	glow.bottom_radius = r_exit * 0.85
	glow.height = 0.01
	glow.radial_segments = 8
	glow.rings = 0
	var g := _mesh(_model, glow, at + Vector3(0, 0, depth * 0.5 + 0.005), engine)
	g.rotation.x = PI * 0.5
	_thrust.append(g)
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = r_exit * 0.8
	cone.height = r_exit * 4.0
	cone.radial_segments = 6
	cone.rings = 0
	var f := _mesh(_model, cone, at + Vector3(0, 0, depth * 0.5 + r_exit * 2.0), engine)
	f.rotation.x = PI * 0.5
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_thrust.append(f)


## Посадочная стойка: шарнир у основания pivot (низ крыла или корпуса), стойка length вниз с развалом
## splay (рад, наружу — по знаку x), внизу — лапа-тарелка, горизонтальная. Длина — до земли.
func _leg(pivot: Vector3, length: float, splay: float, radius: float, foot_r: float, mat: Material) -> void:
	var hinge := Node3D.new()
	hinge.position = pivot
	hinge.rotation.z = splay
	_model.add_child(hinge)
	var strut := CylinderMesh.new()
	strut.top_radius = radius
	strut.bottom_radius = radius
	strut.height = length
	strut.radial_segments = 6
	strut.rings = 0
	_mesh(hinge, strut, Vector3(0, -length * 0.5, 0), mat)
	var foot := CylinderMesh.new()
	foot.top_radius = foot_r * 0.75
	foot.bottom_radius = foot_r
	foot.height = foot_r * 0.25
	foot.radial_segments = 8
	foot.rings = 0
	_mesh(hinge, foot, Vector3(0, -length, 0), mat).rotation.z = -splay
	_legs.append(hinge)


## Подсветка земли под челноком от факелов вниз (сами факелы сверху почти не видны): точечный свет под
## днищем, горит вместе с ними.
func _lift_glow(radius: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = COLOR_ENGINE
	light.light_energy = 1.6
	light.omni_range = radius
	light.shadow_enabled = false
	light.position = Vector3(0, -0.2, 0.1)
	_model.add_child(light)
	_lift.append(light)


## Факел вниз из днища (сопел в модели нет — сверху их не видно): конус от радиуса radius у днища.
func _lift_flame(at: Vector3, radius: float, length: float, engine: Material) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = radius
	cone.bottom_radius = radius * 0.2
	cone.height = length
	cone.radial_segments = 6
	cone.rings = 0
	var f := _mesh(_model, cone, at + Vector3(0, -length * 0.5, 0), engine)
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lift.append(f)

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

	# Зона погрузки — пунктирное кольцо на земле; штрих — два пикселя мира в ширину, длина — целое их число.
	_zone = Node3D.new()
	_zone.position = Vector3(0, 0.05, 0)
	add_child(_zone)
	_zone_mat = _unshaded(COLOR_RING)
	var dash_len := maxf(snappedf(TAU * zone_r / ZONE_DASHES * 0.55, PX), PX)
	for i in ZONE_DASHES:
		var a := TAU * i / ZONE_DASHES
		var dash := _mesh(_zone, _box(Vector3(PX * 2.0, 0.03, dash_len)), Vector3(cos(a), 0, sin(a)) * zone_r, _zone_mat)
		dash.rotation.y = -a
		dash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.visible = false

	# Знак посадки: круг размером с корпус, косые полосы, мерцает.
	_hazard_mat = ShaderMaterial.new()
	_hazard_mat.shader = HAZARD_SHADER
	_hazard_mat.set_shader_parameter(&"color", COLOR_HAZARD)
	_hazard_mat.set_shader_parameter(&"size", hull_r * 2.0)
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
