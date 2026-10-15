extends TestCase
## Меню настроек (SettingsPanel): W / S — строка, A / D — значение; «вид сзади» — только в режиме «относительно
## машины»; управление сохраняется в файл настроек.


func test_rows_and_values() -> void:
	var saved_path := Settings.path
	var saved_mode := Settings.control_mode
	var saved_chase := Settings.chase_camera
	Settings.path = "user://test_settings_panel_%d.cfg" % Time.get_ticks_usec()
	Settings.control_mode = Settings.ControlMode.WORLD
	Settings.chase_camera = false
	var panel := SettingsPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	var changes := [0]
	panel.changed.connect(func() -> void: changes[0] += 1)

	panel.handle(&"move_down")
	panel.handle(&"move_down")
	assert_eq(panel.selected, 2, "W / S walk the rows")
	panel.handle(&"move_right")
	assert_false(Settings.chase_camera, "rear view needs the vehicle-relative mode")
	panel.handle(&"move_up")
	panel.handle(&"move_right")
	assert_eq(Settings.control_mode, Settings.ControlMode.VEHICLE, "A / D switch the control mode")
	panel.handle(&"move_down")
	panel.handle(&"move_left")
	assert_true(Settings.chase_camera, "…then the rear view toggles")
	assert_true(Settings.chase(), "chase is on")
	assert_eq(changes[0], 2, "changed for the mode and the rear view")
	panel.handle(&"move_up")
	panel.handle(&"move_left")
	assert_false(Settings.chase(), "back to world-relative — no rear view")

	var cfg := ConfigFile.new()
	assert_eq(cfg.load(Settings.path), OK, "saved")
	assert_eq(int(cfg.get_value("controls", "mode", -1)), Settings.ControlMode.WORLD, "mode saved")
	assert_eq(cfg.get_value("controls", "chase_camera", false), true, "rear-view choice kept")

	panel.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Settings.path))
	Settings.path = saved_path
	Settings.control_mode = saved_mode
	Settings.chase_camera = saved_chase
