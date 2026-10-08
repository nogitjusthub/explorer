class_name VehicleClass
extends Resource
## Числа баланса одного класса техники (GDD §4). Один .tres на класс.

@export var id: StringName
@export var display_name: String
@export_multiline var blurb: String          ## одна-две строки о характере класса (экран выбора)
@export var hp_max: int = 100

@export_group("Movement")
@export var max_speed: float = 6.5           ## тайл/с
@export var accel: float = 5.0               ## тайл/с²
@export var brake_decel: float = 8.5         ## тайл/с²
@export var turn_rate_deg: float = 150.0     ## °/с
@export var turn_in_place: bool = false
@export var drift: float = 0.0               ## боковое проскальзывание 0..1: 0 — скорость всегда по курсу
@export var mass: float = 1.0
@export var uphill_loss_per_tile: float = 1.0 / 6.0   ## доля max_speed, теряемая за каждый тайл подъёма подряд
@export var uphill_floor: float = 1.0 / 3.0           ## предел скорости не опускается ниже этой доли
@export var downhill_accel_bonus: float = 0.2

@export_group("Walls")
@export var wall_hit_speed_frac: float = 2.0 / 3.0   ## удар в стенку со скоростью «в стену» от этой доли max_speed…
@export var wall_hit_damage: int = 10                 ## …наносит фиксированный урон

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
@export var engine_pitch: float = 1.0        ## тон двигателя относительно ровера
