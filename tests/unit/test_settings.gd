extends TestCase
## Настройки (Settings): испорченный settings.cfg не ломает игру, громкость не выходит за 0…1; регулятор
## громкости пишет файл, только когда уровень изменился, а при протяжке — один раз, по отпусканию.
## Файлы — свои во user:// (настройки игрока не трогаем) и удаляются в конце теста.

const SETTINGS := preload("res://src/core/settings.gd")


func _cfg_path(tag: String) -> String:
	return "user://test_settings_%s_%d.cfg" % [tag, Time.get_ticks_usec()]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


## Свежий Settings (не автозагрузка) с файлом path.
func _load(path: String) -> Node:
	var s: Node = SETTINGS.new()
	s.path = path
	s.load_settings()
	return s


func test_wrong_types_keep_defaults() -> void:
	var path := _cfg_path("types")
	_write(path, "[video]\ncamera_shake=5\nzoom_preset=99\n[audio]\nmaster_volume=\"loud\"\n" \
			+ "[player]\nname=42\nvehicle=[1, 2]\n")
	var s := _load(path)
	assert_eq(s.camera_shake, true, "a number is not a bool")
	assert_eq(s.master_volume, 1.0, "a string is not a volume")
	assert_eq(s.player_name, "AAA")
	assert_eq(s.vehicle_id, "rover")
	assert_false("zoom_preset" in s, "zoom_preset is gone from Settings")
	s.free()
	DirAccess.remove_absolute(path)


func test_volume_clamped_and_snapped() -> void:
	var path := _cfg_path("volume")
	for case: Array in [["7.5", 1.0], ["-3", 0.0], ["0.47", 0.5], ["nan", 1.0], ["inf", 1.0], ["1", 1.0]]:
		_write(path, "[audio]\nmaster_volume=%s\n" % case[0])
		var s := _load(path)
		assert_near(s.master_volume, case[1], 1e-6, "master_volume=%s" % case[0])
		s.free()
	DirAccess.remove_absolute(path)


func test_valid_values_load_and_old_zoom_key_is_dropped_on_save() -> void:
	var path := _cfg_path("valid")
	_write(path, "[video]\ncamera_shake=false\nzoom_preset=2\n[audio]\nmaster_volume=0.3\n" \
			+ "[player]\nname=\"KAC\"\nvehicle=\"tank\"\n")
	var s := _load(path)
	assert_eq(s.camera_shake, false)
	assert_near(s.master_volume, 0.3, 1e-6)
	assert_eq(s.player_name, "KAC")
	assert_eq(s.vehicle_id, "tank")
	s.save_settings()
	var cfg := ConfigFile.new()
	assert_eq(cfg.load(path), OK)
	assert_false(cfg.has_section_key("video", "zoom_preset"), "the unused key is not written back")
	assert_eq(cfg.get_value("player", "vehicle"), "tank")
	s.free()
	DirAccess.remove_absolute(path)


func test_missing_file_keeps_defaults() -> void:
	var s := _load(_cfg_path("missing"))
	assert_eq(s.camera_shake, true)
	assert_eq(s.master_volume, 1.0)
	s.free()


## Регулятор громкости в дереве; автозагрузка Settings — на временный файл, после теста всё как было.
func test_volume_slider_saves_only_changes() -> void:
	var path := _cfg_path("slider")
	var old_path: String = Settings.path
	var old_volume: float = Settings.master_volume
	Settings.path = path
	Settings.master_volume = 0.5
	var slider := VolumeSlider.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(slider)
	var x_half := VolumeSlider.BAR_X + 4.5 * (VolumeSlider.SEG_W + 1)      # пятое деление — 50 %
	var x_high := VolumeSlider.BAR_X + 7.5 * (VolumeSlider.SEG_W + 1)      # восьмое — 80 %

	slider.nudge(0)
	assert_false(FileAccess.file_exists(path), "same level by key — nothing written")
	slider._gui_input(_button(x_half, true))
	for i in 5:
		slider._gui_input(_motion(x_half + i * 0.2))
	assert_near(Settings.master_volume, 0.5, 1e-6)
	slider._gui_input(_button(x_half, false))
	assert_false(FileAccess.file_exists(path), "drag without a change — nothing written")

	slider._gui_input(_button(x_half, true))
	slider._gui_input(_motion(x_high))
	assert_near(Settings.master_volume, 0.8, 1e-6, "volume follows the drag at once")
	assert_false(FileAccess.file_exists(path), "no write while dragging")
	slider._gui_input(_button(x_high, false))
	assert_true(FileAccess.file_exists(path), "written on release")
	DirAccess.remove_absolute(path)

	slider.nudge(-1)
	assert_true(FileAccess.file_exists(path), "a key step is saved at once")

	slider.free()
	DirAccess.remove_absolute(path)
	Settings.path = old_path
	Settings.master_volume = old_volume
	Settings.apply_volume()


func _button(x: float, pressed: bool) -> InputEventMouseButton:
	var mb := InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = pressed
	mb.position = Vector2(x, 5)
	return mb


func _motion(x: float) -> InputEventMouseMotion:
	var mm := InputEventMouseMotion.new()
	mm.position = Vector2(x, 5)
	return mm
