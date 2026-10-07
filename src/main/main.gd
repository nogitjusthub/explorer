extends Node
## Корень игрового цикла (GameFlow). Веха M0: бесконечный мир, ровер, камера, отладочный оверлей.
##
## Параметры командной строки (после «--»):
##   --seed=N          seed мира (по умолчанию — от времени);
##   --autopilot       машина едет сама;
##   --bench=S         автопилот S секунд, затем печать статистики и выход;
##   --shots=N         автопилот, N снимков экрана в build/shots/ (нужен оконный режим), затем выход;
##   --shot-every=S    интервал между снимками, секунд (по умолчанию 3);
##   --no-shadows      без теней (слабые машины, диагностика);
##   --spawn=X,Z       старт в точке мира вместо площадки (отладка);
##   --course=D        автопилот едет строго по курсу D градусов (0 — +x, 90 — +z), без объезда;
##   --snapshot-at=S   отладочный снимок (как по F12) через S секунд;
##   --zoom=N          камера в N раз крупнее (отладка).
## В веб-сборке те же параметры берутся из адреса страницы: ?seed=7&bench=30. Результаты бенчмарка
## и снимки уходят POST-запросами на /log и /shot (tools/scripts/web_server.py).

const VIS_RADIUS_CLEAR := 1000.0

var run_seed: int
var terrain: TerrainData
var generator: TerrainGenerator
var query: TerrainQuery
var scheduler: JobScheduler
var streamer: WorldStreamer
var vehicle: Vehicle
var rig: IsoCameraRig

var _args := {}
var _bench_time := -1.0
var _shots_left := 0
var _shot_every := 3.0
var _shot_timer := 0.0
var _shot_index := 0
var _frames := 0
var _elapsed := 0.0
var _max_delta := 0.0
var _throttle_sum := 0.0
var _physics_frames := 0
var _chunks_built := 0
var _slow_frames := 0
var _objects_at_start := 0
var _spawn := Vector2.ZERO
var _deaths := 0
var _toast: Toast
var _snapshot_at := -1.0


func _ready() -> void:
	_args = _parse_args()
	run_seed = int(_args.get("seed", str(int(Time.get_unix_time_from_system()) % 100000)))
	print("Explorer M0 — seed %d (Godot %s)" % [run_seed, Engine.get_version_info().string])
	_build_world()
	if _args.has("bench"):
		_bench_time = float(_args["bench"])
	if _args.has("snapshot-at"):
		_snapshot_at = float(_args["snapshot-at"])
	if _args.has("shots"):
		_shots_left = int(_args["shots"])
		_shot_every = float(_args.get("shot-every", "3"))
		_shot_timer = _shot_every
	if _args.has("autopilot") or _bench_time > 0.0 or _shots_left > 0:
		vehicle.autopilot = Autopilot.new(DetRng.unit(run_seed, 0, 0, 900) * TAU, query, vehicle.cls)
		if _args.has("course"):
			vehicle.autopilot = Autopilot.new(deg_to_rad(float(_args["course"])), query, vehicle.cls)
			vehicle.autopilot.fixed_course = true
		_begin()
	else:
		vehicle.control_enabled = false
		var start := StartScreen.new()
		start.started.connect(_begin)
		add_child(start)


