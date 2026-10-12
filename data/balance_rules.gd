class_name BalanceRules
extends Resource
## Общие правила баланса забега (GDD §2, §6, §7). Числа — стартовые, для плейтестов.

@export_group("Run")
@export var drop_invuln_s: float = 3.0          ## неуязвимость после десанта
@export var death_delay_s: float = 1.5          ## пауза между гибелью и экраном итога
@export var radar_range: float = 40.0
@export var pickup_radius: float = 0.6          ## тайлов: на таком расстоянии машина подбирает находку
@export var shock_invert_s: float = 3.0         ## разряд по машине (молния, электрошок) — столько секунд управление наоборот
@export var low_fuel_frac: float = 0.2          ## меньше этой доли бака — пейджер «МАЛО ТОПЛИВА»
@export var empty_crawl_speed: float = 0.4      ## тайл/с — с пустым баком машина ползёт (тайл за 2,5 с)

@export_group("Score")
@export var bonus_hp_mult: int = 3
@export var bonus_fuel_mult: int = 2

@export_group("Pickups")
## Шанс находки на тайле (по хэшу тайла); канистры — на чанк, решаются при первой загрузке.
@export var crystal_chance_on_crystal: float = 0.04
@export var crystal_chance_elsewhere: float = 0.0006
@export var sample_chance_lakeside: float = 0.003
@export var sample_chance_forest: float = 0.0016
@export var core_chance_rocky: float = 0.0005
@export var rough_pickup_mult: float = 1.5      ## в россыпях камней находки чуть чаще (риск и награда)
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
@export var shuttle_zone_r: float = 3.0         ## зона погрузки вокруг севшего челнока (корпус — MAIN_HULL_R)
@export var shuttle_stop_speed: float = 0.5     ## тайл/с: машина «остановилась» в зоне

@export_group("Threats")
## Уровень угрозы T = min(threat_max; 1 + floor(t / time_step) + floor(путь / dist_step)) (GDD §7.1).
@export var threat_time_step_s: float = 90.0
@export var threat_dist_step: float = 500.0
@export var threat_max: int = 6
@export var calm_after_ship_s: float = 20.0      ## после сдачи основному челноку новые угрозы не начинаются
@export var first_event_s: float = 35.0          ## ясная погода в начале забега
@export var clear_t1_s: float = 45.0             ## пауза между погодными событиями при T = 1…
@export var clear_t6_s: float = 15.0             ## …и при T = 6 (линейно между ними, ±30%)
@export var quake_min_level: int = 3
@export var quake_interval_t3_s: float = 80.0    ## при T = 3 землетрясения редко…
@export var quake_interval_t4_s: float = 45.0    ## …с T = 4 регулярно

@export_group("Storm")
@export var storm_radius: float = 45.0           ## грозовой фронт диаметром 90 тайлов — проще уйти, чем проехать
@export var storm_dark: float = 0.5              ## насколько темнее земля под тучами
@export var storm_speed: float = 2.04
@export var storm_max_s: float = 150.0          ## дольше — фронт рассеивается
@export var strike_interval_s: float = 2.5
@export var strike_near_frac: float = 0.35       ## доля ударов рядом с машиной (если она под фронтом)
@export var strike_near_r: float = 4.0
@export var strike_telegraph_s: float = 0.7
@export var strike_radius: float = 1.0
@export var strike_core_r: float = 0.45          ## ближе — урон «в центре»
@export var strike_damage_center: int = 25
@export var strike_damage_edge: int = 10
@export var strike_crater_depth: int = 1
@export var strike_crater_chance: float = 0.15   ## воронку выбивает не каждый удар; в воду — никогда

@export_group("Murk")
## Плохая видимость — огромная масса, ползущая по карте: проехать насквозь трудно, проще уйти, пока
## не нагнала. Держится, пока проходит мимо машины, но не дольше murk_max_s — потом рассеивается.
@export var fog_radius: float = 60.0
@export var fog_speed: float = 1.56
@export var dust_radius: float = 72.0
@export var dust_speed: float = 2.28
@export var murk_max_s: float = 150.0
@export var dissipate_s: float = 12.0            ## за столько масса (и гроза) тает в конце жизни
@export var murk_gap: float = 14.0               ## масса появляется так, чтобы край был за экраном
@export var fog_weight: float = 0.45             ## жребий вида: туман / кислотный / пылевая буря
@export var acid_weight: float = 0.2             ## с acid_min_level
@export var dust_weight: float = 0.35            ## с dust_min_level
@export var biome_weather_weight: float = 1.8    ## туман чаще у озёр, буря — на кратерах и равнинах
@export var murk_share: float = 0.5              ## доля плохой видимости среди погодных событий (остальное — гроза)
@export var fog_visibility: float = 4.0
@export var acid_min_level: int = 3
@export var acid_rise: int = 2                   ## газ на столько ярусов выше самой низкой точки вокруг
@export var acid_scan_r: int = 12
@export var acid_dps: float = 1.0
@export var dust_min_level: int = 2
@export var dust_visibility: float = 3.0
@export var dust_wind_accel: float = 1.6         ## делится на массу класса
@export var dust_tornado_chance: float = 0.6     ## с tornado_min_level: смерч при входе в бурю

