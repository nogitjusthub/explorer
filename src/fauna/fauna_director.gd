class_name FaunaDirector
extends Node3D
## Фауна забега (GDD §5.4, §5.6, §7.1). Существа появляются в кольце fauna_spawn_min…max вокруг машины —
## сколько и кто, решает уровень угрозы (T1 — скакуны, T2 — + черви на песке, илозубы в зыбуне и воде у него,
## Несса в больших озёрах, T3 — + панцирники), и исчезают дальше fauna_despawn, если не гонятся.
## Троеглазки лежат в мелкой воде по чанкам и уходят вместе с чанком. Существа слышат шум машины и
## посадок (NoiseField). Поля путей видов (FlowField) строятся
## задачами JobScheduler вокруг машины, пока кто-то гонится. Урон машине — сигналом damaged.
## Таран (_ram): машина на скорости валки деревьев въехала в зверя — удар по нему (Creature.ram); машина
## теряет скорость, как после валки дерева, корпус раскачивается, ховер платит tree_fell_damage, как за дерево.
## Убитый тараном зверь мигает, пропадает облачком и уходит из списка (finished).

signal damaged(amount: int, source: StringName)

const FIELD_EVERY_S := 0.8
const SPAWN_EVERY_S := 2.0
const SPAWN_TRIES := 10
const FORCED_DIST := 14.0
const SHARK_SPAWN_TRIES := 40             ## пятна зыбуна маленькие — проб больше (проба дешёвая)

var rules: BalanceRules
var vehicle: Vehicle
var query: TerrainQuery
var terrain: TerrainData
var generator: TerrainGenerator
var scheduler: JobScheduler
var run_seed: int
var enabled := true
var level := 1
var forced: Array[Dictionary] = []        ## отладка: [{kind, at}] — hoppers, worm, shellback, shark, ray, nessie
var noise := NoiseField.new()
## hits — атаки существ по машине (укусы, тараны панцирника, разряды, удары Нессы); rams — удары тараном
## машины по зверям (урон ховеру за таран — tree_fell_damage — в hits не входит, его счёт — rams), kills —
## убитые тараном.
var stats := {"packs": 0, "worms": 0, "shellbacks": 0, "sharks": 0, "rays": 0, "nessies": 0, "hits": 0,
		"rams": 0, "kills": 0}

var _rng: RandomNumberGenerator
var _creatures: Array[Creature] = []
var _rays: Dictionary[Vector2i, Array] = {}   ## чанк → его троеглазки
var _fields: Dictionary = {}              ## FlowField.Mode → готовое поле
var _field_busy: Dictionary = {}          ## FlowField.Mode → идёт построение
var _field_timer: Dictionary = {}
var _spawn_timer := 1.0
var _worm_wait := -1.0                    ## до следующего червя, с; < 0 — ещё не задано (begin)
var _nessie_wait := -1.0                  ## до следующей Нессы, с
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


## Испуг (удар капсулы десанта): стаи рядом уходят, панцирники успокаиваются.
func scare(at: Vector2, radius: float) -> void:
	for c in _creatures:
		if c.dead or c.pos.distance_to(at) > radius:
			continue
		if c is HopperPack:
			(c as HopperPack).flee()
		elif c is Shellback:
			(c as Shellback).calm_down()
		elif c is MireShark:
			(c as MireShark).scare()


func on_chunk_built(coord: Vector2i) -> void:
	_place_rays(coord)


func on_chunk_removed(coord: Vector2i) -> void:
	for c: Creature in _rays.get(coord, []):
		_creatures.erase(c)
		c.queue_free()
	_rays.erase(coord)


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
	if _worm_wait < 0.0:
		_worm_wait = rules.worm_first_s
	_worm_wait = maxf(_worm_wait - dt, 0.0)
	if _nessie_wait < 0.0:
		_nessie_wait = rules.nessie_first_s
	_nessie_wait = maxf(_nessie_wait - dt, 0.0)
	_spawn_timer -= dt
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_EVERY_S
		_spawn()
	for c in _creatures:
		c.step(dt)
	_ram()
	for i in range(_creatures.size() - 1, -1, -1):
		var c := _creatures[i]
		if c is Stargazer:
			continue                      # троеглазки уходят вместе с чанком
		if c.finished or (not c.aggressive and c.pos.distance_to(s.pos) > rules.fauna_despawn):
			if c is Worm and (c as Worm).met:
				_worm_wait = rules.worm_gap_s
			if c is LakeMonster and (c as LakeMonster).met:
				_nessie_wait = rules.nessie_gap_s
			c.queue_free()
			_creatures.remove_at(i)


