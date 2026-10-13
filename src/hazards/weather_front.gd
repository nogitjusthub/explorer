class_name WeatherFront
extends Node3D
## Плохая видимость (GDD §5.5, §5.6): масса тумана или пыли ползёт по карте и заходит в кадр из-за края
## экрана, как гроза; внутри видно только пузырь вокруг машины (шейдеры: weather_* в visibility.gdshaderinc),
## объём дают слои облачного шума (MurkLayers), цвета сцены приглушаются. Вид — жребий при начале:
## - туман — только видимость;
## - кислотный туман — тот же туман, отличается лишь ядовитым цветом: стелется низом (уровень — низина
##   вокруг + acid_rise) и разъедает машину ниже уровня газа;
## - пылевая буря — ветер dust_wind_accel / масса по всему событию, пыль по всему экрану, шанс смерча.
## На пейджере — сообщение без стрелки: откуда придёт непогода, не сказано; кислотный — тоже «ТУМАН».

signal damaged(amount: int, source: StringName)
signal tornado_requested(wind: Vector2)

enum Variant { FOG, ACID, DUST }

const COLORS := {
	Variant.FOG: Color(0.62, 0.66, 0.74), Variant.ACID: Color(0.6, 0.72, 0.3), Variant.DUST: Color(0.62, 0.44, 0.3)}
const KINDS := {Variant.FOG: &"fog", Variant.ACID: &"acid", Variant.DUST: &"dust"}
const NO_GAS := -1000.0

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var streamer: WorldStreamer
var pickups: PickupField
var rng: RandomNumberGenerator
var level := 1

var variant := Variant.FOG
var center := Vector2.ZERO
var direction := Vector2.RIGHT
var radius := 20.0
var speed := 1.3
var wind := Vector2.ZERO
var gas_y := NO_GAS
var coverage := 0.0                       ## плотность массы у машины, 0…1
var force_tornado := false               ## отладка: смерч при входе в бурю при любом уровне
var ended := false
var finished := false

var _layers: MurkLayers
var _acid_acc := 0.0
var _tornado_rolled := false
var _age := 0.0
var _full_radius := 20.0


func _init() -> void:
	name = "WeatherFront"
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


func kind() -> StringName:
	return KINDS[variant]


func begin(v: Variant) -> void:
	variant = v
	var dust := variant == Variant.DUST
	radius = rules.dust_radius if dust else rules.fog_radius
	_full_radius = radius
	speed = rules.dust_speed if dust else rules.fog_speed
	var from := Vector2.from_angle(rng.randf() * TAU)
	center = vehicle.state.pos + from * (radius + rules.murk_gap)
	direction = (-from).rotated(rng.randf_range(-0.3, 0.3))
	if dust:
		wind = direction
	if variant == Variant.ACID:
		gas_y = Grid.tier_to_y(gas_level(query, vehicle.state.pos, rules.acid_scan_r) + rules.acid_rise)
	RenderingServer.global_shader_parameter_set(&"vis_color", COLORS[variant])
	RenderingServer.global_shader_parameter_set(&"weather_clear", rules.dust_visibility if dust else rules.fog_visibility)
	RenderingServer.global_shader_parameter_set(&"weather_gas_y", gas_y)
	RenderingServer.global_shader_parameter_set(&"weather_max", 1.0)
	_build_layers()
	_update_globals()


## Плотность массы в точке (x, z) на высоте y — копия weather_density() из шейдера (без шумового края).
func density(p: Vector2, y: float = -INF) -> float:
	if ended:
		return 0.0
	var dens := 1.0 - smoothstep(radius - 12.0, radius, p.distance_to(center))
	if gas_y > NO_GAS + 1.0 and y > -INF:
		dens *= 1.0 - smoothstep(gas_y - 0.2, gas_y + 0.9, y)
	return dens


## Уровень низины вокруг точки: самый низкий ярус поверхности в квадрате radius (загруженные тайлы).
static func gas_level(q: TerrainQuery, pos: Vector2, scan: int) -> int:
	var lowest := 1 << 20
	var c := Grid.tile_of_world(pos.x, pos.y)
	for tz in range(c.y - scan, c.y + scan + 1, 2):
		for tx in range(c.x - scan, c.x + scan + 1, 2):
			if q.is_loaded(tx, tz):
				lowest = mini(lowest, floori(q.surface_tier(tx + 0.5, tz + 0.5)))
	return lowest if lowest < (1 << 20) else floori(q.surface_tier(pos.x, pos.y))