@export_group("Tornado")
@export var tornado_min_level: int = 3
@export var tornado_interval_t3_s: float = 100.0 ## сам по себе (буря прошла где-то рядом)…
@export var tornado_interval_t4_s: float = 65.0  ## …с T = 4 чаще
@export var tornado_life_s: float = 45.0
@export var tornado_speed: float = 2.0
@export var tornado_spawn_dist: float = 15.0
@export var tornado_pull_r: float = 6.0
@export var tornado_pull_accel: float = 5.0      ## a(r) = pull / масса × (1 − r / pull_r)
@export var tornado_core_r: float = 1.5
@export var tornado_core_dps: float = 15.0
@export var tornado_throw_after_s: float = 1.5
@export var tornado_throw_dist: float = 4.0

@export_group("Quake")
@export var quake_telegraph_s: float = 2.5        ## от сообщения на пейджере до сдвига: гул и тряска нарастают
@export var quake_line_s: float = 1.0             ## линия разлома проступает за столько до сдвига: белая → красная
## Сила толчка 0…1 (случайно, выше на высоком уровне угрозы) задаёт длину разлома, высоту сброса
## и редкость пандусов — сильный толчок даёт длинный разлом со сплошными обрывами.
@export var fault_length_min: float = 12.0
@export var fault_length_max: float = 34.0
@export var fault_up_max: int = 3                ## одна сторона поднимается на 1…up_max
@export var fault_down_max: int = 2              ## другая опускается на 0…down_max
@export var fault_ramp_every_min: int = 5        ## пандус через столько тайлов у слабого толчка…
@export var fault_ramp_every_max: int = 12       ## …и у сильного
@export var fault_debris_r: float = 1.3          ## осыпь (неровный грунт) по обе стороны линии
@export var fault_pad_clearance: float = 6.0
@export var quake_toss_dist: float = 3.0
@export var quake_toss_damage: int = 10

@export_group("Fauna")
@export var noise_range: float = 12.0            ## пассивная фауна слышит машину в радиусе шум × это
@export var noise_full_frac: float = 0.8         ## шум 1,0 от этой доли Vmax
@export var fauna_spawn_min: float = 40.0        ## появляется в кольце 40…52 тайла от машины
@export var fauna_spawn_max: float = 52.0
@export var fauna_despawn: float = 80.0          ## дальше — исчезает
@export var shuttle_noise_r: float = 15.0        ## посадка основного челнока стягивает фауну
@export var shuttle_noise_s: float = 20.0
@export var emergency_noise_r: float = 8.0
@export var shuttle_pack_chance: float = 0.5     ## к севшему основному челноку выходит стая — не всегда
@export var emergency_noise_s: float = 10.0
@export var fauna_give_up_s: float = 6.0        ## не подобраться к машине столько — фауна сдаётся (червь уходит)
## Скорости погони — между Vmax танка (4) и ровера (6,5): ровер и ховер уходят от фауны, танк — нет.
@export var hopper_speed: float = 5.2
@export var hopper_wander_speed: float = 1.0       ## патрулирует медленно
@export var hopper_patrol_r: float = 5.0          ## обходит кольцо такого радиуса вокруг места появления
@export var hopper_sight_r: float = 6.0           ## машину ближе видит и тихую (шум не нужен)
@export var hopper_bite: int = 6
@export var hopper_bite_cd_s: float = 1.2         ## кусает одна, передняя особь стаи
@export var hopper_chase_s: float = 10.0
@export var hopper_chase_dist: float = 20.0
@export var pack_min: int = 2
@export var pack_max: int = 3
@export var worm_min_level: int = 2
@export var worm_first_s: float = 90.0            ## червь редок: первый — не раньше этого времени забега…
@export var worm_gap_s: float = 150.0             ## …следующий — не раньше этого после встречи (гнался за машиной)
@export var worm_chance: float = 0.15             ## шанс появиться на каждой проверке (раз в 2 с), когда можно
@export var worm_speed: float = 5.0
@export var worm_idle_speed: float = 1.5          ## не слышит машину — незаметно подтягивается к ней
@export var worm_spawn_min: float = 20.0          ## появляется ближе остальных — в 20…30 тайлах, на своём грунте
@export var worm_spawn_max: float = 30.0
@export var worm_telegraph_s: float = 0.9
@export var worm_damage: int = 50                 ## два броска убивают ровер (100) и ховер (70); танк (150) — три
@export var worm_toss: float = 3.0
@export var shellback_min_level: int = 3
@export var shellback_speed: float = 4.6
@export var shellback_charge_speed: float = 5.5
@export var shellback_charge_dist: float = 6.0
@export var shellback_dig_s: float = 1.0
@export var shellback_damage: int = 35

