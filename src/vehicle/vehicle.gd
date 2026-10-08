class_name Vehicle
extends Node3D
## Машина игрока: модель класса (VehicleModels), кинематика по сетке (VehicleKinematics), звук двигателя.
## Позиция обновляется в _physics_process; плавность на высоких FPS даёт physics interpolation.

signal landed(tiers: int, damage: int)
signal damaged(amount: int, source: StringName)   ## урон от падения или валки дерева (до учёта HP)
signal died(cause: StringName)                    ## гибель, которую решает кинематика (утонула)

const WRECK_DARKEN := 0.72
const FAN_SPEED := 18.0            ## рад/с — вентиляторы ховера

var cls: VehicleClass
var query: TerrainQuery
var state := VehicleState.new()
var camera: Camera3D
var autopilot: Autopilot
var control_enabled := true
var engine_running := true      ## false — двигатель заглох (пустой бак): газа нет, машина катится до остановки
var wrecked := false
var total_distance := 0.0
var engine: EngineSound

var _tilt := Basis.IDENTITY
var _model: VehicleModels.Model
var _time := 0.0


func _init(vehicle_class: VehicleClass, terrain_query: TerrainQuery) -> void:
	cls = vehicle_class
	query = terrain_query
	name = "Vehicle"


func _ready() -> void:
	engine = EngineSound.new()
	add_child(engine)
	_rebuild_model()


## Смена класса (экран выбора): модель, тон двигателя, высота над водой.
func set_class(vehicle_class: VehicleClass) -> void:
	cls = vehicle_class
	_rebuild_model()
	place(state.pos, state.heading)


func _rebuild_model() -> void:
	if _model != null:
		_model.root.queue_free()
	_model = VehicleModels.build(cls.id)
	add_child(_model.root)
	engine.pitch_mult = cls.engine_pitch


## Вентиляторы и покачивание ховера — в физическом кадре, вместе с интерполяцией машины.
func _animate(dt: float) -> void:
	_time += dt
	for rotor in _model.spinners:
		rotor.rotation.z += FAN_SPEED * (0.4 + 0.6 * state.throttle) * dt * (0.0 if wrecked else 1.0)
	if _model.hover_height > 0.0:
		var bob := 0.0 if wrecked else sin(_time * 3.0) * 0.012
		_model.root.position.y = _model.hover_height + bob


func place(pos: Vector2, heading: float = 0.0) -> void:
	state = VehicleState.new()
	state.pos = pos
	state.heading = heading
	state.tile = Grid.tile_of_world(pos.x, pos.y)
	state.y = VehicleKinematics.ground_y(state, cls, query)
	_tilt = _ground_basis()
	_apply_transform()
	reset_physics_interpolation()


func _physics_process(dt: float) -> void:
	var inp := Vector2.ZERO
	if control_enabled and engine_running and not wrecked:
		inp = autopilot.direction(state, dt) if autopilot != null else VehicleInput.world_direction(camera)
	var before := state.pos
	var r := VehicleKinematics.step(state, inp, cls, query, dt)
	total_distance += before.distance_to(state.pos)
	if r.landed:
		landed.emit(r.fell_tiers, r.fall_damage)
		EventBus.vehicle_fell.emit(r.fell_tiers, r.fall_damage)
		if r.fall_damage > 0:
			damaged.emit(r.fall_damage, &"fall")
	if r.tree_damage > 0:
		damaged.emit(r.tree_damage, &"tree")
	if r.wall_damage > 0:
		damaged.emit(r.wall_damage, &"wall")
	if r.drowned:
		died.emit(&"drowned")
	if not state.falling and not state.drowning:
		_tilt = _tilt.slerp(_ground_basis(), minf(1.0, 12.0 * dt))
	_apply_transform()
	_animate(dt)
	if engine_running and not wrecked:
		engine.update(state.vel.length() / cls.max_speed, state.throttle, dt)
	elif engine.playing:
		engine.volume_db = move_toward(engine.volume_db, -60.0, 40.0 * dt)
		if engine.volume_db <= -59.0:
			engine.stop()


## Машина разбита: управление отключено, корпус темнеет, двигатель стихает.
func wreck() -> void:
	wrecked = true
	for mat in _model.materials:
		mat.albedo_color = mat.albedo_color.darkened(WRECK_DARKEN)


func _apply_transform() -> void:
	transform = Transform3D(_tilt, Vector3(state.pos.x, state.y, state.pos.y))


## Ориентация по курсу и наклону поверхности (4 точки контакта).
func _ground_basis() -> Basis:
	var f := state.forward()
	var fwd := Vector3(f.x, 0.0, f.y)
	var right := Vector3(-f.y, 0.0, f.x)
	var p := state.pos
	var hf := _height(p.x + f.x * 0.45, p.y + f.y * 0.45)
	var hb := _height(p.x - f.x * 0.45, p.y - f.y * 0.45)
	var hr := _height(p.x + right.x * 0.3, p.y + right.z * 0.3)
	var hl := _height(p.x - right.x * 0.3, p.y - right.z * 0.3)
	var f3 := Vector3(fwd.x * 0.9, hf - hb, fwd.z * 0.9).normalized()
	var r3 := Vector3(right.x * 0.6, hr - hl, right.z * 0.6).normalized()
	var up := r3.cross(f3).normalized()
	return Basis.looking_at(f3, up)


## Высота опоры: поверхность, а для машины на подушке — не ниже зеркала воды.
func _height(x: float, z: float) -> float:
	if cls.hovers:
		return Grid.tier_to_y(query.surface_tier_float(x, z))
	return query.surface_y(x, z)
