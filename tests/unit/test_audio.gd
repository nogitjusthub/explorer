extends TestCase
## Звуки: синтез порциями (Sfx) даёт тот же звук, что целиком, порция — доли миллисекунды, фоновая
## очередь держит бюджет кадра, а звук, понадобившийся раньше, досинтезируется сразу; гул пылевой бури
## (AudioDirector) стихает с концом бури и не воскресает от сводки плотности после него.


func test_chunked_synthesis_matches_whole() -> void:
	# Обычный звук, петля со швом, самый тяжёлый генератор (порции мельче).
	for key: StringName in [&"hit", &"pager", &"wind", &"toggle"]:
		var whole := Sfx.job(key).finish()
		var job := Sfx.job(key)
		var steps := 0
		while job.wav == null and steps < 100000:
			job.step()
			steps += 1
		assert_true(steps > 5, "%s: синтез по шагам (%d)" % [key, steps])
		assert_true(job.wav != null and job.wav.data == whole.data, "%s: тот же звук" % key)
		assert_eq(job.wav.loop_mode, whole.loop_mode, "%s: петля" % key)
		assert_eq(job.wav.loop_end, whole.loop_end, "%s: конец петли" % key)


func test_steps_are_small() -> void:
	# Люк трюма — десятки синусов на сэмпл: целиком ~150 мс, порция — доли миллисекунды (в браузере
	# в разы дольше, потому и порции). Редкий выброс (планировщик ОС) допустим.
	var job := Sfx.job(&"hatch_lift")
	var slow := 0
	var steps := 0
	while job.wav == null:
		var t0 := Time.get_ticks_usec()
		job.step()
		if Time.get_ticks_usec() - t0 > 2000:
			slow += 1
		steps += 1
	assert_true(steps > 100, "много порций (%d)" % steps)
	assert_true(slow <= 2, "порций дольше 2 мс: %d" % slow)


func test_queue_keeps_budget_and_finishes_on_demand() -> void:
	Sfx.prepare([&"tractor"], true)
	assert_false(Sfx.is_ready(&"tractor"), "ещё не синтезирован")
	var t0 := Time.get_ticks_usec()
	assert_true(Sfx.pump(1000), "за 1 мс очередь не кончилась")
	assert_true(Time.get_ticks_usec() - t0 < 4000, "бюджет держится (с запасом на одну порцию)")
	assert_false(Sfx.is_ready(&"tractor"), "луч захвата (~30 мс) за 1 мс не готов")
	var wav := Sfx.named(&"tractor")             # понадобился — досинтезируется сразу
	assert_true(Sfx.is_ready(&"tractor"), "готов")
	assert_true(wav.data == Sfx.job(&"tractor").finish().data, "начатый в фоне и досинтезированный — тот же звук")
	assert_true(Sfx.named(&"tractor") == wav, "второй раз — из кэша")


func test_dust_hum_stops_with_the_storm() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var audio := AudioDirector.new()
	tree.root.add_child(audio)
	var hum := audio.get_child(audio.get_child_count() - 1) as AudioStreamPlayer
	EventBus.weather_changed.emit(&"dust", 0.0)
	assert_false(hum.playing, "сводка плотности гул не включает")
	EventBus.threat_telegraphed.emit(&"dust", Vector3.ZERO, 0.0, Vector2.RIGHT)
	assert_true(hum.playing, "буря идёт — гудит (вдали — тихо)")
	EventBus.weather_changed.emit(&"dust", 1.0)
	var loud := hum.volume_db
	EventBus.weather_changed.emit(&"dust", 0.0)
	assert_true(loud > hum.volume_db + 10.0, "в массе — громче, чем вдали")
	EventBus.threat_ended.emit(&"dust")
	EventBus.weather_changed.emit(&"dust", 0.0)   # сводка после конца (порядок сигналов не важен)
	assert_false(hum.playing, "буря кончилась — гул стих и не воскрес")
	audio.free()
