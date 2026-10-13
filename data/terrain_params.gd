class_name TerrainParams
extends Resource
## Параметры генератора рельефа (GDD §3.4). Высоты — в ярусах, частоты — в 1/тайл.

@export_group("Base")
@export var base_level: float = 10.0
@export var coarse_freq: float = 1.0 / 260.0
@export var coarse_amp: float = 12.0            ## крупный рельеф: много уровней при пологих склонах
@export var detail_freq: float = 1.0 / 70.0
@export var detail_amp: float = 2.0

@export_group("Terraces")
@export var terrace_low: float = 1.0            ## высота ступени на равнинах
@export var terrace_high: float = 2.0           ## высота ступени на плато
@export var plateau_freq: float = 1.0 / 160.0
@export var step_sharp_w: float = 0.06          ## доля интервала ступени под подъём на скалах (обрыв)
@export var step_soil_w: float = 0.6            ## то же на грунте (пологий склон между полками)
@export var step_gentle_w: float = 1.0          ## в зонах пандусов и проездах (без ступеней)
@export var ramp_freq: float = 1.0 / 26.0
@export var ramp_threshold: float = 0.15        ## шум пандусов выше порога — пологий переход

@export_group("Rock")
## Скалистость: горы, края ущелий и отдельные выходы скал. Обрывы и уступы — в основном здесь.
@export var rock_freq: float = 1.0 / 90.0
@export var rock_threshold: float = 0.38

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
@export var ridge_freq: float = 1.0 / 56.0

@export_group("Canyons")
@export var canyon_freq: float = 1.0 / 260.0
@export var canyon_warp_amp: float = 45.0
@export var canyon_width: float = 0.075         ## полуширина полосы в единицах шума
@export var canyon_depth: float = 4.0

@export_group("Water")
## Мир делится на области (искривлённая решётка); у каждой свой уровень воды. Между областями
## с разными уровнями рельеф поднимается пологой дамбой выше обоих — вода разных уровней не
## соприкасается и не «висит» над сухим соседом. Одинаковые уровни стыкуются вода к воде.
@export var water_level: float = 4.0
@export var water_spread: int = 1               ## уровень области: water_level ± spread
@export var water_region: float = 192.0         ## размер области, тайлов
@export var water_region_warp: float = 40.0
@export var dam_width: float = 8.0              ## дамба действует в стольких тайлах от границы
@export var dam_slope: float = 0.5              ## ярусов на тайл — склоны дамбы проезжаемы

@export_group("Puddles")
## Лужи на ровных полках холмов и плато: чаша глубиной 1 ярус, вода вровень с краем.
@export var puddle_cell: int = 22
@export var puddle_chance: float = 0.4
@export var puddle_r_min: float = 1.5
@export var puddle_r_max: float = 3.0

@export_group("Ledges")
@export var ledge_freq: float = 1.0 / 18.0
@export var ledge_p_soil: float = 0.03          ## доля уступов на грунте
@export var ledge_p_rock: float = 0.3           ## на скалах

@export_group("Biomes")
@export var forest_freq: float = 1.0 / 75.0
@export var forest_threshold: float = 0.28
@export var crater_freq: float = 1.0 / 120.0
@export var crater_threshold: float = 0.45
@export var mineral_freq: float = 1.0 / 30.0
@export var crystal_threshold: float = 0.5

@export_group("Dunes")
## Дюнные поля посреди части пустынь (кратерный биом): поперечные гряды поперёк ветра (один на забег),
## слегка извилистые. Гряды — из пологих склонов в ярус, без стенок и уступов; поле гаснет к краям
## пустыни, к лесу, скалам, горам, ущельям, воде и площадкам челнока.
@export var dunes_enabled: bool = true
@export var dune_field_freq: float = 1.0 / 300.0    ## шум выбора: в какой пустыне поле, в какой нет
@export var dune_field_threshold: float = 0.0       ## выше порога — поле (примерно каждая вторая пустыня)
@export var dune_field_fade: float = 0.15           ## ширина края поля в единицах шума выбора
@export var dune_core_from: float = 0.03            ## поле начинается глубже края пустыни: порог кратеров + …
@export var dune_core_to: float = 0.18              ## … и набирает полную высоту к этому
@export var dune_spacing: float = 10.0              ## шаг гряд, тайлов
@export var dune_height: float = 2.2                ## высота гребня, ярусов (до округления)
@export var dune_lee: float = 0.45                  ## доля шага под подветренный (более крутой) склон
@export var dune_meander: float = 4.0               ## изгиб гряд, тайлов
@export var dune_meander_freq: float = 1.0 / 80.0
@export var dune_crest_freq: float = 1.0 / 30.0     ## высота меняется вдоль гребня — гряды рвутся
@export var dune_pad_fade: float = 10.0             ## за кольцом площадки дюны набирают высоту за столько тайлов
@export var dune_pad_penalty: float = 6.0           ## площадка челнока избегает дюн (штраф к оценке места)

@export_group("Ground")
@export var rough_freq: float = 1.0 / 11.0        ## пятна неровного грунта (россыпи камней)
@export var rough_threshold: float = 0.42         ## выше — неровный; на скалах порог ниже, у воды и в лесу — выше
@export var rough_rocky_bonus: float = 0.18
@export var talus_tiers: int = 3                  ## под обрывом от стольких ярусов — осыпь
@export var talus_chance: float = 0.8
@export var mire_freq: float = 1.0 / 7.0          ## зыбучий грунт — пятнами вдоль кромки воды
@export var mire_threshold: float = 0.33          ## зыбким становится около четверти кромки

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

@export_group("Nests")
@export var nest_pad_dist: float = 15.0          ## гнездо не ближе к центру площадки
@export var nest_clear_r: int = 2                ## без деревьев вокруг гнезда
