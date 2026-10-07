class_name VehicleClass
extends Resource
## Числа баланса одного класса техники (GDD §4). Один .tres на класс.

@export var id: StringName
@export var display_name: String
@export var hp_max: int = 100

@export_group("Movement")
@export var max_speed: float = 8.0           ## тайл/с
@export var accel: float = 6.0               ## тайл/с²
@export var brake_decel: float = 10.0        ## тайл/с²
@export var turn_rate_deg: float = 180.0     ## °/с
@export var turn_in_place: bool = false
@export var drift: float = 0.0               ## боковое проскальзывание; только ховер
@export var mass: float = 1.0
@export var uphill_loss_per_tile: float = 1.0 / 6.0   ## доля max_speed, теряемая за каждый тайл подъёма подряд
@export var uphill_floor: float = 1.0 / 3.0           ## предел скорости не опускается ниже этой доли
@export var downhill_accel_bonus: float = 0.2

@export_group("Water")
@export var max_water_depth: int = 1         ## в ярусах; -1 — любая глубина (ховер)
@export var water_speed_mult: float = 0.7
@export var hovers: bool = false

@export_group("Falls")
@export_enum("exp", "linear") var fall_damage_mode: String = "exp"
@export var fall_damage_base: float = 20.0   ## exp: base × 2^(h−2); linear: base × (h−1)

@export_group("Trees")
@export var tree_fell_speed_frac: float = 0.9
@export var tree_speed_after_frac: float = 0.5   ## после валки скорость не выше этой доли max_speed
@export var tree_fell_damage: int = 0

@export_group("Fuel and cargo")
@export var fuel_max: float = 100.0
@export var fuel_idle_per_min: float = 3.0
@export var fuel_drive_per_min: float = 15.0
@export var cargo_slots: int = 10

@export_group("Presentation")
@export var model: PackedScene
@export var engine_sound: AudioStream
