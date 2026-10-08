extends Node
## Типизированный доступ к данным баланса из data/*.tres.
## Пути перечислены явно: в экспортированной сборке .tres переименовываются, сканировать папку ненадёжно.

const RULES_PATH := "res://data/balance.tres"
const VEHICLE_PATHS: Dictionary[StringName, String] = {
	&"rover": "res://data/vehicles/rover.tres",
	&"tank": "res://data/vehicles/tank.tres",
	&"hover": "res://data/vehicles/hover.tres",
}
const PICKUP_PATHS: Dictionary[StringName, String] = {
	&"crystal": "res://data/pickups/crystal.tres",
	&"sample": "res://data/pickups/sample.tres",
	&"core": "res://data/pickups/core.tres",
	&"repair": "res://data/pickups/repair.tres",
	&"canister": "res://data/pickups/canister.tres",
}

var rules: BalanceRules
var _vehicles: Dictionary[StringName, VehicleClass] = {}
var _pickups: Dictionary[StringName, PickupKind] = {}


func _ready() -> void:
	rules = load(RULES_PATH) as BalanceRules
	if rules == null:
		push_error("Balance: cannot load %s" % RULES_PATH)
		rules = BalanceRules.new()
	for id: StringName in VEHICLE_PATHS:
		var cls := load(VEHICLE_PATHS[id]) as VehicleClass
		if cls == null:
			push_error("Balance: cannot load vehicle '%s' from %s" % [id, VEHICLE_PATHS[id]])
			continue
		_vehicles[id] = cls
	for id: StringName in PICKUP_PATHS:
		var kind := load(PICKUP_PATHS[id]) as PickupKind
		if kind == null:
			push_error("Balance: cannot load pickup '%s' from %s" % [id, PICKUP_PATHS[id]])
			continue
		_pickups[id] = kind


func vehicle(id: StringName) -> VehicleClass:
	return _vehicles.get(id)


func vehicle_ids() -> Array[StringName]:
	return _vehicles.keys()


func pickup(id: StringName) -> PickupKind:
	return _pickups.get(id)


func pickup_ids() -> Array[StringName]:
	return _pickups.keys()


## Подменяет класс машины; нужно тестам, чтобы гонять логику на своих числах.
func override_vehicle(id: StringName, cls: VehicleClass) -> void:
	_vehicles[id] = cls
