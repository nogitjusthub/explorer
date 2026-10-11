class_name ShuttleScheduler
extends RefCounted
## Расписание основного челнока (GDD §2.3) — чистая логика без сцены.
## Посадка k (k = 0, 1, 2 …) — через min(90 + 30k, 180) с после прошлого вылета (первая — от начала
## забега). За 30 с до посадки выбирается площадка: ближайшая к дистанции min(25 + 15k, 70) тайлов
## от машины. Окно на площадке — 20 с; пока машина в меню (hold), окно не идёт.

signal announced(pad: Vector3i)
signal landed(pad: Vector3i)
signal departed()

enum State { WAITING, LANDED }

const NO_PAD := Vector3i(0, 0, TerrainGenerator.NO_PAD)

var rules: BalanceRules
var pad_finder: Callable           ## (pos: Vector2, distance: float) -> Vector3i (или NO_PAD)
var state := State.WAITING
var k := 0                         ## номер посадки за забег
var time_left := 0.0               ## до посадки (WAITING) или до конца окна (LANDED)
var pad := NO_PAD                  ## (центр x, центр z, ярус) после анонса


func _init(balance: BalanceRules, finder: Callable) -> void:
	rules = balance
	pad_finder = finder
	time_left = interval(0)


func interval(n: int) -> float:
	return minf(rules.shuttle_interval_base + rules.shuttle_interval_step * n, rules.shuttle_interval_max)


func distance(n: int) -> float:
	return minf(rules.shuttle_dist_base + rules.shuttle_dist_step * n, rules.shuttle_dist_max)


func has_pad() -> bool:
	return pad.z != TerrainGenerator.NO_PAD


## Центр зоны посадки (x, z).
func zone_center() -> Vector2:
	return Vector2(pad.x + 0.5, pad.y + 0.5)


func in_zone(pos: Vector2) -> bool:
	return has_pad() and pos.distance_to(zone_center()) <= rules.shuttle_zone_r


## Шаг расписания. hold — машина в меню челнока: окно на площадке не убывает.
func tick(dt: float, vehicle_pos: Vector2, hold: bool) -> void:
	if state == State.WAITING:
		time_left -= dt
		if not has_pad() and time_left <= rules.shuttle_announce_s:
			pad = pad_finder.call(vehicle_pos, distance(k))
			if has_pad():
				announced.emit(pad)
		if time_left <= 0.0:
			if has_pad():
				state = State.LANDED
				time_left = rules.shuttle_window_s
				landed.emit(pad)
			else:
				_next()      # площадки не нашлось — посадка пропускается
	else:
		if not hold:
			time_left -= dt
		if time_left <= 0.0:
			_next()
			departed.emit()


## Улететь сейчас, не дожидаясь конца окна (груз сдан).
func depart() -> void:
	if state != State.LANDED:
		return
	_next()
	departed.emit()


func _next() -> void:
	k += 1
	state = State.WAITING
	time_left = interval(k)
	pad = NO_PAD


## Площадка, дистанция до которой ближе всего к target (при равенстве — ближняя к машине).
## Площадки — по одной на блок генератора (TerrainParams.pad_block), ищем в квадрате блоков вокруг.
static func find_pad(gen: TerrainGenerator, pos: Vector2, target: float) -> Vector3i:
	var block_size := float(gen.p.pad_block)
	var reach := ceili((target + block_size) / block_size)
	var center := Vector2i(floori(pos.x / block_size), floori(pos.y / block_size))
	var best := NO_PAD
	var best_err := INF
	for bz in range(center.y - reach, center.y + reach + 1):
		for bx in range(center.x - reach, center.x + reach + 1):
			var pad := gen.pad_of_block(Vector2i(bx, bz))
			if pad.z == TerrainGenerator.NO_PAD:
				continue
			var d := pos.distance_to(Vector2(pad.x + 0.5, pad.y + 0.5))
			var err := absf(d - target) + d * 0.001
			if err < best_err:
				best_err = err
				best = pad
	return best
