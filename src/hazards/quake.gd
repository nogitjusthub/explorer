class_name Quake
extends Node3D
## Землетрясение (GDD §5.3): сообщение на пейджере «ЗЕМЛЕТРЯСЕНИЕ», за quake_telegraph_s до сдвига —
## тряска и гул нарастают (пик — на сдвиге, потом затухают); за quake_line_s до сдвига на поверхности
## проступает линия разлома с пылью и вся меняет цвет от белого к красному; затем сразу сдвиг.
## Сила толчка 0…1 (случайно, выше на высоком уровне угрозы) задаёт длину разлома
## (fault_length_min…max), высоту сброса (одна сторона поднимается на 1…fault_up_max, другая
## опускается на 0…fault_down_max) и редкость пандусов (fault_ramp_every_min…max) — сильный толчок
## даёт длинный разлом со сплошными обрывами. Линия — ломаная из 1–4 отрезков (сгибы до 45°,
## чередуются); вдоль неё — осыпь (неровный грунт, fault_debris_r). Машину на сдвинутом блоке подбрасывает от линии по дуге
## на quake_toss_dist тайлов: урон + падение. Разлом не ложится ближе fault_pad_clearance к площадкам
## и только на загруженный рельеф.

signal damaged(amount: int, source: StringName)

const TRIES := 12
const AFTER_S := 1.2                     ## пыль оседает после толчка
const COLOR_LINE_FROM := Color(1.0, 1.0, 1.0)
const COLOR_LINE_TO := Color(0.95, 0.12, 0.08)
const AFTER_SHAKE_S := 1.5               ## тряска после сдвига затухает за столько
const COLOR_DUST := Color(0.62, 0.5, 0.42, 0.55)
const SEGMENT_MIN := 5.0                 ## тайлов — отрезок ломаной разлома не короче
const MAX_BEND := 45.0                   ## градусов — сгиб между отрезками (угол между ними 135…180°)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var streamer: WorldStreamer
var pickups: PickupField
var rng: RandomNumberGenerator
var level := 3                           ## уровень угрозы (сила толчка растёт с ним)

var strength := 0.5
var path := PackedVector2Array()         ## линия разлома, мировые точки
var up := 1
var down := 0
var ramp_every := 5
var finished := false

var _length := 20.0
var _lengths := PackedFloat32Array()
var _coords: FaultLine       ## координаты зоны относительно линии — считаются во время телеграфа
var _left := 0.0
var _struck := false
var _after := AFTER_S
var _shake_timer := 0.0
var _crack_mat: StandardMaterial3D
var _dust: CPUParticles3D


func _init() -> void:
	name = "Quake"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Сила, форма и место; начало телеграфа. false — подходящего места рядом нет, землетрясения не будет.
func begin() -> bool:
	strength = clampf(rng.randf() * 0.75 + 0.1 * (level - rules.quake_min_level), 0.0, 1.0)
	_length = lerpf(rules.fault_length_min, rules.fault_length_max, strength)
	up = clampi(1 + roundi(strength * (rules.fault_up_max - 1) + rng.randf_range(-0.4, 0.4)), 1, rules.fault_up_max)
	down = clampi(roundi(strength * rules.fault_down_max * rng.randf_range(0.6, 1.1)), 0, rules.fault_down_max)
	ramp_every = roundi(lerpf(rules.fault_ramp_every_min, rules.fault_ramp_every_max, strength))
	for attempt in TRIES:
		if attempt == TRIES / 2:
			_length = maxf(_length * 0.7, rules.fault_length_min)     # места не нашлось — разлом покороче
		var c := vehicle.state.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 9.0)
		path = make_path(c, rng.randf() * TAU, _length, rng)
		if _placement_ok():
			_lengths = FaultLine.path_lengths(path)
			_coords = FaultLine.new(path, up, down)
			_left = rules.quake_telegraph_s
			_build_telegraph()
			return true
	return false