@export_group("Water fauna")
## Водная и береговая фауна (GDD §5.6). Шокер-троеглазка — по чанкам, в мелкой воде; илозуб — в зыбучем
## грунте и воде рядом с ним; Несса — редкая, в больших озёрах.
@export var ray_chance: float = 0.03             ## шанс троеглазки на тайле мелкой воды…
@export var ray_per_chunk: int = 3               ## …но не больше стольких на чанк
@export var ray_shock_r: float = 1.0             ## машина в воде ближе — мгновенный разряд
@export var ray_damage: int = 10
@export var ray_cooldown_min_s: float = 5.0
@export var ray_cooldown_max_s: float = 10.0
@export var shark_min_level: int = 2
@export var shark_speed: float = 2.5             ## подход медленный — танк легко уедет
@export var shark_lunge_dist: float = 2.5        ## прыжок из зыбуна на столько тайлов…
@export var shark_lunge_speed: float = 9.0       ## …с такой скоростью
@export var shark_telegraph_s: float = 0.6       ## выныривает и разевает пасть перед прыжком
@export var shark_damage: int = 15
@export var shark_spawn_min: float = 12.0        ## появляется в зыбуне в 12…25 тайлах от машины
@export var shark_spawn_max: float = 25.0
@export var nessie_min_level: int = 2
@export var nessie_first_s: float = 120.0        ## редкая: первая — не раньше этого времени забега…
@export var nessie_gap_s: float = 180.0          ## …следующая — не раньше этого после встречи
@export var nessie_chance: float = 0.2           ## на проверке раз в 2 с, когда машина у большого озера
@export var nessie_speed: float = 4.0            ## под водой (V-след): ховер уходит
@export var nessie_reach: float = 3.5            ## шея бьёт на столько тайлов от основания (достаёт берег за мелководьем)
@export var nessie_damage: int = 30
@export var nessie_toss: float = 2.5             ## ховер подбрасывает на столько тайлов
@export var nessie_lake_tiles: int = 30          ## «большое озеро»: столько глубоких тайлов в радиусе 6

@export_group("Whirlpool")
## Водоворот (GDD §5.6) — 2×2 тайла на глубокой воде, туда заходит только ховер.
@export var whirlpool_min_level: int = 2
@export var whirlpool_interval_s: float = 60.0   ## не чаще (±25%)
@export var whirlpool_chance: float = 0.35       ## на проверке раз в 2 с, пока машина над глубокой водой
@export var whirlpool_life_min_s: float = 20.0
@export var whirlpool_life_max_s: float = 30.0
@export var whirlpool_form_s: float = 2.0        ## телеграф: круги и пена, тяги ещё нет
@export var whirlpool_pull_r: float = 3.5        ## тянет к центру только по воде:
@export var whirlpool_pull_accel: float = 4.0    ## a(r) = pull / масса × (1 − r / pull_r)
@export var whirlpool_core_r: float = 0.8        ## в ядре топит: машина уходит в воду…
@export var whirlpool_core_dps: float = 10.0     ## …и теряет столько HP в секунду, пока не вырвется

@export_group("Emergency")
@export var emergency_delay_s: float = 10.0
@export var emergency_supply: int = 30          ## привозит столько единиц: топливо и запчасти (1 ед. — 1 HP) в любой пропорции
@export var emergency_supply_step: int = 5      ## шаг ползунка в меню вызова
@export var emergency_land_min: float = 2.0     ## садится не ближе этого к машине (корпус не накроет её)…
@export var emergency_land_max: float = 4.5     ## …и не дальше этого
@export var emergency_cargo_mult: float = 0.5
@export var emergency_penalty_base: int = 500   ## × 2^(n−1)
