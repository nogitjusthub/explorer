extends Node
## Типизированный доступ к данным баланса из data/*.tres.
## Пути перечислены явно: в экспортированной сборке .tres переименовываются, сканировать папку ненадёжно.

const VEHICLE_PATHS: Dictionary[StringName, String] = {
	&"rover": "res://data/vehicles/rover.tres",
}

var _vehicles: Dictionary[StringName, VehicleClass] = {}


func _ready() -> void:
	for id: StringName in VEHICLE_PATHS:
		var cls := load(VEHICLE_PATHS[id]) as VehicleClass
		if cls == null:
			push_error("Balance: cannot load vehicle '%s' from %s" % [id, VEHICLE_PATHS[id]])
			continue
		_vehicles[id] = cls


func vehicle(id: StringName) -> VehicleClass:
	return _vehicles.get(id)


func vehicle_ids() -> Array[StringName]:
	return _vehicles.keys()


## Подменяет класс машины; нужно тестам, чтобы гонять логику на своих числах.
func override_vehicle(id: StringName, cls: VehicleClass) -> void:
	_vehicles[id] = cls
