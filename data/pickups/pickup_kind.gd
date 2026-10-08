class_name PickupKind
extends Resource
## Вид находки (GDD §6). Один .tres на вид.

enum Shape { CRYSTAL, CAPSULE, ORB, BOX, CANISTER }

@export var id: StringName
@export var display_name: String
@export var cargo: bool = false                 ## идёт в трюм (иначе действует сразу)
@export var slots: int = 1
@export var value: int = 0                      ## очки при сдаче
@export var hp_restore: int = 0
@export var fuel_restore_min: float = 0.0       ## доля бака
@export var fuel_restore_max: float = 0.0
@export var on_radar: bool = true

@export_group("Look")
@export var shape: Shape = Shape.CRYSTAL
@export var color: Color = Color.WHITE
@export var glow: float = 0.5
@export var size: float = 0.25
