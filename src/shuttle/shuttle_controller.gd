class_name ShuttleController
extends Node
## Челноки на сцене (GDD §2.3): расписание основного, площадка и меню, аварийный вызов по радио.
## Логика — в ShuttleScheduler и EmergencyCall, здесь — связь с машиной, RunState, визуалом и HUD.
## Челноки садятся на землю: до касания на месте посадки горит предупреждающий знак, кто окажется под
## корпусом в момент касания — раздавлен (crushed); стоящий корпус — препятствие для машины.
## Основной улетает сразу после сдачи груза, иначе — по концу окна. Аварийный вызывается через меню
## (что привезти: топливо или запчасти); с воды вызвать нельзя — ему негде сесть рядом.
## GameFlow вызывает step() в своём физическом кадре.

signal evacuate_requested          ## выбрано «Вернуться на орбиту»
signal refueled                    ## аварийный челнок привёз топливо
signal crushed                     ## челнок сел на машину

const LIFT_S := 1.0                ## эвакуация: луч втягивает машину в челнок
const RETRY_S := 0.25              ## аварийному некуда сесть — снова ищем место через столько
const WATER_DEPTH := 0.05          ## ярусов воды под машиной (или под подушкой ховера) — «на воде»
const COLOR_GOOD := Color(0.46, 0.9, 0.4)
const COLOR_WARN := Color(1.0, 0.6, 0.25)

var vehicle: Vehicle
var query: TerrainQuery
var generator: TerrainGenerator
var rules: BalanceRules
var hud: Hud
var run: RunState
var active := false                ## забег идёт: радио и меню работают
var menu_enabled := true           ## автопилот в меню не заходит

var scheduler: ShuttleScheduler
var emergency: EmergencyCall
var _main_craft: ShuttleCraft
var _em_craft: ShuttleCraft
var _menu: ShuttleMenu
var _call_menu: EmergencyMenu
var _menu_armed := true            ## меню откроется снова, только если машина тронулась или выехала
var _main_descending := false
var _em_tile := EmergencyCall.NO_TILE
var _retry_t := 0.0


func _ready() -> void:
	name = "ShuttleController"
	_main_craft = ShuttleCraft.new(ShuttleCraft.Kind.MAIN, rules.shuttle_zone_r)
	add_child(_main_craft)
	_em_craft = ShuttleCraft.new(ShuttleCraft.Kind.EMERGENCY)
	add_child(_em_craft)
	reset()


## Новое расписание (начало забега).
func reset() -> void:
	scheduler = ShuttleScheduler.new(rules, _find_pad)
	scheduler.announced.connect(_on_announced)
	scheduler.landed.connect(_on_landed)
	scheduler.departed.connect(_on_departed)
	emergency = EmergencyCall.new(rules)
	_main_craft.visible = false
	_em_craft.visible = false
	_main_descending = false
	_em_tile = EmergencyCall.NO_TILE
	if _menu != null:
		_close_menu()
	if _call_menu != null:
		_close_call_menu()


func _find_pad(pos: Vector2, distance: float) -> Vector3i:
	return ShuttleScheduler.find_pad(generator, pos, distance)


func step(dt: float) -> void:
	var pos := vehicle.state.pos
	scheduler.tick(dt, pos, _menu != null)
	if scheduler.state == ShuttleScheduler.State.WAITING and scheduler.has_pad() \
			and scheduler.time_left <= ShuttleCraft.FLY_S and not _main_descending:
		_main_descending = true
		_main_craft.descend(_pad_ground(), scheduler.time_left)
	_update_menu()
	_step_emergency(dt)
	vehicle.beacon_calling = emergency.state == EmergencyCall.State.INBOUND
	vehicle.state.obstacles = _obstacles()
	_broadcast()


## Машина в воде (вброд или ховер над водой): аварийному негде сесть рядом.
func in_water() -> bool:
	var p := vehicle.state.pos
	return query.water_depth(p.x, p.y) > WATER_DEPTH


func _unhandled_input(event: InputEvent) -> void:
	if active and menu_enabled and event.is_action_pressed(&"radio") and _menu == null and _call_menu == null:
		get_viewport().set_input_as_handled()
		_on_radio()