func step(dt: float) -> void:
	if finished:
		return
	center += direction * speed * dt
	_age += dt
	if _age > rules.murk_max_s:
		# Не гоняемся за машиной вечно: масса тает.
		radius = _full_radius * clampf(1.0 - (_age - rules.murk_max_s) / rules.dissipate_s, 0.0, 1.0)
		if radius <= 1.0:
			_end()
			return
	_update_globals()
	var s := vehicle.state
	coverage = density(s.pos, s.y + 0.3)
	EventBus.weather_changed.emit(kind(), coverage)
	EventBus.threat_telegraphed.emit(kind(), Vector3(center.x, 0.0, center.y), 0.0, direction)
	RenderingServer.global_shader_parameter_set(&"weather_gloom", coverage * (0.5 if variant == Variant.DUST else 0.65))
	if variant == Variant.DUST:
		EventBus.wind_changed.emit(wind, coverage)
		s.ext_accel += wind * rules.dust_wind_accel / vehicle.cls.mass * coverage
		if coverage > 0.5 and not _tornado_rolled:
			_tornado_rolled = true
			if force_tornado or (level >= rules.tornado_min_level and rng.randf() < rules.dust_tornado_chance):
				tornado_requested.emit(wind)
	if variant == Variant.ACID:
		if coverage > 0.3 and not s.drowning:
			_acid_acc += rules.acid_dps * dt * coverage
			if _acid_acc >= 1.0:
				var dmg := floori(_acid_acc)
				_acid_acc -= dmg
				damaged.emit(dmg, &"acid")
	var fade := 1.0
	var to_vehicle := s.pos - center
	if to_vehicle.dot(direction) < 0.0:
		# Масса прошла машину: клубы тают по мере удаления, затем событие кончается.
		fade = clampf(1.0 - (to_vehicle.length() - radius) / rules.murk_gap, 0.0, 1.0)
		if to_vehicle.length() > radius + rules.murk_gap:
			_end()
			return
	_layers.update(Vector3(s.pos.x, s.y, s.pos.y), _clear_r(), fade)


## Конец: массы нет. Сначала последняя сводка («плотность 0», ветер стих), потом «угроза кончилась» —
## кто гасит свои эффекты по концу угрозы (гул бури), после него сводок не получает.
func _end() -> void:
	ended = true
	finished = true
	RenderingServer.global_shader_parameter_set(&"weather_radius", 0.0)
	RenderingServer.global_shader_parameter_set(&"weather_gloom", 0.0)
	EventBus.weather_changed.emit(kind(), 0.0)
	if variant == Variant.DUST:
		EventBus.wind_changed.emit(wind, 0.0)
	EventBus.threat_ended.emit(kind())


func _update_globals() -> void:
	RenderingServer.global_shader_parameter_set(&"weather_center", Vector3(center.x, 0.0, center.y))
	RenderingServer.global_shader_parameter_set(&"weather_radius", 0.0 if ended else radius)


## Сцену закрыли посреди непогоды («Заново»): глобальные параметры шейдеров живут дольше сцены — без
## сброса масса осталась бы и в новом забеге.
func _exit_tree() -> void:
	if not finished:
		_end()


func _clear_r() -> float:
	return rules.dust_visibility if variant == Variant.DUST else rules.fog_visibility


## Слои облачного шума: туман — высокие медленные, пыль — низкие и быстрые по ветру, кислотный газ —
## плотная пелена на уровне газа, которую закрывают возвышенности (видна только в низинах).
func _build_layers() -> void:
	_layers = MurkLayers.new()
	add_child(_layers)
	var c: Color = COLORS[variant]
	match variant:
		Variant.FOG:
			_layers.add_layer(c.lightened(0.2), 0.7, 1.0, 0.09, Vector2(0.12, 0.05))
			_layers.add_layer(c.lightened(0.32), 0.65, 2.2, 0.06, Vector2(-0.06, 0.09))
			_layers.add_layer(c.lightened(0.45), 0.6, 3.6, 0.045, Vector2(0.05, -0.04))
		Variant.ACID:
			_layers.add_layer(c.lightened(0.06), 0.7, gas_y - 0.15, 0.1, Vector2(0.08, 0.04), 0, true, true)
			_layers.add_layer(c.lightened(0.16), 0.55, gas_y - 0.5, 0.06, Vector2(-0.05, 0.07), 0, true, true)
			_layers.add_layer(c.lightened(0.22), 0.3, 1.8, 0.05, Vector2(0.04, -0.03))
		Variant.DUST:
			var w := wind * 0.12
			_layers.add_layer(c.lightened(0.12), 0.6, 0.5, 0.1, w * 1.6)
			_layers.add_layer(c.lightened(0.22), 0.55, 1.4, 0.07, w * 1.2)
			_layers.add_layer(c.lightened(0.32), 0.5, 2.6, 0.05, w)
