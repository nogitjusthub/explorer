class_name BalanceRules
extends Resource
## Общие правила баланса забега (GDD §2, §6, §7). Числа — стартовые, для плейтестов.

@export_group("Run")
@export var drop_invuln_s: float = 3.0          ## неуязвимость после десанта
@export var death_delay_s: float = 1.5          ## пауза между гибелью и экраном итога
@export var radar_range: float = 40.0
@export var pickup_radius: float = 0.6          ## тайлов: на таком расстоянии машина подбирает находку

@export_group("Score")
@export var bonus_hp_mult: int = 3
@export var bonus_fuel_mult: int = 2

@export_group("Pickups")
## Шанс находки на тайле (по хэшу тайла); канистры — на чанк, решаются при первой загрузке.
@export var crystal_chance_on_crystal: float = 0.07
@export var crystal_chance_elsewhere: float = 0.001
@export var sample_chance_lakeside: float = 0.0045
@export var sample_chance_forest: float = 0.0025
@export var core_chance_rocky: float = 0.0008
@export var repair_per_chunk: float = 1.0 / 30.0
@export var canister_d0: float = 1.0 / 18.0     ## канистр на чанк в начале забега
@export var canister_floor: float = 0.3         ## доля от D0, ниже которой плотность не падает
@export var canister_fade_s: float = 600.0      ## за столько секунд плотность падает до floor

@export_group("Shuttle")
@export var shuttle_interval_base: float = 90.0
@export var shuttle_interval_step: float = 30.0
@export var shuttle_interval_max: float = 180.0
@export var shuttle_dist_base: float = 25.0
@export var shuttle_dist_step: float = 15.0
@export var shuttle_dist_max: float = 70.0
@export var shuttle_announce_s: float = 30.0    ## площадка видна на радаре за столько до посадки
@export var shuttle_window_s: float = 20.0
@export var shuttle_zone_r: float = 2.0
@export var shuttle_stop_speed: float = 0.5     ## тайл/с: машина «остановилась» в зоне

@export_group("Emergency")
@export var emergency_delay_s: float = 10.0
@export var emergency_fuel_frac: float = 0.3
@export var emergency_cargo_mult: float = 0.5
@export var emergency_penalty_base: int = 500   ## × 2^(n−1)
@export var empty_tank_decision_s: float = 10.0