## F — меню вызова аварийного челнока (если он ещё не летит и машина не в воде).
func _on_radio() -> void:
	if emergency.is_busy():
		hud.popup("Аварийный челнок уже в пути", COLOR_WARN)
		return
	if in_water():
		hud.popup("Вызов челнока на воде не возможен", COLOR_WARN)
		return
	_call_menu = EmergencyMenu.new()
	_call_menu.supply = rules.emergency_supply
	_call_menu.step = rules.emergency_supply_step
	_call_menu.penalty = run.next_emergency_penalty()
	_call_menu.fuel = EmergencyCall.default_fuel(rules.emergency_supply, rules.emergency_supply_step,
			1.0 - run.fuel / vehicle.cls.fuel_max, 1.0 - float(run.hp) / vehicle.cls.hp_max)
	_call_menu.confirmed.connect(_on_call_confirmed)
	_call_menu.closed.connect(_close_call_menu)
	add_child(_call_menu)
	vehicle.control_enabled = false


func _on_call_confirmed(fuel: int, parts: int) -> void:
	_close_call_menu()
	if emergency.call_in(fuel, parts):
		_em_tile = EmergencyCall.NO_TILE
		_retry_t = 0.0
		hud.popup("Аварийный челнок вызван", COLOR_WARN)


func _close_call_menu() -> void:
	_call_menu.queue_free()
	_call_menu = null
	vehicle.control_enabled = active and _menu == null


## Аварийный: к началу спуска выбирается место посадки (дальше не меняется — под ним знак);
## нет места — челнок ждёт в небе и ищет снова. Касание — обмен, через STAY_S — взлёт.
func _step_emergency(dt: float) -> void:
	var can_land := true
	if emergency.state == EmergencyCall.State.INBOUND and emergency.time_left <= EmergencyCall.DESCEND_S:
		if _em_tile == EmergencyCall.NO_TILE:
			_retry_t -= dt
			if _retry_t <= 0.0:
				_retry_t = RETRY_S
				_em_tile = EmergencyCall.landing_tile(query, vehicle.state.pos, rules.emergency_land_min,
						rules.emergency_land_max)
				if _em_tile != EmergencyCall.NO_TILE:
					_em_craft.descend(_tile_ground(_em_tile), emergency.time_left)
		can_land = _em_tile != EmergencyCall.NO_TILE
	var was_landed := emergency.state == EmergencyCall.State.LANDED
	if emergency.tick(dt, can_land):
		_on_emergency_touchdown()
	if was_landed and emergency.state == EmergencyCall.State.IDLE:
		_em_craft.ascend()
		_em_tile = EmergencyCall.NO_TILE


## Касание аварийного: машина под корпусом раздавлена; иначе — обмен: груз за полцены минус штраф,
## заказанные топливо и запчасти.
func _on_emergency_touchdown() -> void:
	var at := _tile_ground(_em_tile)
	_em_craft.touch_down()
	_touchdown_hits(at, ShuttleCraft.EMERGENCY_HULL_R)
	if run.is_over():
		return
	var delta := run.emergency_ship(emergency.fuel_units, emergency.parts)
	EventBus.cargo_shipped.emit(delta, true)
	hud.banner("АВАРИЙНЫЙ ЧЕЛНОК  %+d" % delta, COLOR_WARN)
	if emergency.fuel_units > 0:
		hud.popup("+%d топлива" % emergency.fuel_units, Hud.COLOR_FUEL)
	if emergency.parts > 0:
		hud.popup("+%d HP  запчасти" % emergency.parts, Hud.COLOR_HP)
	refueled.emit()


## Касание земли корпусом радиуса hull_r в точке at: деревья под ним валятся, машина под ним
## раздавлена, тряска.
func _touchdown_hits(at: Vector3, hull_r: float) -> void:
	var c := Vector2(at.x, at.z)
	var t0 := Grid.tile_of_world(c.x, c.y)
	var reach := ceili(hull_r) + 1
	for dz in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := t0 + Vector2i(dx, dz)
			if query.has_standing_tree(t.x, t.y) \
					and query.tree_position(t.x, t.y).distance_to(c) < hull_r + VehicleKinematics.TREE_RADIUS:
				query.fell_tree(t.x, t.y)
	var d := vehicle.state.pos.distance_to(c)
	EventBus.camera_shake_requested.emit(clampf(1.0 - d / 12.0, 0.0, 1.0) * 0.8, 0.4)
	if d < hull_r + VehicleKinematics.RADIUS and not vehicle.state.drowning:
		crushed.emit()


## Корпуса севших челноков — препятствия для машины (x, z, радиус).
func _obstacles() -> Array[Vector3]:
	var out: Array[Vector3] = []
	if scheduler.state == ShuttleScheduler.State.LANDED:
		var c := scheduler.zone_center()
		out.append(Vector3(c.x, c.y, ShuttleCraft.MAIN_HULL_R))
	if emergency.state == EmergencyCall.State.LANDED and _em_tile != EmergencyCall.NO_TILE:
		out.append(Vector3(_em_tile.x + 0.5, _em_tile.y + 0.5, ShuttleCraft.EMERGENCY_HULL_R))
	return out


