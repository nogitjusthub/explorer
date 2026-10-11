class_name EmergencyCall
extends RefCounted
## Аварийный (малый) челнок (GDD §2.3) — чистая логика. Вызов — с заказом: сколько привезти топлива и
## сколько запчастей (всего emergency_supply единиц). Прилетает через emergency_delay_s; место посадки
## выбирается к началу спуска (DESCEND_S до касания) — сухой ровный тайл в emergency_land_min…max от
## машины, чтобы корпус её не накрыл. Нет такого — челнок ждёт в небе, пока место не найдётся.
## Обмен — сразу после посадки, через STAY_S взлетает. Одновременно летит не больше одного.

enum State { IDLE, INBOUND, LANDED }

const STAY_S := 1.5                ## стоит после обмена, затем взлетает
const DESCEND_S := 3.0             ## спуск: к его началу выбрано место посадки
const NO_TILE := Vector2i(-999999, -999999)

var rules: BalanceRules
var state := State.IDLE
var time_left := 0.0
var fuel_units := 0                ## заказ: топливо…
var parts := 0                     ## …и запчасти (1 ед. — 1 HP)


func _init(balance: BalanceRules) -> void:
	rules = balance


func is_busy() -> bool:
	return state != State.IDLE


## Вызов с заказом. false — аварийный уже в пути или на земле.
func call_in(fuel: int, repair: int) -> bool:
	if state != State.IDLE:
		return false
	state = State.INBOUND
	time_left = rules.emergency_delay_s
	fuel_units = fuel
	parts = repair
	return true


## Шаг. can_land — место посадки есть: иначе отсчёт стоит на начале спуска (челнок ждёт в небе).
## Возвращает true в момент посадки — пора делать обмен.
func tick(dt: float, can_land: bool = true) -> bool:
	match state:
		State.INBOUND:
			time_left -= dt
			if not can_land:
				time_left = maxf(time_left, DESCEND_S)
			elif time_left <= 0.0:
				state = State.LANDED
				time_left = STAY_S
				return true
		State.LANDED:
			time_left -= dt
			if time_left <= 0.0:
				state = State.IDLE
	return false


## Заказ по умолчанию: supply единиц поровну нужде — чего меньше в баке и броне (в долях), того больше;
## округлено до шага ползунка.
static func default_fuel(supply: int, step: int, fuel_missing: float, hp_missing: float) -> int:
	var need := fuel_missing + hp_missing
	var share := 0.5 if need <= 0.0 else fuel_missing / need
	return clampi(roundi(supply * share / step) * step, 0, supply)


## Тайл посадки: ровный (все углы на одной высоте) сухой тайл без стенок, центр которого в
## land_min…land_max от машины; из таких — ближайший. NO_TILE — сесть некуда.
static func landing_tile(q: TerrainQuery, pos: Vector2, land_min: float, land_max: float) -> Vector2i:
	var own := Grid.tile_of_world(pos.x, pos.y)
	var reach := ceili(land_max)
	var best := NO_TILE
	var best_d := INF
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := own + Vector2i(dx, dz)
			var d := pos.distance_to(Vector2(t.x + 0.5, t.y + 0.5))
			if d < land_min or d > land_max or d >= best_d or not can_land(q, t):
				continue
			best = t
			best_d = d
	return best


static func can_land(q: TerrainQuery, t: Vector2i) -> bool:
	if not q.is_loaded(t.x, t.y) or q.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
		return false
	for c in range(1, 4):
		if q.corner(t.x, t.y, c) != q.corner(t.x, t.y, 0):
			return false
	for dir in 4:
		if q.edge_rise(t.x, t.y, dir) != 0 or q.edge_drop(t.x, t.y, dir) != 0:
			return false
	return true
