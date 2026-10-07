extends TestCase
## Smoke-тесты каркаса: настройки проекта, autoload'ы и данные баланса подключены.


func test_autoloads_present() -> void:
	var root := (Engine.get_main_loop() as SceneTree).root
	for autoload_name in ["EventBus", "Balance", "Settings"]:
		assert_true(root.has_node(autoload_name), "autoload %s is missing" % autoload_name)


func test_rover_resource_loads() -> void:
	var rover := Balance.vehicle(&"rover")
	assert_true(rover != null, "rover.tres is not loaded")
	if rover == null:
		return
	assert_eq(rover.hp_max, 100)
	assert_eq(rover.fuel_max, 100.0)
	assert_eq(rover.cargo_slots, 10)


func test_physics_settings() -> void:
	assert_eq(Engine.physics_ticks_per_second, 60)
	assert_true(ProjectSettings.get_setting("physics/common/physics_interpolation"), "physics interpolation is off")


func test_renderer_is_compatibility() -> void:
	assert_eq(ProjectSettings.get_setting("rendering/renderer/rendering_method"), "gl_compatibility")
