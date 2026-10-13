class_name Vehicle
extends Node3D
## Машина игрока: модель класса (VehicleModels), кинематика по сетке (VehicleKinematics), звук двигателя,
## колея и пыль из-под колёс (VehicleTrail).
## Позиция обновляется в _physics_process; плавность на высоких FPS даёт physics interpolation.

signal landed(tiers: int, damage: int)
signal damaged(amount: int, source: StringName)   ## урон от падения или валки дерева (до учёта HP)
signal died(cause: StringName)                    ## гибель, которую решает кинематика (утонула)

const WRECK_DARKEN := 0.72
const FAN_SPEED := 18.0            ## рад/с — вентиляторы ховера
const BEACON_BLINK_S := 0.4        ## период мигания огонька антенны при вызове аварийного челнока
const ROCK_STIFFNESS := 170.0      ## раскачка корпуса от ударов: пружина (≈2 Гц)…
const ROCK_DAMPING := 7.0          ## …с затуханием за полсекунды-секунду
const ROCK_MAX := 0.35             ## рад
## Сила раскачки (начальная угловая скорость, рад/с) от разных ударов.
const ROCK_BITE := 0.9
const ROCK_TREE := 0.8
const ROCK_WALL := 1.8
const ROCK_LANDING := 1.0
const ROCK_RAM := 2.8

var cls: VehicleClass
var query: TerrainQuery
var state := VehicleState.new()
var camera: Camera3D
var autopilot: Autopilot
var control_enabled := true
var out_of_fuel := false        ## бак пуст: машина ползёт не быстрее crawl_speed (GDD §7.3)
var crawl_speed := 0.4          ## тайл/с — предел скорости с пустым баком (задаёт GameFlow из правил)
var wrecked := false
var total_distance := 0.0
var engine: EngineSound
var beacon_calling := false     ## летит аварийный челнок: огонёк антенны ярко мигает и подсвечивает всё вокруг
var inverted_left := 0.0        ## секунд: после разряда (молния, электрошок) направления ввода наоборот

var _tilt := Basis.IDENTITY
var _model: VehicleModels.Model
var _beacon_light: OmniLight3D
var _shock: ShockFx                ## дуги разряда и белые вспышки корпуса, пока управление наоборот
var _trail: VehicleTrail           ## колея на земле, пыль и комья из-под колёс
var _rock := Vector2.ZERO          ## наклон модели от ударов: x — тангаж (нос вверх +), y — крен (правый борт вверх +)
var _rock_vel := Vector2.ZERO
var _tumble := Vector2.ZERO        ## наклон в полёте после броска — равновесие пружины, пока машина в воздухе
var _ride := VehicleRide.new()     ## анимация хода: тряска корпуса, колыхание ховера, антенна-хлыст
var _time := 0.0
var _lift_t := -1.0
var _lift_from := Vector3.ZERO
var _lift_to := Vector3.ZERO
var _lift_s := 1.0


func _init(vehicle_class: VehicleClass, terrain_query: TerrainQuery) -> void:
	cls = vehicle_class
	query = terrain_query
	name = "Vehicle"


func _ready() -> void:
	engine = EngineSound.new()
	add_child(engine)
	_rebuild_model()
	_shock = ShockFx.new()
	add_child(_shock)
	_trail = VehicleTrail.new()
	_trail.setup(cls, query)
	add_child(_trail)


## Смена класса (экран выбора): модель, тон двигателя, высота над водой.
func set_class(vehicle_class: VehicleClass) -> void:
	cls = vehicle_class
	_rebuild_model()
	if _trail != null:
		_trail.set_class(cls)
	place(state.pos, state.heading)


func _rebuild_model() -> void:
	if _model != null:
		_model.root.queue_free()
	_model = VehicleModels.build(cls.id)
	add_child(_model.root)
	_ride = VehicleRide.new()
	_beacon_light = OmniLight3D.new()
	_beacon_light.light_color = VehicleModels.BEACON
	_beacon_light.light_energy = 1.5
	_beacon_light.omni_range = 0.9
	_beacon_light.shadow_enabled = false
	_beacon_light.position = _model.beacon_pos + Vector3(0, 0.05, 0)
	_beacon_light.visible = false
	_model.antenna.add_child(_beacon_light)      # качается вместе с антенной
	engine.pitch_mult = cls.engine_pitch


