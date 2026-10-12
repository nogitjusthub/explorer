extends Node
## Глобальная шина уведомлений. Состояния не хранит: модули шлют события, HUD/аудио/камера слушают.
## Сюда — только уведомления «один ко многим»; тесно связанные модули используют прямые
## типизированные ссылки. Запросы с ответом через шину запрещены.

@warning_ignore_start("unused_signal")

# Машина и ресурсы забега
signal hp_changed(cur: int, max: int)
signal fuel_changed(cur: float, max: float)
signal fuel_empty()
signal cargo_changed(slots_used: int, slots_max: int, value: int)
signal score_changed(total: int)
signal vehicle_damaged(amount: int, source: StringName, at: Vector3)
signal vehicle_fell(h: int, dmg: int)
signal controls_inverted(seconds: float)   ## разряд по машине: столько секунд управление наоборот
signal vehicle_died(cause: StringName)
signal pickup_collected(kind: StringName, value: int)
signal cargo_shipped(value: int, emergency: bool)

# Угрозы и погода
signal threat_telegraphed(kind: StringName, at: Vector3, seconds: float, dir_hint: Vector2)
signal threat_ended(kind: StringName)
signal lightning_struck(at: Vector3)
signal sheet_lightning(at: Vector3)        ## зарница в тучах — вспышка и далёкий гром без удара
signal wind_changed(dir: Vector2, strength: float)

# Фауна
signal fauna_alerted(kind: StringName, at: Vector3)
signal screen_flash_requested(strength: float)
signal weather_changed(kind: StringName, intensity: float)

# Мир
signal terrain_deformed(tiles: PackedInt64Array)
signal chunk_loaded(coord: Vector2i)
signal chunk_unloaded(coord: Vector2i)

# Челноки
signal shuttle_state_changed(state: StringName, seconds_left: float, pad: Vector3)
signal shuttle_menu_requested(open: bool)
signal emergency_state_changed(state: StringName, seconds_left: float, penalty: int)
## Звук челнока: event — descend (спуск, касание через seconds), land (касание), ascend (взлёт),
## tractor (луч захвата при эвакуации, seconds — сколько тянет); small — аварийный (звук выше).
signal shuttle_sound(event: StringName, at: Vector3, small: bool, seconds: float)

# Камера
signal camera_rotated(quarter_turns: int)
signal camera_shake_requested(strength: float, seconds: float)

# Жизненный цикл забега
signal run_started(seed: int, vehicle: StringName)
signal drop_landed(at: Vector3)            ## капсула десанта коснулась земли
signal run_ended(result: Dictionary)

@warning_ignore_restore("unused_signal")
