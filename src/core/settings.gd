extends Node
## Пользовательские настройки, сохраняются в user://settings.cfg.

const PATH := "user://settings.cfg"

var camera_shake: bool = true
var zoom_preset: int = 1
var master_volume: float = 1.0         ## общая громкость 0…1 шагами по 0,1 (VolumeSlider); 0 — без звука
var player_name: String = "AAA"        ## последнее введённое имя для таблицы рекордов
var vehicle_id: String = "rover"       ## последний выбранный класс техники
var quick_restart := false             ## «Заново» на экране итога: следующий забег без экрана выбора (не сохраняется)


func _ready() -> void:
	load_settings()
	apply_volume()


## Новая общая громкость: применить к шине Master и сохранить.
func set_master_volume(v: float) -> void:
	master_volume = clampf(snappedf(v, 0.1), 0.0, 1.0)
	apply_volume()
	save_settings()


## Громкость шины Master: по квадрату уровня — на слух ступени ровнее (половина — −12 дБ); 0 — выключен.
func apply_volume() -> void:
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume * master_volume, 0.0001)))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	camera_shake = cfg.get_value("video", "camera_shake", camera_shake)
	zoom_preset = cfg.get_value("video", "zoom_preset", zoom_preset)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	player_name = cfg.get_value("player", "name", player_name)
	vehicle_id = cfg.get_value("player", "vehicle", vehicle_id)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("video", "zoom_preset", zoom_preset)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "vehicle", vehicle_id)
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Settings: cannot save %s (error %d)" % [PATH, err])
