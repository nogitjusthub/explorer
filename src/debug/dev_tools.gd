class_name DevTools
extends Node
## Отладочные режимы запуска: бенчмарк, серия снимков, отладочный снимок (F12 и по таймеру).
##
## Параметры командной строки (после «--»; справка — play.cmd --help):
##   Мир и машина:
##     --seed=N           задаёт мир (по умолчанию — от времени)
##     --vehicle=ID       машина: rover, tank, hover (по умолчанию — последняя выбранная)
##     --spawn=X,Z        старт в точке мира вместо площадки
##     --no-drop          без сцены десанта: машина сразу на площадке старта
##     --fuel=N           топлива в начале забега, единиц
##   Камера и экран:
##     --zoom=N           камера в N раз крупнее (0.75 — мельче)
##     --no-shadows       без теней
##     --debug            отладочный оверлей виден сразу (иначе — по F3)
##   Угрозы:
##     --no-threats       без угроз (погода, землетрясения, смерчи)
##     --no-fauna         без фауны
##     --threat=N         уровень угрозы не ниже N (1–6)
##     --event=K@S,...    событие K на S-й секунде: storm, strike, fog, acid, dust, tornado,
##                          quake, whirlpool, hoppers, worm, shellback, shark, ray, nessie
##                          (strike — молния в машину; червь — если рядом песок или равнина;
##                          водные — если рядом зыбун, мелкая или глубокая вода)
##   Сценарии без рук:
##     --idle             без стартового экрана и автопилота: машина стоит
##     --select           показать трюм с выбором машины и при --idle или --shots
##     --press=A@S,...    нажать действие A на S-й секунде: radio@8,move_right@9
##     --click=X:Y@S,...  клик (тап) в точке X,Y рендера 480×320 на S-й секунде
##     --shuttle-in=S     первый челнок садится через S секунд
##     --shuttle-dist=D   площадка челнока на дистанции D (0 — площадка старта)
##   Автопилот, бенчмарк, снимки:
##     --autopilot        машина едет сама, гибель — возрождение
##     --course=D         автопилот строго по курсу D градусов, без объезда
##     --bench=S          бенчмарк S секунд с автопилотом, отчёт и выход
##     --log-slow         печатать кадры дольше 20 мс
##     --shots=N          N скриншотов в build\shots, интервал --shot-every=S (3 с)
##     --snapshot-at=S    отладочный снимок (как по F12) через S секунд
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
var threats: ThreatDirector
var fauna: FaunaDirector

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
var _clicks: Array[Dictionary] = []     ## {pos (пиксели рендера), at}
var _mouse_up: Array[Vector2] = []
var _release: Array[StringName] = []


func _init(parsed_args: Dictionary) -> void:
	args = parsed_args
	name = "DevTools"
	process_mode = Node.PROCESS_MODE_ALWAYS     # снимки, нажатия и F12 работают и на паузе
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
	for item in String(args.get("click", "")).split(",", false):
		var parts := item.split("@")
		var xy := parts[0].split(":")
		if parts.size() == 2 and xy.size() == 2:
			_clicks.append({"pos": Vector2(float(xy[0]), float(xy[1])), "at": float(parts[1])})


## Нужен ли автопилот (явно или ради бенчмарка и снимков; --idle — без него).
func wants_autopilot() -> bool:
	return not args.has("idle") and (args.has("autopilot") or _bench_time > 0.0 or _shots_left > 0)


## Начать забег сразу, без стартового экрана (--select — показать его всё равно).
func skips_start() -> bool:
	return (wants_autopilot() or args.has("idle")) and not args.has("select")


## Правки баланса для отладки (на копии правил).
func tweak_rules(rules: BalanceRules) -> BalanceRules:
	if not args.has("shuttle-in") and not args.has("shuttle-dist"):
		return rules
	var r := rules.duplicate() as BalanceRules
	r.shuttle_interval_base = float(args.get("shuttle-in", r.shuttle_interval_base))
	r.shuttle_dist_base = float(args.get("shuttle-dist", r.shuttle_dist_base))
	return r


## Принудительные события из --event=storm@5,quake@12.
func forced_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in String(args.get("event", "")).split(",", false):
		var parts := item.split("@")
		if parts.size() == 2:
			result.append({"kind": StringName(parts[0]), "at": float(parts[1])})
	return result


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
			if args.has("log-slow"):
				print("slow frame %.1f ms at %.2f s" % [dt * 1000.0, _elapsed])
	for action in _release:
		var up := InputEventAction.new()
		up.action = action
		up.pressed = false
		Input.parse_input_event(up)
	_release.clear()
	for pos in _mouse_up:
		_click(pos, false)
	_mouse_up.clear()
	while not _clicks.is_empty() and _elapsed >= _clicks[0]["at"]:
		var c: Dictionary = _clicks.pop_front()
		_click(c["pos"], true)
		_mouse_up.append(c["pos"])
		print("click %s at %.1f s" % [c["pos"], _elapsed])
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


## Клик (или тап — касание эмулирует мышь) в точке рендера 480×320: в окне она масштабирована.
func _click(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = get_viewport().get_final_transform() * pos
	ev.global_position = ev.position
	Input.parse_input_event(ev)


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
	if threats != null:
		var st := threats.stats
		_report("bench: threats — level %d, storms %d (strikes %d), quakes %d, fog %d, acid %d, dust %d (tornadoes %d), whirlpools %d" % [
			threats.level, st["storm"], st["strikes"], st["quake"], st["fog"], st["acid"], st["dust"], st["tornado"],
			st["whirlpool"]])
	if fauna != null:
		var fs := fauna.stats
		_report("bench: fauna — packs %d, worms %d, shellbacks %d, mire sharks %d, stargazers %d, nessies %d, hits on the vehicle %d" % [
			fs["packs"], fs["worms"], fs["shellbacks"], fs["sharks"], fs["rays"], fs["nessies"], fs["hits"]])
		_report("bench: fauna alive now — %d nodes under the director" % fauna.get_child_count())
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
