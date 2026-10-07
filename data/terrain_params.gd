class_name TerrainParams
extends Resource
## Параметры генератора рельефа (GDD §3.4). Высоты — в ярусах, частоты — в 1/тайл.

@export_group("Base")
@export var base_level: float = 7.0
@export var coarse_freq: float = 1.0 / 220.0
@export var coarse_amp: float = 6.0
@export var detail_freq: float = 1.0 / 70.0
@export var detail_amp: float = 2.5

@export_group("Terraces")
@export var terrace_low: float = 1.0            ## высота ступени на равнинах
@export var terrace_high: float = 2.0           ## высота ступени на плато
@export var plateau_freq: float = 1.0 / 160.0
@export var step_sharp_w: float = 0.06          ## доля интервала ступени, на которой идёт подъём (резко)
@export var step_gentle_w: float = 1.0          ## то же в зоне пандусов (полого)
@export var ramp_freq: float = 1.0 / 26.0
@export var ramp_threshold: float = 0.15        ## шум пандусов выше порога — пологий переход

@export_group("Avenues")
## Сеть пологих «проездов»: искривлённая решётка коридоров, где обрывы, горы и ущелья сходят на нет.
## Любая замкнутая стена крупнее ячейки решётки пересекает проезд — ям без выхода крупнее ячейки нет.
@export var avenue_spacing: float = 56.0
@export var avenue_width: float = 2.5
@export var avenue_fade: float = 4.0
@export var avenue_canyon_fade: float = 9.0     ## ущелья выходят к проезду дольше: дно поднимается полого
@export var avenue_warp: float = 12.0
@export var avenue_warp_freq: float = 1.0 / 90.0

@export_group("Mountains")
@export var mountain_freq: float = 1.0 / 150.0
@export var mountain_threshold: float = 0.32
@export var mountain_height: float = 8.0
@export var ridge_freq: float = 1.0 / 32.0

@export_group("Canyons")
@export var canyon_freq: float = 1.0 / 260.0
@export var canyon_warp_amp: float = 45.0
@export var canyon_width: float = 0.075         ## полуширина полосы в единицах шума
@export var canyon_depth: float = 4.0

@export_group("Water")
@export var water_level: float = 3.0
@export var water_freq: float = 1.0 / 500.0
@export var water_amp: float = 1.4

@export_group("Ledges")
@export var ledge_freq: float = 1.0 / 18.0
@export var ledge_p_plateau: float = 0.3
@export var ledge_p_plain: float = 0.1

@export_group("Biomes")
@export var forest_freq: float = 1.0 / 75.0
@export var forest_threshold: float = 0.28
@export var crater_freq: float = 1.0 / 120.0
@export var crater_threshold: float = 0.45
@export var mineral_freq: float = 1.0 / 30.0
@export var crystal_threshold: float = 0.5

@export_group("Trees")
@export var tree_density_forest: float = 0.35
@export var tree_density_plain: float = 0.03
@export var tree_density_lakeside: float = 0.08
@export var tree_density_rocky: float = 0.01

@export_group("Shuttle pads")
@export var pad_block: int = 64                 ## сторона блока (2×2 чанка), одна площадка на блок
@export var pad_half: int = 2                   ## площадка 5×5 тайлов
@export var pad_blend: float = 6.0              ## ширина пологого кольца вокруг площадки
@export var pad_clear_r: int = 3                ## без деревьев в этом радиусе от края площадки
