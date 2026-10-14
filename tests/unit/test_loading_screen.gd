extends TestCase
## Экран загрузки: прогресс не идёт назад, по окончании экран гаснет и уходит.


func test_progress_is_monotonic_and_finish_frees() -> void:
	var screen := LoadingScreen.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(screen)
	screen.set_progress(0.5, "сборка мира")
	screen.set_progress(0.3, "прогрев графики")
	assert_near(screen._shown, 0.5, 1e-6, "progress never goes back")
	assert_eq(screen._text, "прогрев графики", "the stage text follows the latest call")
	screen.set_progress(2.0, "трюм")
	assert_near(screen._shown, 1.0, 1e-6, "clamped to 1")
	screen.finish()
	for _i in 30:
		screen._process(1.0 / 30.0)
	assert_true(screen.is_queued_for_deletion(), "the screen fades out and frees itself")