## Таран (GDD §5.4): машина въехала в зверя не медленнее порога валки деревьев своего класса — удар по
## каждому телу, которого коснулась впервые (один контакт — один удар). Машина теряет скорость, как после
## валки дерева (раз за кадр, сколько бы тел ни задела), корпус раскачивается, ховер платит HP, как за дерево.
## Падающая, подброшенная, тонущая или разбитая машина не таранит (касания при этом запоминаются).
func _ram() -> void:
	var s := vehicle.state
	var able := not (s.falling or s.launched or s.drowning or vehicle.wrecked)
	var fast := able and VehicleKinematics.fells(vehicle.cls, s.vel.length())
	var hits := 0
	for c in _creatures:
		var before := c.kills
		hits += c.ram(s.pos, s.y, s.vel, fast)
		stats["kills"] += c.kills - before
	if hits == 0:
		return
	stats["rams"] += hits
	VehicleKinematics.after_felling(s, vehicle.cls)
	vehicle.rock(Vehicle.ROCK_TREE, -s.forward())
	EventBus.camera_shake_requested.emit(0.3, 0.15)
	if vehicle.cls.tree_fell_damage > 0:
		damaged.emit(vehicle.cls.tree_fell_damage, &"ram")     # мимо _on_creature_hit: не атака зверя (stats — rams)


## Отладка (--hunt): ближайшее к from живое тело под тараном (центр) не дальше reach, или null.
func nearest_prey(from: Vector2, reach: float = 30.0) -> Variant:
	var best: Variant = null
	var best_d := reach
	for c in _creatures:
		for b in c.bodies:
			var d := b.pos.distance_to(from)
			if b.alive() and d < best_d:
				best = b.pos
				best_d = d
	return best


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
		# Строится под бюджет кадра по часам: готово через разное число кадров. Тайминг фауны в детерминизм
		# сида не входит — сид задаёт мир, а не ходы зверей.
		var job := FlowField.build(query, mode, vehicle.state.tile, _on_field_ready)
		scheduler.enqueue(job, -0.5)


func _on_field_ready(f: FlowField) -> void:
	_fields[f.mode] = f
	_field_busy[f.mode] = false


## Сколько кого держать вокруг машины при текущем уровне угрозы.
func _wanted(kind: StringName) -> int:
	match kind:
		&"packs":
			return 1 + (1 if level >= 2 else 0) + (1 if level >= 4 else 0)
		&"worms":
			return 1 if level >= rules.worm_min_level else 0
		&"shellbacks":
			return (1 + (1 if level >= 5 else 0)) if level >= rules.shellback_min_level else 0
		&"sharks":
			return (1 + (1 if level >= 4 else 0)) if level >= rules.shark_min_level else 0
		&"nessies":
			return 1 if level >= rules.nessie_min_level else 0
	return 0


func _spawn() -> void:
	var counts := {"packs": 0, "worms": 0, "shellbacks": 0, "sharks": 0, "nessies": 0}
	for c in _creatures:
		if c is HopperPack:
			counts["packs"] += 1
		elif c is Worm:
			counts["worms"] += 1
		elif c is Shellback:
			counts["shellbacks"] += 1
		elif c is MireShark:
			counts["sharks"] += 1
		elif c is LakeMonster:
			counts["nessies"] += 1
	if counts["packs"] < _wanted(&"packs"):
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t))
		if at != null:
			_spawn_pack(at, _rng.randi_range(rules.pack_min, rules.pack_max))
	# Червь — когда машина на его грунте (песок или грунт): рядом, за кадром, в песке.
	var on_habitat := Worm.habitat(query, Grid.tile_of_world(vehicle.state.pos.x, vehicle.state.pos.y))
	if counts["worms"] < _wanted(&"worms") and on_habitat and _worm_wait <= 0.0 and _rng.randf() < rules.worm_chance:
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return Worm.spawn_ground(query, t),
				rules.worm_spawn_min, rules.worm_spawn_max)
		if at != null:
			_spawn_worm(at)
	if counts["shellbacks"] < _wanted(&"shellbacks"):
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t))
		if at != null:
			_spawn_shellback(at)
	# Илозуб — в зыбуне или в воде у зыбуна, ближе остальных: ему не уйти со своего ареала.
	if counts["sharks"] < _wanted(&"sharks"):
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _shark_ground(t),
				rules.shark_spawn_min, rules.shark_spawn_max, SHARK_SPAWN_TRIES)
		if at != null:
			_spawn_shark(at)
	# Несса — редкая: когда машина у большого озера, в его глубокой воде.
	if counts["nessies"] < _wanted(&"nessies") and _nessie_wait <= 0.0 and _near_big_lake() \
			and _rng.randf() < rules.nessie_chance:
		var at: Variant = _ring_point(func(t: Vector2i) -> bool: return LakeMonster.habitat(query, t) \
				and LakeMonster.big_lake(query, t, rules.nessie_lake_tiles), 10.0, 18.0)
		if at != null:
			_spawn_nessie(at)


## Машина в воде или на берегу (до 3 тайлов) большого озера.
func _near_big_lake() -> bool:
	var c := vehicle.state.tile
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var t := c + Vector2i(dx, dz)
			if LakeMonster.habitat(query, t):
				return LakeMonster.big_lake(query, t, rules.nessie_lake_tiles)
	return false


