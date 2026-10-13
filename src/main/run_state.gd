class_name RunState
extends RefCounted
## Состояние одного забега (GDD §2, §6, §7): HP, топливо, трюм, счёт, время. Чистая логика без сцены.
## Счёт = Σ сдач основному челноку + Σ аварийных сдач + бонус при эвакуации; не ниже нуля.
## При гибели трюм теряется. CAUSE_EMPTY_TANK — из прошлых версий (пустой бак больше не конец забега),
## остаётся ради старых записей таблицы рекордов.

signal hp_changed(hp: int, hp_max: int)
signal fuel_changed(fuel: float, fuel_max: float)
signal cargo_changed(slots_used: int, slots_max: int, value: int)
signal score_changed(score: int)
signal ended(cause: StringName)

const CAUSE_EVACUATED := &"evacuated"
const CAUSE_EMPTY_TANK := &"empty_tank"

## Предмет в трюме.
class CargoItem:
	extends RefCounted
	var kind: PickupKind

	func _init(k: PickupKind) -> void:
		kind = k


## Результат попытки положить находку в трюм.
class CargoOffer:
	extends RefCounted
	var accepted := false
	var displaced: Array[PickupKind] = []      ## вытеснено — выпадает на землю


var cls: VehicleClass
var rules: BalanceRules
var hp: int
var fuel: float
var cargo: Array[CargoItem] = []
var banked := 0                 ## Σ сдач (основной + аварийный челнок)
var shipments := 0
var emergency_calls := 0
var time := 0.0
var invulnerable := 0.0         ## секунд неуязвимости (после десанта)
var ended_cause: StringName = &""
var final_score := 0
var bonus := 0


func _init(vehicle_class: VehicleClass, balance: BalanceRules) -> void:
	cls = vehicle_class
	rules = balance
	hp = cls.hp_max
	fuel = cls.fuel_max
	invulnerable = rules.drop_invuln_s


## Разослать текущие значения всем подписчикам (HUD в начале забега).
func announce() -> void:
	hp_changed.emit(hp, cls.hp_max)
	fuel_changed.emit(fuel, cls.fuel_max)
	cargo_changed.emit(cargo_slots_used(), cls.cargo_slots, cargo_value())
	score_changed.emit(score())


## Итог забега для экрана итога и таблицы рекордов.
func result() -> Dictionary:
	return {
		"class": String(cls.id), "cause": String(ended_cause), "score": final_score,
		"banked": banked, "bonus": bonus, "time": time, "shipments": shipments,
		"emergency_calls": emergency_calls,
	}


func is_over() -> bool:
	return ended_cause != &""


func tick(dt: float) -> void:
	if is_over():
		return
	time += dt
	invulnerable = maxf(invulnerable - dt, 0.0)


## Урон. Возвращает true, если машина погибла.
func damage(amount: int, source: StringName) -> bool:
	if is_over() or amount <= 0 or invulnerable > 0.0:
		return false
	hp = maxi(hp - amount, 0)
	hp_changed.emit(hp, cls.hp_max)
	if hp == 0:
		end(source)
		return true
	return false


func heal(amount: int) -> void:
	hp = mini(hp + amount, cls.hp_max)
	hp_changed.emit(hp, cls.hp_max)


func add_fuel(amount: float) -> void:
	fuel = minf(fuel + amount, cls.fuel_max)
	fuel_changed.emit(fuel, cls.fuel_max)


## Расход за шаг. Возвращает true, если бак опустел именно сейчас.
func burn_fuel(dt: float, throttle: float) -> bool:
	if fuel <= 0.0:
		return false
	fuel = maxf(fuel - VehicleKinematics.fuel_per_second(cls, throttle) * dt, 0.0)
	fuel_changed.emit(fuel, cls.fuel_max)
	return fuel == 0.0


func cargo_slots_used() -> int:
	var n := 0
	for item in cargo:
		n += item.kind.slots
	return n


func cargo_value() -> int:
	var v := 0
	for item in cargo:
		v += item.kind.value
	return v


## Кладёт находку в трюм (GDD §2.2). Если места нет — вытесняет самые дешёвые предметы, пока не
## освободится место, но только если их суммарная цена меньше цены новой; иначе отказ.
func offer_cargo(kind: PickupKind) -> CargoOffer:
	var offer := CargoOffer.new()
	var free := cls.cargo_slots - cargo_slots_used()
	if kind.slots > cls.cargo_slots:
		return offer
	if free < kind.slots:
		var by_value := cargo.duplicate()
		by_value.sort_custom(func(a: CargoItem, b: CargoItem) -> bool: return a.kind.value < b.kind.value)
		var removed: Array[CargoItem] = []
		var removed_value := 0
		for item: CargoItem in by_value:
			if free >= kind.slots:
				break
			removed.append(item)
			removed_value += item.kind.value
			free += item.kind.slots
		if free < kind.slots or removed_value >= kind.value:
			return offer
		for item in removed:
			cargo.erase(item)
			offer.displaced.append(item.kind)
	cargo.append(CargoItem.new(kind))
	offer.accepted = true
	cargo_changed.emit(cargo_slots_used(), cls.cargo_slots, cargo_value())
	return offer


## Сдача груза основному челноку (полная цена). Возвращает засчитанные очки; после конца забега — 0
## (счёт уже итоговый, меню челнока могло не успеть закрыться).
func ship_cargo() -> int:
	var value := cargo_value()
	if is_over() or cargo.is_empty():
		return 0
	banked += value
	shipments += 1
	_clear_cargo()
	score_changed.emit(score())
	return value


## Сдача аварийному челноку: груз за полцены, штраф 500 × 2^(n−1); челнок привёз fuel_units
## топлива и parts единиц запчастей (1 ед. — 1 HP). Возвращает изменение счёта (может быть отрицательным);
## после конца забега обмена нет — 0.
func emergency_ship(fuel_units: float, parts: int) -> int:
	if is_over():
		return 0
	emergency_calls += 1
	var delta := roundi(cargo_value() * rules.emergency_cargo_mult) \
			- rules.emergency_penalty_base * int(pow(2.0, emergency_calls - 1))
	banked += delta
	_clear_cargo()
	add_fuel(fuel_units)
	if parts > 0:
		heal(parts)
	score_changed.emit(score())
	return delta


## Текущий сданный счёт (не ниже нуля).
func score() -> int:
	return maxi(banked, 0)


## Бонус, который даст эвакуация прямо сейчас: остаток HP × 3 + остаток топлива × 2.
func evacuation_bonus() -> int:
	return hp * rules.bonus_hp_mult + roundi(fuel) * rules.bonus_fuel_mult


## Штраф следующего аварийного вызова: 500 × 2^(n−1).
func next_emergency_penalty() -> int:
	return rules.emergency_penalty_base * int(pow(2.0, emergency_calls))


## Эвакуация основным челноком: груз засчитывается, остаток HP и топлива — бонус.
func evacuate() -> void:
	if is_over():
		return
	ship_cargo()
	bonus = evacuation_bonus()
	_finish(CAUSE_EVACUATED)


## Конец забега без эвакуации (гибель, пустой бак): трюм потерян.
func end(cause: StringName) -> void:
	if is_over():
		return
	bonus = 0
	_finish(cause)


func _finish(cause: StringName) -> void:
	ended_cause = cause
	final_score = maxi(banked + bonus, 0)
	ended.emit(cause)


func _clear_cargo() -> void:
	cargo.clear()
	cargo_changed.emit(0, cls.cargo_slots, 0)