## Линия разлома — ломаная длиной length из 1–4 отрезков разной длины (каждый не короче SEGMENT_MIN):
## между соседними угол от 135° до 180° (сгиб не больше MAX_BEND), сгибы чередуются — то в одну
## сторону, то в другую. Центр — в center, общее направление — angle.
static func make_path(center: Vector2, angle: float, length: float, r: RandomNumberGenerator) -> PackedVector2Array:
	var count := r.randi_range(1, clampi(floori(length / SEGMENT_MIN), 1, 4))
	# Длины: каждому по SEGMENT_MIN, остаток — по случайным весам: отрезки выходят разные.
	var weights := PackedFloat32Array()
	var sum := 0.0
	for k in count:
		weights.append(r.randf_range(0.3, 1.0))
		sum += weights[k]
	var spare := length - SEGMENT_MIN * count
	var local := PackedVector2Array([Vector2.ZERO])
	var dir := 0.0
	var side := 1.0 if r.randf() < 0.5 else -1.0
	for k in count:
		if k > 0:
			dir += deg_to_rad(r.randf_range(0.0, MAX_BEND)) * side
			side = -side
		local.append(local[k] + Vector2.from_angle(dir) * (SEGMENT_MIN + spare * weights[k] / sum))
	var mid := FaultLine.path_bounds(local).get_center()
	var out := PackedVector2Array()
	for q in local:
		out.append(center + (q - mid).rotated(angle))
	return out


func step(dt: float) -> void:
	if not _struck:
		_coords.prepare(1)                  # тяжёлый расчёт — порциями, пока идёт телеграф
		_left -= dt
		var k := 1.0 - _left / rules.quake_telegraph_s
		EventBus.threat_telegraphed.emit(&"quake", _center3(), maxf(_left, 0.0), Vector2.ZERO)
		_shake_timer -= dt
		if _shake_timer <= 0.0:
			_shake_timer = 0.15
			EventBus.camera_shake_requested.emit((0.1 + 0.7 * k * k) * (0.7 + 0.6 * strength), 0.25)
		# За quake_line_s до сдвига — линия: вся сразу, цвет от белого к красному.
		var line_k := 1.0 - _left / rules.quake_line_s
		if line_k >= 0.0:
			var crack := get_node(^"Crack") as Node3D
			if not crack.visible:
				crack.visible = true
				_dust.emitting = true
			_crack_mat.albedo_color = COLOR_LINE_FROM.lerp(COLOR_LINE_TO, clampf(line_k, 0.0, 1.0))
		if _left <= 0.0:
			_strike()
		return
	_after -= dt
	if _after <= 0.0:
		finished = true


func _strike() -> void:
	_struck = true
	_dust.amount = int(_dust.amount * 2)
	var vt := vehicle.state.tile
	var before := _tile_corners(vt)
	Deformation.fault_path(terrain, path, up, down, ramp_every, _coords)
	Deformation.mark_ground(terrain, _debris_tiles(), ChunkData.FLAG_ROUGH)
	streamer.request_pit_fill()
	EventBus.threat_ended.emit(&"quake")
	EventBus.camera_shake_requested.emit(1.2 + 0.8 * strength, AFTER_SHAKE_S)
	(get_node(^"Crack") as Node3D).visible = false
	var s := vehicle.state
	if _tile_corners(vt) != before and not s.falling and not s.drowning:
		_toss()


## Осыпь вдоль линии: тайлы ближе fault_debris_r к разлому (кроме самых концов).
func _debris_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var box := FaultLine.path_bounds(path).grow(rules.fault_debris_r + 1.0)
	for tz in range(floori(box.position.y), ceili(box.end.y)):
		for tx in range(floori(box.position.x), ceili(box.end.x)):
			var cc := FaultLine.path_coords(path, _lengths, Vector2(tx + 0.5, tz + 0.5), rules.fault_debris_r + 1.0)
			if absf(cc.y) <= rules.fault_debris_r and cc.x > 1.0 and cc.x < _length - 1.0:
				out.append(Vector2i(tx, tz))
	return out


## Машину на сдвинутом блоке подбрасывает от линии разлома (поперёк неё, в сторону машины).
func _toss() -> void:
	var s := vehicle.state
	var cc := FaultLine.path_coords(path, _lengths, s.pos)
	var dir := Vector2(cc.z, cc.w) * (1.0 if cc.y >= 0.0 else -1.0)
	var target := s.pos + dir * rules.quake_toss_dist
	for _i in 3:
		var t := Grid.tile_of_world(target.x, target.y)
		if query.is_loaded(t.x, t.y):
			break
		target = s.pos + (target - s.pos) * 0.5
	VehicleKinematics.launch(s, target, 1.0, vehicle.cls, query)
	vehicle.tumble(target - s.pos, 0.25)
	damaged.emit(rules.quake_toss_damage, &"quake")