## Троеглазки чанка: на тайлах мелкой воды с шансом ray_chance по хэшу тайла, не больше ray_per_chunk.
func _place_rays(coord: Vector2i) -> void:
	if _rays.has(coord):
		return
	var d: ChunkData = terrain.chunks.get(coord)
	if d == null:
		return
	var placed: Array = []
	var o := Grid.chunk_origin(coord)
	for tz in range(o.y, o.y + Grid.CHUNK):
		for tx in range(o.x, o.x + Grid.CHUNK):
			if d.water_level[d.local_index(tx, tz)] == 0:
				continue
			if DetRng.unit(run_seed, tx, tz, 961) >= rules.ray_chance or not Stargazer.habitat(query, Vector2i(tx, tz)):
				continue
			placed.append(_spawn_ray(Vector2(tx + 0.5, tz + 0.5)))
			if placed.size() >= rules.ray_per_chunk:
				break
		if placed.size() >= rules.ray_per_chunk:
			break
	_rays[coord] = placed


## Точка в кольце вокруг машины на загруженном тайле, годном для вида, или null.
func _ring_point(ok: Callable, r_min: float = -1.0, r_max: float = -1.0, tries: int = SPAWN_TRIES) -> Variant:
	var lo := rules.fauna_spawn_min if r_min < 0.0 else r_min
	var hi := rules.fauna_spawn_max if r_max < 0.0 else r_max
	for _i in tries:
		var p := vehicle.state.pos + Vector2.from_angle(_rng.randf() * TAU) * _rng.randf_range(lo, hi)
		var t := Grid.tile_of_world(p.x, p.y)
		if query.is_loaded(t.x, t.y) and ok.call(t):
			return Vector2(t.x + 0.5, t.y + 0.5)
	return null


## Ареал илозуба: зыбун или вода не дальше shark_home_r от него.
func _shark_ground(t: Vector2i) -> bool:
	return MireShark.habitat(query, t, rules.shark_home_r)


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


func _spawn_shark(at: Vector2) -> MireShark:
	var sh := MireShark.new()
	_adopt(sh)
	sh.setup(at)
	stats["sharks"] += 1
	return sh


func _spawn_nessie(at: Vector2) -> LakeMonster:
	var n := LakeMonster.new()
	_adopt(n)
	n.setup(at)
	stats["nessies"] += 1
	return n


## Троеглазка лежит до выгрузки чанка; свой генератор — по тайлу (решения детерминированы).
func _spawn_ray(at: Vector2) -> Stargazer:
	var r := Stargazer.new()
	_adopt(r)
	r.rng = DetRng.rng_for(run_seed, floori(at.x), floori(at.y), 962)
	r.setup(at)
	stats["rays"] += 1
	return r


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
		if at != null and _rng.randf() < rules.shuttle_pack_chance:
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
			var at: Variant = _scan_point(func(t: Vector2i) -> bool: return Worm.spawn_ground(query, t), 3.0, 25.0)
			if at != null:
				_spawn_worm(at).start_hunt()
			else:
				print("fauna: no sand for a worm near the vehicle")
		&"shellback":
			var at: Variant = _ring_point(func(t: Vector2i) -> bool: return _dry(t), 10.0, 12.0)
			if at != null:
				var sb := _spawn_shellback(at)
				sb.state = Shellback.State.APPROACH
				sb.aggressive = true
		&"shark":
			var at: Variant = _scan_point(func(t: Vector2i) -> bool: return _shark_ground(t), 3.0, 15.0)
			if at != null:
				_spawn_shark(at).start_hunt()
			else:
				print("fauna: no quicksand (or water next to it) near the vehicle")
		&"ray":
			var at: Variant = _scan_point(func(t: Vector2i) -> bool: return Stargazer.habitat(query, t), 2.0, 8.0)
			if at != null:
				var t := Grid.tile_of_world(at.x, at.y)
				var coord := Grid.chunk_of_tile(t.x, t.y)
				var list: Array = _rays.get(coord, [])
				list.append(_spawn_ray(at))
				_rays[coord] = list
			else:
				print("fauna: no shallow water near the vehicle")
		&"nessie":
			var at: Variant = _scan_point(func(t: Vector2i) -> bool: return LakeMonster.habitat(query, t), 6.0, 18.0)
			if at != null:
				_spawn_nessie(at).start_hunt()
			else:
				print("fauna: no deep water near the vehicle")


## Отладка: ближайший к r_min тайл вокруг машины в кольце r_min…r_max, годный для вида (полный перебор,
## не жребий — водные виды живут на редких тайлах), или null.
func _scan_point(ok: Callable, r_min: float, r_max: float) -> Variant:
	var c := vehicle.state.pos
	var reach := ceili(r_max)
	var best: Variant = null
	var best_d := INF
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := Grid.tile_of_world(c.x, c.y) + Vector2i(dx, dz)
			var p := Vector2(t.x + 0.5, t.y + 0.5)
			var d := p.distance_to(c)
			if d < r_min or d > r_max or d >= best_d or not query.is_loaded(t.x, t.y) or not ok.call(t):
				continue
			best = p
			best_d = d
	return best
