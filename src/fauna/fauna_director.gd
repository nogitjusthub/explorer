class_name FaunaDirector
extends Node3D
## Фауна забега (GDD §5.4, §7.1). Существа появляются в кольце fauna_spawn_min…max вокруг машины —
## сколько и кто, решает уровень угрозы (T1 — скакуны, T2 — + черви на песке, T3 — + панцирники),
## и исчезают дальше fauna_despawn, если не гонятся. Слышат шум машины и посадок (NoiseField);
## гнёзда (по чанкам) выпускают стаю, когда машина рядом. Поля путей видов (FlowField) строятся
## задачами JobScheduler вокруг машины, пока кто-то гонится. Урон машине — сигналом damaged.

signal damaged(amount: int, source: StringName)

const FIELD_EVERY_S := 0.8
const SPAWN_EVERY_S := 2.0
const SPAWN_TRIES := 10
const FORCED_DIST := 14.0

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var scheduler: JobScheduler
var run_seed: int
var enabled := true
var level := 1
var forced: Array[Dictionary] = []        ## отладка: [{kind, at}] — hoppers, worm, shellback
var noise := NoiseField.new()
var stats := {"packs": 0, "worms": 0, "shellbacks": 0, "hits": 0}

var _rng: RandomNumberGenerator
var _creatures: Array[Creature] = []
var _nests: Dictionary[Vector2i, Nest] = {}
var _fields: Dictionary = {}              ## FlowField.Mode → готовое поле
var _field_busy: Dictionary = {}          ## FlowField.Mode → идёт построение
var _field_timer: Dictionary = {}
var _spawn_timer := 1.0
var _time := 0.0
var _shuttle_state := &""
var _emergency_state := &""


func _ready() -> void:
	name = "FaunaDirector"
	noise.noise_range = rules.noise_range
	noise.full_frac = rules.noise_full_frac
	EventBus.shuttle_state_changed.connect(_on_shuttle)
	EventBus.emergency_state_changed.connect(_on_emergency)
	for coord: Vector2i in terrain.chunks:
		on_chunk_built(coord)


func begin() -> void:
	_rng = DetRng.rng_for(run_seed, 0, 0, 900)
	_time = 0.0


## Готовое поле путей вида (или null, пока не построено).
func field(mode: FlowField.Mode) -> FlowField:
	return _fields.get(mode)


func on_chunk_built(coord: Vector2i) -> void:
	var o := Grid.chunk_origin(coord)
	for t in generator.nests_in_rect(o.x, o.y, o.x + Grid.CHUNK - 1, o.y + Grid.CHUNK - 1):
		if _nests.has(t):
			continue
		var nest := Nest.new(t)
		add_child(nest)
		nest.build(query)
		_nests[t] = nest


func on_chunk_removed(coord: Vector2i) -> void:
	for t: Vector2i in _nests.keys():
		if Grid.chunk_of_tile(t.x, t.y) == coord:
			_nests[t].queue_free()
			_nests.erase(t)


func step(dt: float) -> void:
	if not enabled:
		return
	_time += dt
	var s := vehicle.state
	noise.update_vehicle(s.pos, s.vel.length(), vehicle.cls.max_speed)
	noise.tick(dt)
	for i in range(forced.size() - 1, -1, -1):
		if _time >= forced[i]["at"]:
			_force(forced[i]["kind"])
			forced.remove_at(i)
	_update_fields(dt)
	_check_nests(dt)
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_EVERY_S
		_spawn()
	for c in _creatures:
		c.step(dt)
	for i in range(_creatures.size() - 1, -1, -1):
		var c := _creatures[i]
		if c.finished or (not c.aggressive and c.pos.distance_to(s.pos) > rules.fauna_despawn):
			c.queue_free()
			_creatures.remove_at(i)


## Поля путей — только для видов, которые сейчас гонятся; центр — тайл машины.
func _update_fields(dt: float) -> void:
	for mode in [FlowField.Mode.HOPPER, FlowField.Mode.SHELLBACK]:
		var needed := false
		for c in _creatures:
			if c.aggressive and ((mode == FlowField.Mode.HOPPER and c is HopperPack) or (mode == FlowField.Mode.SHELLBACK and c is Shellback)):
				needed = true
				break
		if not needed:
			continue
		_field_timer[mode] = _field_timer.get(mode, 0.0) - dt
		if _field_timer[mode] > 0.0 or _field_busy.get(mode, false):
			continue
		_field_timer[mode] = FIELD_EVERY_S
		_field_busy[mode] = true
		var job := FlowField.build(query, mode, vehicle.state.tile, _on_field_ready)
		scheduler.enqueue(job, -0.5)


func _on_field_ready(f: FlowField) -> void:
	_fields[f.mode] = f
	_field_busy[f.mode] = false