func _placement_ok() -> bool:
	var band := rules.fault_up_max + 4
	var rect := FaultLine.path_bounds(path).grow(band)
	for p in [rect.position, rect.end, Vector2(rect.position.x, rect.end.y), Vector2(rect.end.x, rect.position.y)]:
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y):
			return false
	# Площадки — по одной на блок генератора; мерим расстояние от площадки до самой линии (у дуги и
	# полумесяца рамка много больше зоны разлома).
	var clear := band + rules.fault_pad_clearance + generator.p.pad_half
	var reach := rect.grow(rules.fault_pad_clearance + generator.p.pad_half)
	var block := float(generator.p.pad_block)
	var lengths := FaultLine.path_lengths(path)
	for bz in range(floori(reach.position.y / block), floori(reach.end.y / block) + 1):
		for bx in range(floori(reach.position.x / block), floori(reach.end.x / block) + 1):
			var pad := generator.pad_of_block(Vector2i(bx, bz))
			if pad.z == TerrainGenerator.NO_PAD:
				continue
			var cc := FaultLine.path_coords(path, lengths, Vector2(pad.x + 0.5, pad.y + 0.5), clear)
			if absf(cc.y) < clear:
				return false
	return true


func _tile_corners(t: Vector2i) -> Array[int]:
	return [query.corner(t.x, t.y, 0), query.corner(t.x, t.y, 1), query.corner(t.x, t.y, 2), query.corner(t.x, t.y, 3)]


## Середина линии разлома (по длине).
func _center3() -> Vector3:
	var half := _length * 0.5
	var c := path[0]
	for i in range(1, path.size()):
		if _lengths[i] >= half:
			var k := (half - _lengths[i - 1]) / maxf(_lengths[i] - _lengths[i - 1], 1e-6)
			c = path[i - 1].lerp(path[i], k)
			break
	return Vector3(c.x, query.surface_y(c.x, c.y), c.y)


## Линия разлома на поверхности (темнеет к толчку) и пыль вдоль неё.
func _build_telegraph() -> void:
	var crack := Node3D.new()
	crack.name = "Crack"
	add_child(crack)
	crack.visible = false
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.albedo_color = COLOR_LINE_FROM
	var points := PackedVector3Array()
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var pieces := maxi(ceili(a.distance_to(b)), 1)      # по кусочку на тайл — трещина ложится по рельефу
		for k in pieces:
			var p0 := a.lerp(b, float(k) / pieces)
			var p1 := a.lerp(b, float(k + 1) / pieces)
			var mid := (p0 + p1) * 0.5
			var d := p1 - p0
			var seg := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(d.length() + 0.05, 0.03, 0.12)
			seg.mesh = box
			seg.material_override = _crack_mat
			seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var y := query.surface_y(mid.x, mid.y)
			seg.position = Vector3(mid.x, y + 0.03, mid.y)
			seg.rotation.y = -atan2(d.y, d.x) + rng.randf_range(-0.12, 0.12)
			crack.add_child(seg)
			points.append(Vector3(mid.x, y + 0.1, mid.y))
	_dust = CPUParticles3D.new()
	_dust.amount = clampi(roundi(_length * 1.6), 16, 64)
	_dust.lifetime = 1.4
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_POINTS
	_dust.emission_points = points
	_dust.direction = Vector3.UP
	_dust.spread = 25.0
	_dust.initial_velocity_min = 0.4
	_dust.initial_velocity_max = 1.2
	_dust.gravity = Vector3(0, -0.6, 0)
	_dust.scale_amount_min = 0.5
	_dust.scale_amount_max = 1.0
	var quad := QuadMesh.new()
	quad.size = Vector2(0.22, 0.22)
	var dust_mat := StandardMaterial3D.new()
	dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	dust_mat.albedo_color = COLOR_DUST
	quad.material = dust_mat
	_dust.mesh = quad
	_dust.emitting = false
	add_child(_dust)