func _build_world() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.27, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.52, 0.72)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -70.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.light_energy = 1.25
	sun.shadow_enabled = not _args.has("no-shadows")
	# Одна ортогональная карта теней на небольшую дальность — плотнее тексели. Смещение по нормали
	# берётся из вершинных нормалей меша (ChunkMesher их пишет), иначе грани затеняют сами себя.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 2.0
	add_child(sun)

	terrain = TerrainData.new()
	generator = TerrainGenerator.new(run_seed, TerrainParams.new())
	query = TerrainQuery.new(terrain)
	scheduler = JobScheduler.new()
	scheduler.name = "JobScheduler"
	add_child(scheduler)
	streamer = WorldStreamer.new(terrain, generator, query, scheduler, TerrainMaterials.new())
	streamer.chunk_ready.connect(func(_c: Vector2i) -> void: _chunks_built += 1)
	add_child(streamer)

	var spawn := _spawn_point()
	var t0 := Time.get_ticks_usec()
	streamer.preload_around(spawn)
	print("preload: %d chunks in %d ms" % [streamer.loaded_count(), (Time.get_ticks_usec() - t0) / 1000])

	vehicle = Vehicle.new(Balance.vehicle(&"rover"), query)
	add_child(vehicle)
	vehicle.place(spawn, -PI * 0.75)
	vehicle.died.connect(_on_vehicle_died)
	_spawn = spawn

	rig = IsoCameraRig.new()
	rig.target = vehicle
	rig.zoom = float(_args.get("zoom", "1"))
	add_child(rig)
	vehicle.camera = rig.camera

	_toast = Toast.new()
	add_child(_toast)

	var overlay := DebugOverlay.new()
	overlay.run_seed = run_seed
	overlay.vehicle = vehicle
	overlay.streamer = streamer
	overlay.scheduler = scheduler
	overlay.query = query
	add_child(overlay)

	RenderingServer.global_shader_parameter_set(&"vis_radius", VIS_RADIUS_CLEAR)


## Точка десанта M0: центр ближайшей к началу координат площадки челнока (ровно и сухо).
func _spawn_point() -> Vector2:
	if _args.has("spawn"):
		var xz := (_args["spawn"] as String).split(",")
		return Vector2(float(xz[0]) + 0.5, float(xz[1]) + 0.5)
	for r in 4:
		for bz in range(-r, r + 1):
			for bx in range(-r, r + 1):
				var pad := generator.pad_of_block(Vector2i(bx, bz))
				if pad.z != TerrainGenerator.NO_PAD:
					return Vector2(pad.x + 0.5, pad.y + 0.5)
	return Vector2(0.5, 0.5)


## Гибель (M0: пока только «утонул»). Полный экран итога — в M1a.
func _on_vehicle_died(cause: StringName) -> void:
	_deaths += 1
	print("vehicle died: %s" % cause)
	if vehicle.autopilot != null:
		vehicle.place(_spawn, -PI * 0.75)   # бенчмарк продолжается
		return
	vehicle.control_enabled = false
	var screen := StartScreen.new()
	screen.text = "МАШИНА УТОНУЛА\n\nНажмите любую клавишу, чтобы начать заново"
	screen.started.connect(func() -> void: get_tree().reload_current_scene())
	add_child(screen)


func _begin() -> void:
	_objects_at_start = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	vehicle.control_enabled = true
	vehicle.engine.play()


func _physics_process(_dt: float) -> void:
	streamer.update_focus(vehicle.state.pos, vehicle.state.vel)
	var p := vehicle.state.pos
	RenderingServer.global_shader_parameter_set(&"vis_center", Vector3(p.x, vehicle.state.y, p.y))
	_physics_frames += 1
	_throttle_sum += vehicle.state.throttle


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_snapshot"):
		_debug_snapshot()


## Отладочный снимок (F12): скриншот, карта, состояние машины, дамп тайлов — см. DebugSnapshot.
func _debug_snapshot() -> void:
	var dir := DebugSnapshot.capture(get_viewport(), vehicle, query, run_seed, rig.quarter())
	var where := "отправлен на сервер" if dir.is_empty() else dir.replace(ProjectSettings.globalize_path("res://"), "")
	_toast.show_message("Снимок: " + where)
	print("debug snapshot: " + (dir if not dir.is_empty() else "web"))


