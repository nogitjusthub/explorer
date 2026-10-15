extends Node
## Пользовательские настройки, сохраняются в user://settings.cfg (в браузере — IndexedDB).
## Файл мог быть испорчен или поправлен руками: при чтении значение чужого типа отбрасывается (остаётся
## по умолчанию), громкость зажимается в 0…1. Ключ video/zoom_preset из старых версий не читается
## (зум не настраивается) и при следующем сохранении пропадает.

const PATH := "user://settings.cfg"
## Режим управления: W A S D — вверх, вниз, влево, вправо по экрану (WORLD) или вперёд, назад, поворот (VEHICLE).
enum ControlMode { WORLD, VEHICLE }

var path := PATH                       ## тесты подставляют свой файл, чтобы не трогать настройки игрока
var camera_shake: bool = true          ## тряска камеры (IsoCameraRig); переключателя в интерфейсе пока нет
var master_volume: float = 1.0         ## общая громкость 0…1 шагами по 0,1 (VolumeSlider); 0 — без звука
var vehicle_id: String = "rover"       ## последний выбранный класс техники
var quick_restart := false             ## «Заново» на экране итога: следующий забег без экрана выбора (не сохраняется)
var control_mode: ControlMode = ControlMode.WORLD   ## режим управления (меню настроек)
var chase_camera := false              ## «камера: вид сзади» — только при ControlMode.VEHICLE: камера за машиной


## Камера идёт за машиной (вид сзади): включена и режим «относительно машины».
func chase() -> bool:
	return chase_camera and control_mode == ControlMode.VEHICLE


func _ready() -> void:
	load_settings()
	apply_volume()


## Новая общая громкость: применить к шине Master и, если persist, сохранить (протяжка регулятора
## сохраняет один раз — по отпусканию). false — уровень не изменился: ни шину, ни файл не трогаем.
func set_master_volume(v: float, persist: bool = true) -> bool:
	var level := clampf(snappedf(v, 0.1), 0.0, 1.0) if is_finite(v) else master_volume
	if is_equal_approx(level, master_volume):
		return false
	master_volume = level
	apply_volume()
	if persist:
		save_settings()
	return true


## Громкость шины Master: по квадрату уровня — на слух ступени ровнее (половина — −12 дБ); 0 — выключен.
func apply_volume() -> void:
	AudioServer.set_bus_mute(0, master_volume <= 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(master_volume * master_volume, 0.0001)))


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(path) != OK:
		return
	var shake: Variant = cfg.get_value("video", "camera_shake", camera_shake)
	if shake is bool:
		camera_shake = shake
	var volume: Variant = cfg.get_value("audio", "master_volume", master_volume)
	if (volume is float or volume is int) and is_finite(float(volume)):
		master_volume = clampf(snappedf(float(volume), 0.1), 0.0, 1.0)     # больше 1 перегрузил бы шину
	var vehicle_value: Variant = cfg.get_value("player", "vehicle", vehicle_id)
	if vehicle_value is String:
		vehicle_id = vehicle_value                 # неизвестный класс GameFlow заменит на rover
	var mode: Variant = cfg.get_value("controls", "mode", control_mode)
	if mode is int and mode in ControlMode.values():
		control_mode = mode as ControlMode
	var chase_value: Variant = cfg.get_value("controls", "chase_camera", chase_camera)
	if chase_value is bool:
		chase_camera = chase_value


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("player", "vehicle", vehicle_id)
	cfg.set_value("controls", "mode", control_mode)
	cfg.set_value("controls", "chase_camera", chase_camera)
	var err := cfg.save(path)
	if err != OK:
		push_error("Settings: cannot save %s (error %d)" % [path, err])
