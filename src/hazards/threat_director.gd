class_name ThreatDirector
extends Node
## Угрозы забега (GDD §5, §7.1). Уровень угрозы T растёт со временем и пройденным путём.
## Погода циклична: ясно → событие → ясно, паузы короче с ростом T. Землетрясения — по своему
## таймеру с T ≥ quake_min_level. После сдачи груза основному челноку — затишье: новые угрозы не
## начинаются, текущие идут до конца. Угрозы — дочерние узлы, GameFlow вызывает step() в своём
## физическом кадре; урон машине они передают сигналом damaged.

signal damaged(amount: int, source: StringName)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var streamer: WorldStreamer
var pickups: PickupField
var run_seed: int
var enabled := true
var min_level := 1                         ## отладка: не ниже этого уровня
var forced: Array[Dictionary] = []         ## отладка: [{kind, at}] — событие на заданной секунде

var level := 1
var stats := {"storm": 0, "quake": 0, "strikes": 0}   ## для отчёта бенчмарка
var _rng: RandomNumberGenerator
var _time := 0.0
var _distance0 := 0.0
var _clear_left := 0.0
var _quake_left := 0.0
var _calm_left := 0.0
var _weather: Node = null
var _quake: Quake = null


func _ready() -> void:
	name = "ThreatDirector"
	EventBus.cargo_shipped.connect(_on_cargo_shipped)
	EventBus.lightning_struck.connect(func(_at: Vector3) -> void: stats["strikes"] += 1)


## Начало забега: таймеры с нуля.
func begin() -> void:
	_rng = DetRng.rng_for(run_seed, 0, 0, 800)
	_time = 0.0
	_distance0 = vehicle.total_distance
	_clear_left = rules.first_event_s
	_quake_left = rules.quake_interval_t3_s
	_calm_left = 0.0


## T = min(max; 1 + floor(t / шаг времени) + floor(путь / шаг пути)).
static func threat_level(r: BalanceRules, seconds: float, distance: float) -> int:
	return mini(r.threat_max, 1 + floori(seconds / r.threat_time_step_s) + floori(distance / r.threat_dist_step))


## Пауза ясной погоды при уровне t: от clear_t1_s при T = 1 до clear_t6_s при T = 6, ±30%.
static func clear_duration(r: BalanceRules, t: int, roll: float) -> float:
	var base := lerpf(r.clear_t1_s, r.clear_t6_s, clampf((t - 1) / 5.0, 0.0, 1.0))
	return base * lerpf(0.7, 1.3, roll)


static func quake_interval(r: BalanceRules, t: int, roll: float) -> float:
	var base := r.quake_interval_t3_s if t <= r.quake_min_level else r.quake_interval_t4_s
	return base * lerpf(0.75, 1.25, roll)


func in_calm() -> bool:
	return _calm_left > 0.0


## Радар глушит гроза, если машина под фронтом.
func radar_jammed() -> bool:
	var storm := _weather as StormFront
	return storm != null and storm.covers(vehicle.state.pos)


func step(dt: float) -> void:
	if not enabled:
		return
	_time += dt
	level = maxi(min_level, threat_level(rules, _time, vehicle.total_distance - _distance0))
	_calm_left = maxf(_calm_left - dt, 0.0)
	for i in range(forced.size() - 1, -1, -1):
		if _time >= forced[i]["at"]:
			_start(forced[i]["kind"])
			forced.remove_at(i)

	if _weather != null:
		_weather.call(&"step", dt)
		if _weather.get(&"finished"):
			_weather.queue_free()
			_weather = null
			_clear_left = clear_duration(rules, level, _rng.randf())
	else:
		_clear_left -= dt
		if _clear_left <= 0.0 and not in_calm():
			_start(_pick_weather())

	if level >= rules.quake_min_level:
		_quake_left -= dt
		if _quake_left <= 0.0 and _quake == null and not in_calm():
			_quake_left = quake_interval(rules, level, _rng.randf())
			if not _start(&"quake"):
				_quake_left = 5.0      # рядом площадка или край загрузки — попробуем чуть позже
	if _quake != null:
		_quake.step(dt)
		if _quake.finished:
			_quake.queue_free()
			_quake = null


## Какое погодное событие сейчас (M3a — только гроза; туман и пылевая буря — в M3b).
func _pick_weather() -> StringName:
	return &"storm"


## Запуск угрозы. false — не началась (уже идёт такая же или ей нет места).
func _start(kind: StringName) -> bool:
	match kind:
		&"storm":
			if _weather != null:
				return false
			var storm := StormFront.new()
			_setup(storm)
			add_child(storm)
			storm.begin()
			_weather = storm
			stats["storm"] += 1
			return true
		&"quake":
			if _quake != null:
				return false
			var quake := Quake.new()
			_setup(quake)
			add_child(quake)
			if quake.begin():
				_quake = quake
				stats["quake"] += 1
				return true
			quake.queue_free()
	return false


func _setup(hazard: Node) -> void:
	hazard.set(&"rules", rules)
	hazard.set(&"vehicle", vehicle)
	hazard.set(&"query", query)
	hazard.set(&"terrain", terrain)
	hazard.set(&"generator", generator)
	hazard.set(&"streamer", streamer)
	hazard.set(&"pickups", pickups)
	hazard.set(&"rng", _rng)
	hazard.connect(&"damaged", func(amount: int, source: StringName) -> void: damaged.emit(amount, source))


func _on_cargo_shipped(_value: int, emergency: bool) -> void:
	if not emergency:
		_calm_left = rules.calm_after_ship_s