func _tile_ground(t: Vector2i) -> Vector3:
	return Vector3(t.x + 0.5, query.surface_y(t.x + 0.5, t.y + 0.5), t.y + 0.5)


func _pad_ground() -> Vector3:
	var pad := scheduler.pad
	return Vector3(pad.x + 0.5, Grid.tier_to_y(pad.z), pad.y + 0.5)


func _on_announced(_pad: Vector3i) -> void:
	_main_craft.show_marker(_pad_ground())
	hud.popup("Площадка челнока на радаре", ShuttleCraft.COLOR_RING)


func _on_landed(_pad: Vector3i) -> void:
	_main_craft.touch_down()
	_touchdown_hits(_pad_ground(), ShuttleCraft.MAIN_HULL_R)
	hud.popup("Челнок на площадке", ShuttleCraft.COLOR_RING)


func _on_departed() -> void:
	_main_craft.ascend()
	_main_descending = false
	if _menu != null:
		_close_menu()


## Меню открывается, когда машина остановилась в зоне севшего челнока, и закрывается, если её
## вынесло из зоны. После закрытия (Esc, A / D) снова откроется, только когда машина тронется.
func _update_menu() -> void:
	var s := vehicle.state
	var speed := s.vel.length()
	var in_zone := scheduler.state == ShuttleScheduler.State.LANDED and scheduler.in_zone(s.pos) \
			and not s.falling and not s.drowning
	if not in_zone or speed > rules.shuttle_stop_speed * 3.0:
		_menu_armed = true
	if _menu == null:
		if active and menu_enabled and in_zone and _menu_armed and speed < rules.shuttle_stop_speed \
				and _call_menu == null and not run.is_over():
			_open_menu()
		return
	if not in_zone:            # вынесло из зоны (толчок, смерч, подброс) — меню закрывается само
		_close_menu()
		return
	_menu.cargo_value = run.cargo_value()
	_menu.bonus = run.evacuation_bonus()
	_menu.window_left = scheduler.time_left


func _open_menu() -> void:
	_menu_armed = false
	_menu = ShuttleMenu.new()
	_menu.cargo_value = run.cargo_value()
	_menu.bonus = run.evacuation_bonus()
	_menu.window_left = scheduler.time_left
	_menu.ship_requested.connect(_on_ship)
	_menu.evacuate_requested.connect(_on_evacuate)
	_menu.closed.connect(_close_menu)
	add_child(_menu)
	vehicle.control_enabled = false


func _close_menu() -> void:
	_menu.queue_free()
	_menu = null
	vehicle.control_enabled = active and _call_menu == null


## Груз сдан — челнок сразу улетает.
func _on_ship() -> void:
	var value := run.ship_cargo()
	EventBus.cargo_shipped.emit(value, false)
	hud.banner("ГРУЗ СДАН  +%d" % value, COLOR_GOOD)
	_close_menu()
	scheduler.depart()


func _on_evacuate() -> void:
	_close_menu()
	vehicle.control_enabled = false
	vehicle.lift(_pad_ground() + Vector3(0, ShuttleCraft.HATCH_Y, 0), LIFT_S)
	_main_craft.tractor(vehicle, LIFT_S)
	get_tree().create_timer(LIFT_S + 0.2).timeout.connect(_evac_takeoff)
	evacuate_requested.emit()


func _evac_takeoff() -> void:
	_main_craft.ascend()
	EventBus.camera_shake_requested.emit(0.6, 1.0)


## Состояние челноков для HUD и радара. Аварийный: inbound — летит, no_place — ждёт в небе места,
## landed — сел; без вызова: menu — открыто меню вызова, water — машина в воде (вызвать нельзя), idle.
func _broadcast() -> void:
	var pad := _pad_ground() if scheduler.has_pad() else Vector3.INF
	var state := &"waiting"
	if scheduler.state == ShuttleScheduler.State.LANDED:
		state = &"landed"
	elif scheduler.has_pad():
		state = &"announced"
	EventBus.shuttle_state_changed.emit(state, scheduler.time_left, pad)
	var penalty := run.next_emergency_penalty()
	var em := &"idle"
	match emergency.state:
		EmergencyCall.State.INBOUND:
			var waiting := emergency.time_left <= EmergencyCall.DESCEND_S and _em_tile == EmergencyCall.NO_TILE
			em = &"no_place" if waiting else &"inbound"
		EmergencyCall.State.LANDED:
			em = &"landed"
		_:
			if _call_menu != null:
				em = &"menu"
			elif in_water():
				em = &"water"
	EventBus.emergency_state_changed.emit(em, emergency.time_left if em == &"inbound" else 0.0, penalty)