## Вентиляторы, раскачка от ударов и анимация хода (VehicleRide) — в физическом кадре, вместе с
## интерполяцией машины.
func _animate(dt: float) -> void:
	_time += dt
	for rotor in _model.spinners:
		rotor.rotation.z += FAN_SPEED * (0.4 + 0.6 * state.throttle) * dt * (0.0 if wrecked else 1.0)
	_animate_rock(dt)
	_ride.update(dt, _model, state, cls, query.flags(state.tile.x, state.tile.y), not wrecked, _rock)
	_animate_beacon()


func _animate_rock(dt: float) -> void:
	if wrecked:
		return
	if not state.launched:
		_tumble = Vector2.ZERO
	_rock_vel += (-(_rock - _tumble) * ROCK_STIFFNESS - _rock_vel * ROCK_DAMPING) * dt
	var lim := maxf(ROCK_MAX, _tumble.length() + 0.1)
	_rock = (_rock + _rock_vel * dt).clamp(Vector2(-lim, -lim), Vector2(lim, lim))
	_model.root.rotation.x = _rock.x
	_model.root.rotation.z = _rock.y


## Огонёк антенны: обычно тлеет и чуть дышит; пока летит аварийный челнок — ярко мигает со вспышкой света.
func _animate_beacon() -> void:
	if wrecked:
		_beacon_light.visible = false
		return
	if beacon_calling:
		var on := fmod(_time, BEACON_BLINK_S) < BEACON_BLINK_S * 0.5
		_model.beacon.albedo_color = VehicleModels.BEACON.lightened(0.35) if on else VehicleModels.BEACON_DIM.darkened(0.5)
		_beacon_light.visible = on
	else:
		_model.beacon.albedo_color = VehicleModels.BEACON_DIM.lerp(VehicleModels.BEACON, 0.15 + 0.15 * sin(_time * 2.0))
		_beacon_light.visible = false


func place(pos: Vector2, heading: float = 0.0) -> void:
	state = VehicleState.new()
	state.pos = pos
	state.heading = heading
	state.tile = Grid.tile_of_world(pos.x, pos.y)
	state.y = VehicleKinematics.ground_y(state, cls, query)
	_tilt = _ground_basis()
	_apply_transform()
	reset_physics_interpolation()


## Возрождение (песочница автопилота): машина снова цела, видна и управляема в точке pos. Модель
## пересобирается — сплющенный челноком корпус (crush), потемневшая обшивка (wreck) и поворот в луче
## эвакуации (lift) уходят вместе со старой; луч, разряд, раскачка и пустой бак сброшены, двигатель снова
## заведён.
func respawn(pos: Vector2, heading: float = 0.0) -> void:
	_shock.set_active(false, _model.root)       # вспышки висят на старой модели — снять до её удаления
	_model.root.visible = false                 # старая удаляется в конце кадра — не мелькнуть рядом с новой
	_rebuild_model()
	wrecked = false
	out_of_fuel = false
	inverted_left = 0.0
	beacon_calling = false
	_lift_t = -1.0
	_rock = Vector2.ZERO
	_rock_vel = Vector2.ZERO
	_tumble = Vector2.ZERO
	visible = true
	control_enabled = true
	place(pos, heading)
	if not engine.playing:
		engine.play()


## Раскачка корпуса от удара (укус, таран, стенка, дерево): push — куда толкнули (в мире, по
## плоскости); корпус кренится от удара и качается на пружине. Модель, не кинематика: машину это не двигает.
func rock(strength: float, push: Vector2) -> void:
	if push.length_squared() < 0.0001:
		push = -state.forward()
	push = push.normalized()
	var fwd := state.forward()
	var right := Vector2(-fwd.y, fwd.x)
	# Толкнули назад — нос задирается; толкнули вправо — левый борт поднимается.
	_rock_vel += Vector2(-push.dot(fwd), -push.dot(right)) * strength


## Бросок (червь, смерч, толчок землетрясения): в полёте корпус наклонён в сторону толчка на angle
## (рад) — для кинематографичности; после приземления качается обратно на пружине.
func tumble(push: Vector2, angle: float) -> void:
	if push.length_squared() < 0.0001:
		return
	push = push.normalized()
	var fwd := state.forward()
	var right := Vector2(-fwd.y, fwd.x)
	_tumble = Vector2(-push.dot(fwd), -push.dot(right)) * angle
	rock(ROCK_RAM, push)


