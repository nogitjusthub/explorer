class_name Quake
extends Node3D
## Землетрясение (GDD §5.3): телеграф quake_telegraph_s — нарастающая тряска камеры, пыль и линия
## разлома на поверхности, пейджер «СЕЙСМИКА»; затем разлом длиной fault_length рядом с машиной:
## одна сторона поднимается на 1…up_max, другая опускается на 0…down_max, вдоль линии — пандусы.
## Машину на сдвинутом блоке подбрасывает по дуге на quake_toss_dist тайлов: урон + падение.
## Разлом не ложится ближе fault_pad_clearance к площадкам и только на загруженный рельеф.

signal damaged(amount: int, source: StringName)

const TRIES := 12
const AFTER_S := 1.2                     ## пыль оседает после толчка
const COLOR_CRACK := Color(0.12, 0.07, 0.06)
const COLOR_DUST := Color(0.62, 0.5, 0.42, 0.55)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var streamer: WorldStreamer
var pickups: PickupField
var rng: RandomNumberGenerator

var start := Vector2i.ZERO               ## вершина начала линии разлома
var along_x := true
var up := 1
var down := 0
var finished := false

var _left := 0.0
var _struck := false
var _after := AFTER_S
var _shake_timer := 0.0
var _crack_mat: StandardMaterial3D
var _dust: CPUParticles3D


func _init() -> void:
	name = "Quake"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Выбор места и начало телеграфа. false — подходящего места рядом нет, землетрясения не будет.
func begin() -> bool:
	for _i in TRIES:
		along_x = rng.randf() < 0.5
		var c := vehicle.state.pos + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(3.0, 9.0)
		var half := rules.fault_length / 2
		start = Vector2i(floori(c.x) - half, floori(c.y)) if along_x else Vector2i(floori(c.x), floori(c.y) - half)
		if _placement_ok():
			up = rng.randi_range(1, rules.fault_up_max)
			down = rng.randi_range(0, rules.fault_down_max)
			_left = rules.quake_telegraph_s
			_build_telegraph()
			return true
	return false


func step(dt: float) -> void:
	if not _struck:
		_left -= dt
		var k := 1.0 - _left / rules.quake_telegraph_s
		EventBus.threat_telegraphed.emit(&"quake", _center3(), maxf(_left, 0.0), Vector2.ZERO)
		_shake_timer -= dt
		if _shake_timer <= 0.0:
			_shake_timer = 0.15
			EventBus.camera_shake_requested.emit(0.2 + 0.6 * k, 0.25)
		_crack_mat.albedo_color.a = clampf(k * 1.4, 0.0, 1.0)
		if _left <= 0.0:
			_strike()
		return
	_after -= dt
	if _after <= 0.0:
		finished = true


func _strike() -> void:
	_struck = true
	_dust.amount = 64
	var vt := vehicle.state.tile
	var before := _tile_corners(vt)
	Deformation.fault(terrain, start, along_x, rules.fault_length, up, down)
	streamer.request_pit_fill()
	EventBus.threat_ended.emit(&"quake")
	EventBus.camera_shake_requested.emit(1.6, 1.0)
	(get_node(^"Crack") as Node3D).visible = false
	var s := vehicle.state
	if _tile_corners(vt) != before and not s.falling and not s.drowning:
		_toss()


## Машину на сдвинутом блоке подбрасывает от линии разлома.
func _toss() -> void:
	var s := vehicle.state
	var across := Vector2(0, 1) if along_x else Vector2(1, 0)
	var offset := (s.pos.y - start.y) if along_x else (s.pos.x - start.x)
	var dir := across * (1.0 if offset >= 0.0 else -1.0)
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
	var lo := start + (Vector2i(-1, -band) if along_x else Vector2i(-band, -1))
	var hi := start + (Vector2i(rules.fault_length + 1, band) if along_x else Vector2i(band, rules.fault_length + 1))
	for tz in [lo.y, hi.y]:
		for tx in [lo.x, hi.x]:
			if not query.is_loaded(tx, tz):
				return false
	# Площадки — по одной на блок генератора; проверяем блоки вокруг прямоугольника разлома.
	var reach := rules.fault_pad_clearance + generator.p.pad_half
	var block := float(generator.p.pad_block)
	var rect := Rect2(Vector2(lo), Vector2(hi - lo)).grow(reach)
	for bz in range(floori(rect.position.y / block), floori(rect.end.y / block) + 1):
		for bx in range(floori(rect.position.x / block), floori(rect.end.x / block) + 1):
			var pad := generator.pad_of_block(Vector2i(bx, bz))
			if pad.z != TerrainGenerator.NO_PAD and rect.has_point(Vector2(pad.x + 0.5, pad.y + 0.5)):
				return false
	return true


func _tile_corners(t: Vector2i) -> Array[int]:
	return [query.corner(t.x, t.y, 0), query.corner(t.x, t.y, 1), query.corner(t.x, t.y, 2), query.corner(t.x, t.y, 3)]


func _center3() -> Vector3:
	var half := rules.fault_length * 0.5
	var c := Vector2(start) + (Vector2(half, 0) if along_x else Vector2(0, half))
	return Vector3(c.x, query.surface_y(c.x, c.y), c.y)


## Линия разлома на поверхности (темнеет к толчку) и пыль вдоль неё.
func _build_telegraph() -> void:
	var crack := Node3D.new()
	crack.name = "Crack"
	add_child(crack)
	_crack_mat = StandardMaterial3D.new()
	_crack_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_crack_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_crack_mat.albedo_color = Color(COLOR_CRACK, 0.0)
	for a in range(1, rules.fault_length - 1):
		var v := start + (Vector2i(a, 0) if along_x else Vector2i(0, a))
		var p := Vector2(v) + (Vector2(0.5, 0) if along_x else Vector2(0, 0.5))
		var seg := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.0, 0.03, 0.12) if along_x else Vector3(0.12, 0.03, 1.0)
		seg.mesh = box
		seg.material_override = _crack_mat
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		seg.position = Vector3(p.x, query.surface_y(p.x, p.y) + 0.03, p.y)
		seg.rotation.y = rng.randf_range(-0.12, 0.12)
		crack.add_child(seg)
	_dust = CPUParticles3D.new()
	var c := _center3()
	_dust.position = c
	_dust.amount = 32
	_dust.lifetime = 1.4
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(rules.fault_length * 0.5, 0.1, 0.3) if along_x \
			else Vector3(0.3, 0.1, rules.fault_length * 0.5)
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
	add_child(_dust)
