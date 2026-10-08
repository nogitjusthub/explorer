class_name EmergencyCall
extends RefCounted
## Аварийный (малый) челнок (GDD §2.3) — чистая логика. Прилетает через 10 с после вызова, садится
## на ближайший к машине сухой тайл без стенок в радиусе 3 (если такого нет — зависает над машиной),
## обмен — сразу после посадки, затем взлетает. Одновременно летит не больше одного.

enum State { IDLE, INBOUND, LANDED }

const LAND_RADIUS := 3
const STAY_S := 1.5                ## стоит после обмена, затем взлетает
const NO_TILE := Vector2i(-999999, -999999)

var rules: BalanceRules
var state := State.IDLE
var time_left := 0.0


func _init(balance: BalanceRules) -> void:
	rules = balance


func is_busy() -> bool:
	return state != State.IDLE


## Вызов. false — аварийный уже в пути или на земле.
func call_in() -> bool:
	if state != State.IDLE:
		return false
	state = State.INBOUND
	time_left = rules.emergency_delay_s
	return true


## Шаг. Возвращает true в момент посадки — пора делать обмен.
func tick(dt: float) -> bool:
	match state:
		State.INBOUND:
			time_left -= dt
			if time_left <= 0.0:
				state = State.LANDED
				time_left = STAY_S
				return true
		State.LANDED:
			time_left -= dt
			if time_left <= 0.0:
				state = State.IDLE
	return false


## Тайл посадки: ближайший к машине сухой тайл без стенок по всем четырём рёбрам в радиусе 3,
## кроме тайла под машиной. NO_TILE — сесть некуда (челнок зависает над машиной).
static func landing_tile(q: TerrainQuery, pos: Vector2) -> Vector2i:
	var own := Grid.tile_of_world(pos.x, pos.y)
	var best := NO_TILE
	var best_d := INF
	for dz in range(-LAND_RADIUS, LAND_RADIUS + 1):
		for dx in range(-LAND_RADIUS, LAND_RADIUS + 1):
			var t := own + Vector2i(dx, dz)
			if t == own:
				continue
			var d := pos.distance_to(Vector2(t.x + 0.5, t.y + 0.5))
			if d > LAND_RADIUS + 0.5 or d >= best_d or not _can_land(q, t):
				continue
			best = t
			best_d = d
	return best


static func _can_land(q: TerrainQuery, t: Vector2i) -> bool:
	if not q.is_loaded(t.x, t.y) or q.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
		return false
	for dir in 4:
		if q.edge_rise(t.x, t.y, dir) != 0 or q.edge_drop(t.x, t.y, dir) != 0:
			return false
	return true
