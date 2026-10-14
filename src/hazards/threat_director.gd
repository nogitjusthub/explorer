class_name ThreatDirector
extends Node
## Угрозы забега (GDD §5, §7.1). Уровень угрозы T растёт со временем и пройденным путём.
## Непогода циклична: ясно → событие → ясно, паузы короче с ростом T. Событие — гроза или плохая
## видимость (WeatherFront: туман, кислотный туман или пылевая буря — жребий). Землетрясения и смерчи —
## по своим таймерам с T ≥ 3; в пылевой буре смерч ещё и может родиться при входе в неё. Водоворот —
## с T ≥ 2, пока машина над глубокой водой: по курсу, на глубине 2×2 тайла. После сдачи
## груза основному челноку — затишье: новые угрозы не начинаются, текущие идут до конца.
## Угрозы — дочерние узлы, GameFlow вызывает step() в своём физическом кадре; урон — сигналом damaged.

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
var stats := {"storm": 0, "quake": 0, "strikes": 0, "fog": 0, "acid": 0, "dust": 0, "tornado": 0, "whirlpool": 0}   ## для отчёта бенчмарка
var _rng: RandomNumberGenerator
var _time := 0.0
var _distance0 := 0.0
var _clear_left := 0.0
var _quake_left := 0.0
var _tornado_left := 0.0
var _whirl_left := 0.0
var _whirl_check := 0.0
var _calm_left := 0.0
var _weather: Node = null                  ## StormFront или WeatherFront
var _quake: Quake = null
var _tornado: Tornado = null
var _whirlpool: Whirlpool = null


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
	_tornado_left = rules.tornado_interval_t3_s
	_whirl_left = rules.whirlpool_interval_s * 0.5
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


static func tornado_interval(r: BalanceRules, t: int, roll: float) -> float:
	var base := r.tornado_interval_t3_s if t <= r.tornado_min_level else r.tornado_interval_t4_s
	return base * lerpf(0.75, 1.25, roll)


## Жребий вида плохой видимости: туман всегда, кислотный с acid_min_level, буря с dust_min_level;
## туман и кислотный чаще у озёр, буря — на кратерах и равнинах. roll ∈ [0, 1).
static func murk_variant(r: BalanceRules, t: int, biome: int, roll: float) -> WeatherFront.Variant:
	var lake := biome == ChunkData.Biome.LAKESIDE
	var open := biome == ChunkData.Biome.CRATERS or biome == ChunkData.Biome.PLAINS
	var fog := r.fog_weight * (r.biome_weather_weight if lake else 1.0)
	var acid := r.acid_weight * (r.biome_weather_weight if lake else 1.0) if t >= r.acid_min_level else 0.0
	var dust := r.dust_weight * (r.biome_weather_weight if open else 1.0) if t >= r.dust_min_level else 0.0
	var x := roll * (fog + acid + dust)
	if x < fog:
		return WeatherFront.Variant.FOG
	if x < fog + acid:
		return WeatherFront.Variant.ACID
	return WeatherFront.Variant.DUST


func in_calm() -> bool:
	return _calm_left > 0.0


