class_name DevTools
extends Node
## Отладочные режимы запуска: бенчмарк, серия снимков, отладочный снимок (F12 и по таймеру).
##
## Параметры командной строки (после «--»):
##   --seed=N          seed мира (по умолчанию — от времени);
##   --autopilot       машина едет сама, забег бесконечный (гибель — возрождение, пустой бак — дозаправка);
##   --bench=S         автопилот S секунд, затем печать статистики и выход;
##   --shots=N         автопилот, N снимков экрана в build/shots/ (нужен оконный режим), затем выход;
##   --shot-every=S    интервал между снимками, секунд (по умолчанию 3);
##   --no-shadows      без теней (слабые машины, диагностика);
##   --spawn=X,Z       старт в точке мира вместо площадки (отладка);
##   --course=D        автопилот едет строго по курсу D градусов (0 — +x, 90 — +z), без объезда;
##   --snapshot-at=S   отладочный снимок (как по F12) через S секунд;
##   --zoom=N          камера в N раз крупнее (отладка);
##   --debug           отладочный оверлей виден сразу (иначе — по F3);
##   --idle            без стартового экрана и автопилота: машина стоит (проверка челноков, снимки);
##   --shuttle-in=S    первый челнок садится через S секунд (вместо 90);
##   --shuttle-dist=D  площадка челнока на дистанции D тайлов (0 — ближайшая, обычно площадка старта);
##   --fuel=N          топлива в начале забега N единиц;
##   --press=A@S,...   нажать действие A на S-й секунде (radio@8,move_right@9 — сценарии без рук).
## В веб-сборке те же параметры берутся из адреса страницы: ?seed=7&bench=30. Результаты бенчмарка
## и снимки уходят POST-запросами на /log и /shot (tools/scripts/web_server.py).

var args := {}
var run_seed: int
var vehicle: Vehicle
var streamer: WorldStreamer
var scheduler: JobScheduler
var terrain: TerrainData
var query: TerrainQuery
var rig: IsoCameraRig
var toast: Toast
var deaths := 0
var pickups_collected := 0
var run: RunState                  ## текущий забег (у автопилота после гибели начинается новый)

var _bench_time := -1.0
var _shots_left := 0
var _shot_every := 3.0
var _shot_timer := 0.0
var _shot_index := 0
var _snapshot_at := -1.0
var _frames := 0
var _elapsed := 0.0
var _max_delta := 0.0
var _throttle_sum := 0.0
var _physics_frames := 0
var _chunks_built := 0
var _slow_frames := 0
var _objects_at_start := 0
var _presses: Array[Dictionary] = []    ## {action, at}
var _release: Array[StringName] = []


func _init(parsed_args: Dictionary) -> void:
	args = parsed_args
	name = "DevTools"
	if args.has("bench"):
		_bench_time = float(args["bench"])
	if args.has("snapshot-at"):
		_snapshot_at = float(args["snapshot-at"])
	if args.has("shots"):
		_shots_left = int(args["shots"])
		_shot_every = float(args.get("shot-every", "3"))
		_shot_timer = _shot_every
	for item in String(args.get("press", "")).split(",", false):
		var parts := item.split("@")
		if parts.size() == 2:
			_presses.append({"action": StringName(parts[0]), "at": float(parts[1])})


## Нужен ли автопилот (явно или ради бенчмарка и снимков; --idle — без него).
func wants_autopilot() -> bool:
	return not args.has("idle") and (args.has("autopilot") or _bench_time > 0.0 or _shots_left > 0)


## Начать забег сразу, без стартового экрана.
func skips_start() -> bool:
	return wants_autopilot() or args.has("idle")


## Правки баланса для отладки (на копии правил).
func tweak_rules(rules: BalanceRules) -> BalanceRules:
	if not args.has("shuttle-in") and not args.has("shuttle-dist"):
		return rules
	var r := rules.duplicate() as BalanceRules
	r.shuttle_interval_base = float(args.get("shuttle-in", r.shuttle_interval_base))
	r.shuttle_dist_base = float(args.get("shuttle-dist", r.shuttle_dist_base))
	return r


func tweak_run(run_state: RunState) -> void:
	if args.has("fuel"):
		run_state.fuel = float(args["fuel"])


func make_autopilot() -> Autopilot:
	var course := DetRng.unit(run_seed, 0, 0, 900) * TAU
	if args.has("course"):
		course = deg_to_rad(float(args["course"]))
	var pilot := Autopilot.new(course, query, vehicle.cls)
	pilot.fixed_course = args.has("course")
	return pilot


## Начало забега: от этого числа объектов считается утечка в отчёте бенчмарка.
func mark_start() -> void:
	_objects_at_start = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	streamer.chunk_ready.connect(func(_c: Vector2i) -> void: _chunks_built += 1)


func _physics_process(_dt: float) -> void:
	_physics_frames += 1
	_throttle_sum += vehicle.state.throttle


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_snapshot"):
		snapshot()


## Отладочный снимок (F12): скриншот, карта, состояние машины, дамп тайлов — см. DebugSnapshot.
func snapshot() -> void:
	var dir := DebugSnapshot.capture(get_viewport(), vehicle, query, run_seed, rig.quarter())
	var where := "отправлен на сервер" if dir.is_empty() else dir.replace(ProjectSettings.globalize_path("res://"), "")
	toast.show_message("Снимок: " + where)
	print("debug snapshot: " + (dir if not dir.is_empty() else "web"))


func _process(dt: float) -> void:
	_frames += 1
	_elapsed += dt
	if _frames > 10:
		_max_delta = maxf(_max_delta, dt)
		if dt > 0.02:
			_slow_frames += 1
	for action in _release:
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up)
	_release.clear()
	while not _presses.is_empty() and _elapsed >= _presses[0]["at"]:
		var press: Dictionary = _presses.pop_front()
		var ev := InputEventAction.new()
		ev.action = press["action"]
		ev.pressed = true
		Input.parse_input_event(ev)
		_release.append(press["action"])
		print("press %s at %.1f s" % [press["action"], _elapsed])
	if _snapshot_at > 0.0 and _elapsed >= _snapshot_at:
		_snapshot_at = -1.0
		snapshot()
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
	_report("bench: pickups collected %d; current run: hp %d, fuel %.0f, cargo %d slots / %d pts, score %d" % [
		pickups_collected, run.hp, run.fuel, run.cargo_slots_used(), run.cargo_value(), run.score()])
	_report("bench: render — draw calls %d, primitives %d, objects in frame %d, video memory %.0f MB" % [
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0])
	_report("bench: objects %d (at start %d), static memory %.1f MB, terrain diffs %d, deaths %d" % [
		Performance.get_monitor(Performance.OBJECT_COUNT), _objects_at_start,
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, terrain.diffs.size(), deaths])


func _report(line: String) -> void:
	print(line)
	if OS.has_feature("web"):
		_web_post("/log", line, false)


## POST на локальный сервер веб-сборки. base64 — для двоичных данных (снимки).
func _web_post(path: String, payload: String, base64: bool) -> void:
	var body := "Uint8Array.from(atob('%s'), c => c.charCodeAt(0))" % payload if base64 else JSON.stringify(payload)
	JavaScriptBridge.eval("fetch('%s', {method: 'POST', body: %s})" % [path, body])


static func parse_args() -> Dictionary:
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