## Разряд по машине (молния, электрошок, GDD §5.6): на seconds направления ввода меняются на
## противоположные — по корпусу бегут дуги разряда, корпус мерцает белым, гудят помехи.
func invert_controls(seconds: float) -> void:
	if wrecked or seconds <= 0.0:
		return
	inverted_left = maxf(inverted_left, seconds)
	_shock.set_active(true, _model.root)
	EventBus.controls_inverted.emit(inverted_left)


## Эвакуация: луч челнока плавно втягивает машину в точку to (в мире), потом она скрывается.
func lift(to: Vector3, seconds: float) -> void:
	_lift_t = 0.0
	_lift_from = Vector3(state.pos.x, state.y, state.pos.y)
	_lift_to = to
	_lift_s = seconds
	control_enabled = false


## Челнок сел на машину: корпус сплющен, машина разбита.
func crush() -> void:
	_model.root.scale = Vector3(1.15, 0.3, 1.15)
	wreck()


func _physics_process(dt: float) -> void:
	if _lift_t >= 0.0:
		_lift_t += dt
		var k := minf(_lift_t / _lift_s, 1.0)
		var p := _lift_from.lerp(_lift_to, k * k * (3.0 - 2.0 * k))
		state.pos = Vector2(p.x, p.z)
		state.y = p.y
		_model.root.rotation.y += dt * 2.5 * k
		_ride.update(dt, _model, state, cls, 0, false, _rock)   # в луче тряска стихает, антенна успокаивается
		_trail.track(state, false, dt)
		_apply_transform()
		if k >= 1.0:
			visible = false
			engine.stop()
			_lift_t = -1.0
		return
	var inp := Vector2.ZERO
	if inverted_left > 0.0:
		inverted_left = maxf(inverted_left - dt, 0.0)
		_shock.set_active(inverted_left > 0.0 and not wrecked, _model.root)
	if control_enabled and not wrecked:
		if autopilot != null:
			inp = autopilot.direction(state, dt)
		else:
			inp = VehicleInput.world_direction(camera)
			if inverted_left > 0.0:
				inp = -inp
	var before := state.pos
	state.speed_cap = crawl_speed if out_of_fuel else INF
	var r := VehicleKinematics.step(state, inp, cls, query, dt)
	total_distance += before.distance_to(state.pos)
	if r.landed:
		landed.emit(r.fell_tiers, r.fall_damage)
		EventBus.vehicle_fell.emit(r.fell_tiers, r.fall_damage)
		if r.fall_damage > 0:
			damaged.emit(r.fall_damage, &"fall")
			rock(ROCK_LANDING, -state.forward())
	if r.tree_damage > 0:
		damaged.emit(r.tree_damage, &"tree")
	if r.felled_tree or r.tree_damage > 0:
		rock(ROCK_TREE, -state.forward())
	if r.wall_damage > 0:
		damaged.emit(r.wall_damage, &"wall")
		rock(ROCK_WALL, -state.forward())
	if r.drowned:
		died.emit(&"drowned")
	if not state.falling and not state.drowning:
		_tilt = _tilt.slerp(_ground_basis(), minf(1.0, 12.0 * dt))
	_apply_transform()
	_animate(dt)
	_trail.track(state, not state.falling and not state.launched and not state.drowning, dt)
	if not wrecked:
		engine.update(state.vel.length() / cls.max_speed, state.throttle, dt)
	elif engine.playing:
		engine.volume_db = move_toward(engine.volume_db, -60.0, 40.0 * dt)
		if engine.volume_db <= -59.0:
			engine.stop()


## Гибель над водой (ховер на воде, машина в воде): корпус идёт ко дну, как тонущая. Уже на дне или тонет —
## ничего.
func sink_on_water() -> void:
	var t := state.tile
	if state.drowning or state.falling or not query.is_loaded(t.x, t.y):
		return
	if query.water_tier(t.x, t.y) == TerrainQuery.NO_WATER:
		return
	if state.y <= query.surface_y(state.pos.x, state.pos.y) + 0.01:
		return
	VehicleKinematics.sink_wreck(state)


## Машина разбита: управление отключено, корпус темнеет, двигатель стихает.
func wreck() -> void:
	wrecked = true
	for mat in _model.materials:
		BodyMaterial.set_color(mat, BodyMaterial.color_of(mat).darkened(WRECK_DARKEN))


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
