class_name Autopilot
extends RefCounted
## Автопилот для бенчмарка и снимков: едет на полном газу и раз в 0,4 с выбирает из 16
## направлений то, где дальше всего свободно (без стенок вверх, деревьев и глубокой воды),
## предпочитая текущий курс. Нужен, чтобы бенчмарк стриминга реально объезжал мир.

const PROBE_LEN := 10.0
const PROBE_STEP := 0.5
const REPLAN_S := 0.4
const DIRECTIONS := 16

var query: TerrainQuery
var cls: VehicleClass
var fixed_course := false        ## ехать строго по курсу, без объезда (отладка воды, обрывов)
var _course := 0.0
var _timer := 0.0
var _drift := 0.0


func _init(start_course: float, terrain_query: TerrainQuery, vehicle_class: VehicleClass) -> void:
	_course = start_course
	query = terrain_query
	cls = vehicle_class


func direction(state: VehicleState, dt: float) -> Vector2:
	_timer -= dt
	_drift += dt
	if fixed_course:
		return Vector2.from_angle(_course)
	if _timer <= 0.0:
		_timer = REPLAN_S
		_replan(state)
	return Vector2.from_angle(_course)


func _replan(state: VehicleState) -> void:
	var best := _course
	var best_score := -INF
	# Медленный дрейф предпочтения, чтобы маршрут не зацикливался.
	var preferred := _course + sin(_drift * 0.2) * 0.3
	for k in DIRECTIONS:
		var a := TAU * k / DIRECTIONS
		var free := _free_run(state.pos, Vector2.from_angle(a))
		var score := free + 3.0 * cos(wrapf(a - preferred, -PI, PI))
		if score > best_score:
			best_score = score
			best = a
	_course = best


## Сколько тайлов можно проехать по прямой без препятствий (до PROBE_LEN).
func _free_run(from: Vector2, dir: Vector2) -> float:
	var tile := Vector2i(floori(from.x), floori(from.y))
	var d := PROBE_STEP
	while d <= PROBE_LEN:
		var p := from + dir * d
		var t := Vector2i(floori(p.x), floori(p.y))
		if t != tile:
			if not _passable(tile, t):
				return d
			tile = t
		if query.has_standing_tree(t.x, t.y) and p.distance_to(query.tree_position(t.x, t.y)) < 0.7:
			return d
		d += PROBE_STEP
	return PROBE_LEN


func _passable(a: Vector2i, b: Vector2i) -> bool:
	var step := b - a
	# Диагональный шаг проверяем через оба промежуточных тайла.
	if step.x != 0 and step.y != 0:
		var via_x := a + Vector2i(step.x, 0)
		var via_z := a + Vector2i(0, step.y)
		return (_edge_ok(a, via_x) and _edge_ok(via_x, b)) or (_edge_ok(a, via_z) and _edge_ok(via_z, b))
	return _edge_ok(a, b)


func _edge_ok(a: Vector2i, b: Vector2i) -> bool:
	var dir := Grid.DIR_OFFSETS.find(b - a)
	if dir < 0 or query.edge_rise(a.x, a.y, dir) > 0:
		return false
	if query.edge_drop(a.x, a.y, dir) >= 3:
		return false   # не прыгаем с высоких обрывов
	if cls.max_water_depth >= 0:
		var w := query.water_tier(b.x, b.y)
		if w != TerrainQuery.NO_WATER and w - query.surface_tier(b.x + 0.5, b.y + 0.5) > cls.max_water_depth:
			return false
	return true