## Сколько тайлов видно вокруг машины (карта мира: разведанное): в ясную погоду — clear_sky; в массе тумана
## или пыли — до её просвета (clear_radius) по плотности массы в точке (кислотный туман выше газа не мешает);
## под грозовыми тучами — до storm_visibility по тому, как глубоко машина под фронтом.
func visibility(pos: Vector2, y: float, clear_sky: float) -> float:
	var front := _weather as WeatherFront
	if front != null:
		return lerpf(clear_sky, minf(front.clear_radius(), clear_sky), clampf(front.density(pos, y), 0.0, 1.0))
	var storm := _weather as StormFront
	if storm != null:
		return lerpf(clear_sky, minf(rules.storm_visibility, clear_sky), clampf(storm.coverage, 0.0, 1.0))
	return clear_sky


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
			if _start(forced[i]["kind"]):
				DevTools.mark("event:%s" % forced[i]["kind"])    # этап для замеров (web_bench)
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
			_start(&"storm" if _rng.randf() >= rules.murk_share else &"murk")

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

	if level >= rules.tornado_min_level:
		_tornado_left -= dt
		if _tornado_left <= 0.0 and _tornado == null and not in_calm():
			_tornado_left = tornado_interval(rules, level, _rng.randf())
			_start(&"tornado")
	if _tornado != null:
		_tornado.step(dt)
		if _tornado.finished:
			_tornado.queue_free()
			_tornado = null

	if level >= rules.whirlpool_min_level and _whirlpool == null:
		_whirl_left -= dt
		_whirl_check -= dt
		if _whirl_left <= 0.0 and _whirl_check <= 0.0 and not in_calm():
			_whirl_check = 2.0
			if _over_deep_water() and _rng.randf() < rules.whirlpool_chance:
				if _spawn_whirlpool(Whirlpool.SPAWN_MIN, Whirlpool.SPAWN_MAX):
					_whirl_left = rules.whirlpool_interval_s * lerpf(0.75, 1.25, _rng.randf())
	if _whirlpool != null:
		_whirlpool.step(dt)
		if _whirlpool.finished:
			_whirlpool.queue_free()
			_whirlpool = null


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
		&"murk", &"fog", &"acid", &"dust":
			if _weather != null:
				return false
			var variant := WeatherFront.Variant.FOG
			match kind:
				&"murk":
					var t := vehicle.state.tile
					variant = murk_variant(rules, level, query.biome(t.x, t.y), _rng.randf())
				&"acid":
					variant = WeatherFront.Variant.ACID
				&"dust":
					variant = WeatherFront.Variant.DUST
			var front := WeatherFront.new()
			_setup(front)
			front.level = level
			front.tornado_requested.connect(func(wind: Vector2) -> void: _spawn_tornado(wind))
			add_child(front)
			front.begin(variant)
			_weather = front
			stats[String(front.kind())] += 1
			return true
		&"quake":
			if _quake != null:
				return false
			var quake := Quake.new()
			quake.level = level
			_setup(quake)
			add_child(quake)
			if quake.begin():
				_quake = quake
				stats["quake"] += 1
				return true
			quake.queue_free()
		&"tornado":
			var front := _weather as WeatherFront
			return _spawn_tornado(front.wind if front != null else Vector2.ZERO)
		&"whirlpool":
			# Отладка (--event=whirlpool): вплотную к машине, чтобы сразу потянуло; у берега глубокой воды рядом
			# может не быть — тогда где-нибудь в кольце до игровой дальности.
			if not _spawn_whirlpool(2.0, 4.0) and not _spawn_whirlpool(4.0, Whirlpool.SPAWN_MAX):
				print("threats: no deep water for a whirlpool near the vehicle")
				return false
			return true
		&"strike":
			# Отладка: удар молнии прямо в машину (гроза начинается, если её нет).
			if _weather != null and not _weather is StormFront:
				return false
			if _weather == null:
				_start(&"storm")
			(_weather as StormFront).strike_vehicle()
			return true
	return false


## Водоворот по курсу машины в r_min…r_max тайлах на глубокой воде 2×2 (в игре — за кадром). Один за раз.
func _spawn_whirlpool(r_min: float, r_max: float) -> bool:
	if _whirlpool != null:
		return false
	var at := Whirlpool.find_spot(query, vehicle.state.pos, vehicle.state.vel, r_min, r_max, _rng)
	if at == Vector2.INF:
		return false
	var w := Whirlpool.new()
	_setup(w)
	add_child(w)
	w.begin(at)
	_whirlpool = w
	stats["whirlpool"] += 1
	return true


## Машина над глубокой водой (2+ яруса) — водоворот имеет смысл только там.
func _over_deep_water() -> bool:
	return Whirlpool.deep(query, vehicle.state.tile)


## Смерч: с наветренной стороны из-за края экрана, в буре его сносит ветром. Один за раз.
func _spawn_tornado(wind: Vector2) -> bool:
	if _tornado != null:
		return false
	var t := Tornado.new()
	_setup(t)
	t.drift = wind
	add_child(t)
	var from := (-wind).rotated(_rng.randf_range(-0.8, 0.8)) if wind != Vector2.ZERO \
			else Vector2.from_angle(_rng.randf() * TAU)
	t.begin(vehicle.state.pos + from * rules.tornado_spawn_dist)
	_tornado = t
	stats["tornado"] += 1
	return true


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