func _check_nests(dt: float) -> void:
	var wake_r := rules.nest_wake_r + (4.0 if level >= 3 else 0.0)
	for nest: Nest in _nests.values():
		nest.cooldown = maxf(nest.cooldown - dt, 0.0)
		if nest.cooldown <= 0.0 and nest.center().distance_to(vehicle.state.pos) < wake_r:
			nest.cooldown = rules.nest_cooldown_s * (0.6 if level >= 3 else 1.0)
			var pack := _spawn_pack(nest.center(), rules.pack_max)
			pack.wake()


## Сколько кого держать вокруг машины при текущем уровне угрозы.
func _wanted(kind: StringName) -> int:
	match kind:
		&"packs":
			return 1 + (1 if level >= 2 else 0) + (1 if level >= 4 else 0)
		&"worms":
			return 2 if level >= rules.worm_min_level else 0
		&"shellbacks":
			return (1 + (1 if level >= 5 else 0)) if level >= rules.shellback_min_level else 0
	return 0


func _spawn() -> void:
	var counts := {"packs": 0, "worms": 0, "shellbacks": 0}
	for c in _creatures:
		if c is HopperPack:
			counts["packs"] += 1
		elif c is Worm:
			counts["worms"] += 1
		elif c is Shellback:
			counts["shellbacks"] += 1
	if counts["packs"] < _wanted(&"packs"):
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t))
		if at != null:
			_spawn_pack(at, _rng.randi_range(rules.pack_min, rules.pack_max))
	if counts["worms"] < _wanted(&"worms"):
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t) and query.material(t.x, t.y) == ChunkData.Mat.SAND)
		if at != null:
			_spawn_worm(at)
	if counts["shellbacks"] < _wanted(&"shellbacks"):
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t))
		if at != null:
			_spawn_shellback(at)


## Точка в кольце вокруг машины на загруженном тайле, годном для вида, или null.
func _ring_point(ok: Callable, r_min: float = -1.0, r_max: float = -1.0) -> Variant:
	var lo := rules.fauna_spawn_min if r_min < 0.0 else r_min
	var hi := rules.fauna_spawn_max if r_max < 0.0 else r_max
	for _i in SPAWN_TRIES:
		var p := vehicle.state.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(lo, hi)
		var t := Grid.tile_of_world(p.x, p.y)
		if query.is_loaded(t.x, t.y) and ok.call(t):
			return Vector2(t.x + 0.5, t.y + 0.5)
	return null


func _dry(t: Vector2i) -> bool:
	if query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
		return false
	var d := terrain.owner_of(t.x, t.y)
	return d != null and (d.flags[d.local_index(t.x, t.y)] & ChunkData.FLAG_PAD) == 0


func _spawn_pack(at: Vector2, count: int) -> HopperPack:
	var pack := HopperPack.new()
	_adopt(pack)
	pack.setup(at, count)
	stats["packs"] += 1
	return pack


func _spawn_worm(at: Vector2) -> Worm:
	var worm := Worm.new()
	_adopt(worm)
	worm.setup(at)
	stats["worms"] += 1
	return worm


func _spawn_shellback(at: Vector2) -> Shellback:
	var sb := Shellback.new()
	_adopt(sb)
	sb.setup(at)
	stats["shellbacks"] += 1
	return sb


func _adopt(c: Creature) -> void:
	c.rules = rules
	c.vehicle = vehicle
	c.query = query
	c.terrain = terrain
	c.noise = noise
	c.director = self
	c.rng = _rng
	c.damaged.connect(_on_creature_hit)
	add_child(c)
	_creatures.append(c)


func _on_creature_hit(amount: int, source: StringName) -> void:
	stats["hits"] += 1
	damaged.emit(amount, source)


## Посадка основного челнока шумит: фауна стягивается к площадке, к ней идёт стая.
func _on_shuttle(state: StringName, _seconds: float, pad: Vector3) -> void:
	if state == &"landed" and _shuttle_state != &"landed" and enabled:
		var p := Vector2(pad.x, pad.z)
		noise.add(p, rules.shuttle_noise_r, rules.shuttle_noise_s)
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t), 20.0, 30.0)
		if at != null:
			_spawn_pack(at, rules.pack_max).wake(p)
	_shuttle_state = state


func _on_emergency(state: StringName, _seconds: float, _penalty: int) -> void:
	if state == &"landed" and _emergency_state != &"landed" and enabled:
		noise.add(vehicle.state.pos, rules.emergency_noise_r, rules.emergency_noise_s)
	_emergency_state = state


## Отладка: существо рядом с машиной, сразу в атаке.
func _force(kind: StringName) -> void:
	match kind:
		&"hoppers":
			var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t), FORCED_DIST, FORCED_DIST + 3.0)
			if at != null:
				_spawn_pack(at, rules.pack_max).wake()
		&"worm":
			var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t) and query.material(t.x, t.y) == ChunkData.Mat.SAND, 3.0, 25.0)
			if at != null:
				_spawn_worm(at).start_hunt()
			else:
				print("fauna: no sand near the vehicle for a worm")
		&"shellback":
			var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t), 10.0, 12.0)
			if at != null:
				var sb := _spawn_shellback(at)
				sb.state = Shellback.State.APPROACH
				sb.aggressive = true
