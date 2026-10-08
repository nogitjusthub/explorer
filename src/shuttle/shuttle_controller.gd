class_name ShuttleController
extends Node
## Челноки на сцене (GDD §2.3): расписание основного, площадка и меню, аварийный вызов по радио,
## решение при пустом баке. Логика — в ShuttleScheduler и EmergencyCall, здесь — связь с машиной,
## RunState, визуалом и HUD. GameFlow вызывает step() в своём физическом кадре.

signal evacuate_requested          ## выбрано «Завершить забег»
signal refueled                    ## аварийный челнок привёз топливо
signal tank_expired                ## пустой бак: время на решение вышло

const CONFIRM_S := 3.0             ## второе нажатие F в течение этого времени подтверждает вызов
const RETARGET_S := 0.25
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
var _menu_armed := true            ## меню откроется снова, только если машина тронулась или выехала
var _main_descending := false
var _em_descending := false
var _em_target := Vector3.ZERO
var _em_tile := EmergencyCall.NO_TILE
var _retarget_t := 0.0
var _decision_left := -1.0
var _confirm_left := 0.0


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
	_em_descending = false
	_decision_left = -1.0
	_confirm_left = 0.0
	if _menu != null:
		_close_menu()


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
	if _decision_left >= 0.0 and _menu == null:
		_decision_left -= dt
		if _decision_left <= 0.0:
			_decision_left = -1.0
			tank_expired.emit()
	_confirm_left = maxf(_confirm_left - dt, 0.0)
	_broadcast()


## Пустой бак: если аварийный уже летит — ждём его, иначе 10 с на решение.
func on_fuel_empty() -> void:
	if emergency.state == EmergencyCall.State.INBOUND:
		hud.banner("ТОПЛИВО КОНЧИЛОСЬ", Hud.COLOR_FUEL_LOW)
		return
	_decision_left = rules.empty_tank_decision_s


## Топливо появилось (канистра): решение больше не нужно.
func on_refueled() -> void:
	_decision_left = -1.0


func _unhandled_input(event: InputEvent) -> void:
	if active and event.is_action_pressed(&"radio"):
		get_viewport().set_input_as_handled()
		_on_radio()


## F: при пустом баке — сразу вызов; иначе первое нажатие спрашивает подтверждение (штраф велик).
func _on_radio() -> void:
	if emergency.is_busy():
		hud.popup("Аварийный челнок уже в пути", COLOR_WARN)
		return
	if _decision_left >= 0.0 or _confirm_left > 0.0:
		emergency.call_in()
		_decision_left = -1.0
		_confirm_left = 0.0
		_em_descending = false
		hud.popup("Аварийный челнок вызван", COLOR_WARN)
	else:
		_confirm_left = CONFIRM_S


func _step_emergency(dt: float) -> void:
	if emergency.state == EmergencyCall.State.INBOUND and emergency.time_left <= ShuttleCraft.FLY_S:
		_retarget_t -= dt
		if _retarget_t <= 0.0 or not _em_descending:
			_retarget_t = RETARGET_S
			_em_target = _emergency_ground()
		if not _em_descending:
			_em_descending = true
			_em_craft.descend(_em_target, emergency.time_left)
		else:
			_em_craft.retarget(_em_target)
	var was_landed := emergency.state == EmergencyCall.State.LANDED
	if emergency.tick(dt):
		_exchange()
	if was_landed and emergency.state == EmergencyCall.State.IDLE:
		_em_craft.ascend()
		_em_descending = false


## Обмен с аварийным челноком: груз за полцены минус штраф, +30% бака.
func _exchange() -> void:
	_em_craft.position = _em_target
	_em_craft.touch_down()
	if _em_tile != EmergencyCall.NO_TILE and query.has_standing_tree(_em_tile.x, _em_tile.y):
		query.fell_tree(_em_tile.x, _em_tile.y)
	if run.is_over():
		return
	var delta := run.emergency_ship()
	EventBus.cargo_shipped.emit(delta, true)
	hud.banner("АВАРИЙНЫЙ ЧЕЛНОК  %+d" % delta, COLOR_WARN)
	hud.popup("+%d%% топлива" % roundi(rules.emergency_fuel_frac * 100.0), Hud.COLOR_FUEL)
	_decision_left = -1.0
	refueled.emit()


## Куда садится аварийный: тайл рядом с машиной или зависание над ней.
func _emergency_ground() -> Vector3:
	var s := vehicle.state
	_em_tile = EmergencyCall.landing_tile(query, s.pos)
	if _em_tile == EmergencyCall.NO_TILE:
		return Vector3(s.pos.x, s.y + 1.4, s.pos.y)
	return Vector3(_em_tile.x + 0.5, query.surface_y(_em_tile.x + 0.5, _em_tile.y + 0.5), _em_tile.y + 0.5)


func _pad_ground() -> Vector3:
	var pad := scheduler.pad
	return Vector3(pad.x + 0.5, Grid.tier_to_y(pad.z), pad.y + 0.5)


func _on_announced(_pad: Vector3i) -> void:
	_main_craft.show_marker(_pad_ground())
	hud.popup("Площадка челнока на радаре", ShuttleCraft.COLOR_RING)


func _on_landed(_pad: Vector3i) -> void:
	_main_craft.touch_down()
	hud.popup("Челнок на площадке", ShuttleCraft.COLOR_RING)


func _on_departed() -> void:
	_main_craft.ascend()
	_main_descending = false
	if _menu != null:
		_close_menu()


## Меню открывается, когда машина остановилась в зоне севшего челнока.
func _update_menu() -> void:
	var s := vehicle.state
	var speed := s.vel.length()
	var in_zone := scheduler.state == ShuttleScheduler.State.LANDED and scheduler.in_zone(s.pos) \
			and not s.falling and not s.drowning
	if not in_zone or speed > rules.shuttle_stop_speed * 3.0:
		_menu_armed = true
	if _menu == null:
		if active and menu_enabled and in_zone and _menu_armed and speed < rules.shuttle_stop_speed:
			_open_menu()
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
	vehicle.control_enabled = active


func _on_ship() -> void:
	var value := run.ship_cargo()
	EventBus.cargo_shipped.emit(value, false)
	hud.banner("ГРУЗ СДАН  +%d" % value, COLOR_GOOD)


func _on_evacuate() -> void:
	_close_menu()
	vehicle.control_enabled = false
	evacuate_requested.emit()


## Состояние челноков для HUD и радара.
func _broadcast() -> void:
	var pad := _pad_ground() if scheduler.has_pad() else Vector3.INF
	var state := &"waiting"
	if scheduler.state == ShuttleScheduler.State.LANDED:
		state = &"landed"
	elif scheduler.has_pad():
		state = &"announced"
	EventBus.shuttle_state_changed.emit(state, scheduler.time_left, pad)
	var penalty := run.next_emergency_penalty()
	if emergency.state == EmergencyCall.State.INBOUND:
		EventBus.emergency_state_changed.emit(&"inbound", emergency.time_left, penalty)
	elif emergency.state == EmergencyCall.State.LANDED:
		EventBus.emergency_state_changed.emit(&"landed", 0.0, penalty)
	elif _decision_left >= 0.0:
		EventBus.emergency_state_changed.emit(&"decide", _decision_left, penalty)
	elif _confirm_left > 0.0:
		EventBus.emergency_state_changed.emit(&"confirm", _confirm_left, penalty)
	else:
		EventBus.emergency_state_changed.emit(&"idle", 0.0, penalty)
