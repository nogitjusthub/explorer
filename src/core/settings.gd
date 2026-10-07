extends Node
## Пользовательские настройки, сохраняются в user://settings.cfg.

const PATH := "user://settings.cfg"

var camera_shake: bool = true
var zoom_preset: int = 1
var master_volume: float = 1.0


func _ready() -> void:
	load_settings()


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	camera_shake = cfg.get_value("video", "camera_shake", camera_shake)
	zoom_preset = cfg.get_value("video", "zoom_preset", zoom_preset)
	master_volume = cfg.get_value("audio", "master_volume", master_volume)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("video", "zoom_preset", zoom_preset)
	cfg.set_value("audio", "master_volume", master_volume)
	var err := cfg.save(PATH)
	if err != OK:
		push_error("Settings: cannot save %s (error %d)" % [PATH, err])