func _process(dt: float) -> void:
	_frames += 1
	_elapsed += dt
	if _frames > 10:
		_max_delta = maxf(_max_delta, dt)
		if dt > 0.02:
			_slow_frames += 1
	if _snapshot_at > 0.0 and _elapsed >= _snapshot_at:
		_snapshot_at = -1.0
		_debug_snapshot()
	if _shots_left > 0:
		_shot_timer -= dt
		if _shot_timer <= 0.0:
			_shot_timer = _shot_every
			_take_shot()
	if _bench_time > 0.0 and _elapsed >= _bench_time:
		_bench_time = -1.0
		_print_bench()
		_finish()


func _take_shot() -> void:
	# Кадр рендера 480×320 увеличиваем вдвое без сглаживания — как он выглядит в окне.
	var image := get_viewport().get_texture().get_image()
	image.resize(image.get_width() * 2, image.get_height() * 2, Image.INTERPOLATE_NEAREST)
	if OS.has_feature("web"):
		_web_post("/shot", Marshalls.raw_to_base64(image.save_png_to_buffer()), true)
	else:
		var dir := ProjectSettings.globalize_path("res://build/shots")
		DirAccess.make_dir_recursive_absolute(dir)
		var path := dir.path_join("shot_%02d.png" % _shot_index)
		image.save_png(path)
		print("shot " + path)
	_shot_index += 1
	_shots_left -= 1
	if _shots_left == 0 and _bench_time <= 0.0:
		_finish()


## Конец автоматического прогона. В браузере выход из движка бессмыслен (и ломает веб-аудио) —
## там просто останавливаем машину.
func _finish() -> void:
	if OS.has_feature("web"):
		vehicle.control_enabled = false
	else:
		get_tree().quit()


func _print_bench() -> void:
	var avg_throttle := _throttle_sum / maxi(_physics_frames, 1)
	var cls := vehicle.cls
	var fuel_per_min := VehicleKinematics.fuel_per_second(cls, avg_throttle) * 60.0
	_report("bench (%s, seed %d): %.1f s, %d frames, avg %.1f FPS, worst frame %.1f ms, frames > 20 ms: %d, worst job slice %.1f ms" % [
		"web" if OS.has_feature("web") else "desktop", run_seed, _elapsed, _frames, _frames / _elapsed,
		_max_delta * 1000.0, _slow_frames, scheduler.max_frame_usec / 1000.0])
	_report("bench: chunks built %d, loaded now %d, distance %.0f tiles, avg speed %.2f tiles/s" % [
		_chunks_built, streamer.loaded_count(), vehicle.total_distance, vehicle.total_distance / _elapsed])
	_report("bench: avg throttle %.2f → fuel %.1f u/min → full tank of %s lasts %.1f min" % [
		avg_throttle, fuel_per_min, cls.id, cls.fuel_max / fuel_per_min])
	_report("bench: render — draw calls %d, primitives %d, objects in frame %d, video memory %.0f MB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_report("bench: objects %d (at start %d), static memory %.1f MB, terrain diffs %d, deaths %d" % [
		Performance.get_monitor(Performance.OBJECT_COUNT), _objects_at_start,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, terrain.diffs.size(), _deaths])


func _report(line: String) -> void:
	print(line)
	if OS.has_feature("web"):
		_web_post("/log", line, false)


## POST на локальный сервер веб-сборки. base64 — для двоичных данных (снимки).
func _web_post(path: String, payload: String, base64: bool) -> void:
	var body := "Uint8Array.from(atob('%s'), c => c.charCodeAt(0))" % payload if base64 else JSON.stringify(payload)
	JavaScriptBridge.eval("fetch('%s', {method: 'POST', body: %s})" % [path, body])


func _parse_args() -> Dictionary:
	var result := {}
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv := arg.trim_prefix("--").split("=", true, 1)
		result[kv[0]] = kv[1] if kv.size() > 1 else ""
	if OS.has_feature("web"):
		var search: Variant = JavaScriptBridge.eval("window.location.search", true)
		if search is String:
			for pair in (search as String).trim_prefix("?").split("&", false):
				var kv := pair.split("=", true, 1)
				result[kv[0]] = kv[1] if kv.size() > 1 else ""
	return result
