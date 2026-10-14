class_name DevTools
extends Node
## Отладочные режимы запуска: бенчмарк, серия снимков, отладочный снимок (F12 на ПК и по таймеру).
##
## Параметры командной строки (после «--»; справка — play.cmd --help):
##   Мир и машина:
##     --seed=N           задаёт мир (по умолчанию — от времени)
##     --vehicle=ID       машина: rover, tank, hover (по умолчанию — последняя выбранная)
##     --spawn=X,Z        старт в точке мира вместо площадки
##     --no-drop          без сцены десанта: машина сразу на площадке старта
##     --fuel=N           топлива в начале забега, единиц
##     --no-dunes         мир без дюнных полей (сравнить то же место с дюнами и без)
##   Камера и экран:
##     --zoom=N           камера в N раз крупнее (0.75 — мельче)
##     --no-shadows       без теней
##     --debug            отладочный оверлей виден сразу (иначе — по F3)
##   Угрозы:
##     --no-threats       без угроз (погода, землетрясения, смерчи)
##     --no-fauna         без фауны
##     --threat=N         уровень угрозы не ниже N (1–6)
##     --event=K@S,...    событие K на S-й секунде: storm, strike, fog, acid, dust, murk, tornado,
##                          quake, whirlpool, hoppers, worm, shellback, shark, ray, nessie
##                          (strike — молния в машину; murk — непогода по биому; червь — если рядом
##                          песок или равнина; водные — если рядом зыбун, мелкая или глубокая вода;
##                          опечатка в имени — предупреждение в консоли)
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
##     --hunt             автопилот таранит ближайшего зверя (скакуны, панцирник, илозуб), если он рядом
##     --bench=S          бенчмарк S секунд с автопилотом, отчёт и выход
##     --log-slow[=MS]    печатать кадры дольше MS мс (20) по часам, с первого кадра: игра, генерация,
##                          отрисовка; метки этапов (mark …) (в вебе — ?log-slow в адресе, консоль F12)
##     --shader-audit     печатать материалы с новым ключом шейдера, появившиеся после прогрева
##                          (их шейдер прогрев не покрыл — первое появление дёрнет кадр в браузере)
##     --shots=N          N скриншотов в build\shots, интервал --shot-every=S (3 с)
##     --snapshot-at=S    отладочный снимок (как по F12) через S секунд
## В веб-сборке те же параметры берутся из адреса страницы: ?seed=7&bench=30 — в debug-экспорте
## (export_web.ps1 -Debug) и в release на локальном сервере (127.0.0.1, localhost — замеры web_bench.mjs).
## Опубликованная release-сборка из адреса берёт лишь диагностику — ?log-slow и ?shader-audit; прочее (бак,
## угроза, автопилот, события, seed…) отбрасывает со строкой в консоли.
## Результаты бенчмарка и снимки уходят POST-запросами на /log и /shot (tools/scripts/web_server.py).

## Имена событий --event: ThreatDirector._start и FaunaDirector._force.
const EVENT_KINDS: Array[StringName] = [&"storm", &"strike", &"fog", &"acid", &"dust", &"murk", &"tornado",
		&"quake", &"whirlpool", &"hoppers", &"worm", &"shellback", &"shark", &"ray", &"nessie"]
## Параметры адреса страницы, которые принимает release-сборка в вебе: только диагностика кадра.
const WEB_RELEASE_PARAMS: Array[String] = ["log-slow", "shader-audit"]
## Хосты, с которых release-сборка в вебе принимает все параметры (локальные замеры).
const LOCAL_HOSTS: Array[String] = ["127.0.0.1", "localhost"]

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
var holding := false                   ## идёт экран загрузки: часы сценариев (--press, --shots, --bench…) стоят
var _elapsed := 0.0
var _max_delta := 0.0
var _last_usec := 0                    ## Time.get_ticks_usec() прошлого кадра — длительность кадра по часам
var _wall := PackedFloat32Array()      ## длительности кадров по часам (мс) для отчёта бенчмарка
var _slow_ms := 20.0                   ## --log-slow=MS
var _throttle_sum := 0.0
var _physics_frames := 0
var _chunks_built := 0
var _slow_frames := 0
var _physics_seen := 0                 ## Engine.get_physics_frames() в прошлом кадре — сколько шагов физики было
var script_usec := 0                   ## шаги игры (GameFlow) с прошлого кадра, мкс — копит main
var _builds := 0                       ## сборок чанков (в т. ч. пересборок) с прошлого кадра — для --log-slow
var _audit_new: Array[Node] = []       ## --shader-audit: узлы, добавленные с прошлого кадра
var _audit_keys := {}                  ## ключи шейдеров, уже виденные в игровом мире
var _audit_listed := false
var _objects_at_start := 0
var _presses: Array[Dictionary] = []    ## {action, at}
var _clicks: Array[Dictionary] = []     ## {pos (пиксели рендера), at}
var _mouse_up: Array[Vector2] = []
var _release: Array[StringName] = []
var _events: Array[Dictionary] = []     ## --event, разобранный один раз (предупреждения — тоже раз)


func _init(parsed_args: Dictionary) -> void:
	args = parsed_args
	name = "DevTools"
	process_mode = Node.PROCESS_MODE_ALWAYS     # снимки, нажатия и F12 работают и на паузе
	_events = parse_events(String(args.get("event", "")))
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


func _ready() -> void:
	if streamer != null:
		streamer.chunk_built.connect(func(_c: Vector2i) -> void: _builds += 1)
	if args.has("log-slow"):
		if String(args["log-slow"]).is_valid_float():
			_slow_ms = float(args["log-slow"])
		# Время отрисовки кадра (ЦП и ГП) — чтобы отличить тормоза игры от тормозов рендера и браузера.
		RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if args.has("shader-audit"):
		get_tree().node_added.connect(func(n: Node) -> void:
			if n is GeometryInstance3D:
				_audit_new.append(n))
		_audit_collect(get_tree().root)      # уже построенное (мир, машина) — до конца прогрева, молча


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


## Принудительные события из --event=storm@5,quake@12 — каждому директору свой список (он его расходует).
func forced_events() -> Array[Dictionary]:
	return _events.duplicate(true)


## Разбор --event: K@S через запятую. Неизвестное имя (опечатка) или запись не по форме — предупреждение
## в консоли, запись пропускается: иначе событие молча не случилось бы.
static func parse_events(spec: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in spec.split(",", false):
		var parts := item.split("@")
		if parts.size() != 2 or not parts[1].is_valid_float():
			push_warning("DevTools: --event item '%s' is not KIND@SECONDS — skipped" % item)
			continue
		var kind := StringName(parts[0])
		if not EVENT_KINDS.has(kind):
			push_warning("DevTools: --event: unknown event '%s' — skipped (known: %s)" % [kind,
					", ".join(PackedStringArray(EVENT_KINDS))])
			continue
		result.append({"kind": kind, "at": float(parts[1])})
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
	if args.has("hunt") and fauna != null:
		pilot.prey = fauna.nearest_prey
	return pilot


## Начало забега: от этого числа объектов считается утечка в отчёте бенчмарка.
func mark_start() -> void:
	_objects_at_start = int(Performance.get_monitor(Performance.OBJECT_COUNT))
	streamer.chunk_ready.connect(func(_c: Vector2i) -> void: _chunks_built += 1)


func _physics_process(_dt: float) -> void:
	_physics_frames += 1
	_throttle_sum += vehicle.state.throttle


## --shader-audit: ключи шейдеров узлов, добавленных в игровой мир. До конца прогрева (и в нём самом) —
## запоминаем молча; после — новый ключ печатаем с путём узла: его шейдер прогрев не покрыл.
func _audit() -> void:
	var world := get_viewport().world_3d
	for n in _audit_new:
		if not is_instance_valid(n) or not n.is_inside_tree() or (n as Node3D).get_world_3d() != world:
			continue
		var instanced := n is MultiMeshInstance3D or n is CPUParticles3D
		for m in ShaderCache.materials_of(n):
			var key := ShaderCache.key_of(m, instanced)
			if _audit_keys.has(key):
				continue
			_audit_keys[key] = true
			if ShaderCache.warmed:
				print("shader-audit: not warmed at %.1f s: %s\n    %s" % [_elapsed, n.get_path(), key])
	_audit_new.clear()
	if ShaderCache.warmed and not _audit_listed:
		_audit_listed = true
		var keys: Array = _audit_keys.keys()
		keys.sort()
		print("shader-audit: %d shader keys after warmup:\n    %s" % [keys.size(), "\n    ".join(keys)])


func _audit_collect(n: Node) -> void:
	if n is GeometryInstance3D:
		_audit_new.append(n)
	for c in n.get_children():
		_audit_collect(c)


## Снимок по F12 — только на ПК: в браузере F12 открывает консоль, а снимок там всё равно некуда
## сохранить (его принимает только локальный web_server.py — для этого есть --snapshot-at).
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"debug_snapshot") and not OS.has_feature("web"):
		snapshot()


## Отладочный снимок (F12): скриншот, карта, состояние машины, дамп тайлов — см. DebugSnapshot.
func snapshot() -> void:
	var dir := DebugSnapshot.capture(get_viewport(), vehicle, query, run_seed, rig.quarter())
	var where := "отправлен на сервер" if dir.is_empty() else dir.replace(ProjectSettings.globalize_path("res://"), "")
	toast.show_message("Снимок: " + where)
	print("debug snapshot: " + (dir if not dir.is_empty() else "web"))


func _process(dt: float) -> void:
	_frames += 1
	if not holding:
		_elapsed += dt
	# Кадр — по часам: dt движок урезает (не больше 8 шагов физики), и многосекундный кадр компиляции шейдеров
	# выглядел бы как «130 мс».
	var now := Time.get_ticks_usec()
	var wall := (now - _last_usec) / 1000.0 if _last_usec > 0 else dt * 1000.0
	_last_usec = now
	if _frames > 10:
		_max_delta = maxf(_max_delta, wall / 1000.0)
		_wall.append(wall)
		if wall > 20.0:
			_slow_frames += 1
	if args.has("log-slow") and wall > _slow_ms:
		_log_slow(dt, wall)
	_physics_seen = Engine.get_physics_frames()
	script_usec = 0
	_builds = 0
	if not _audit_new.is_empty():
		_audit()
	if holding:
		return                             # сценарий — от конца загрузки
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
	var f := frame_stats(_wall)
	_report("bench: wall frames — p95 %.1f ms, p99 %.1f ms, max %.1f ms, > 33 ms: %d, > 50 ms: %d" % [
		f["p95"], f["p99"], f["max"], f["over33"], f["over50"]])
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
		_report("bench: fauna — packs %d, worms %d, shellbacks %d, mire sharks %d, stargazers %d, nessies %d, hits on the vehicle %d, rams %d, killed %d" % [
			fs["packs"], fs["worms"], fs["shellbacks"], fs["sharks"], fs["rays"], fs["nessies"], fs["hits"],
			fs["rams"], fs["kills"]])
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


## Медленный кадр и на что ушло время: скрипты кадра (process), физика (сколько шагов), задачи генерации,
## отрисовка, объекты и память. Если всё это мало, а кадр долгий — тормозит не игра, а движок или
## браузер (компиляция шейдеров, сборка мусора, звук, драйвер). wall — по часам, dt — урезанный движком;
## «at» — время игры и время с запуска (часы). В вебе при бенчмарке строка уходит и на локальный сервер.
func _log_slow(dt: float, wall: float) -> void:
	var vp := get_viewport().get_viewport_rid()
	var line := "slow frame %.1f ms (dt %.1f) at %.2f s (%.2f s since start) — game steps %.1f ms ×%d, jobs %.1f ms, chunks built %d, render cpu %.1f / gpu %.1f ms, draws %d, objects %d" % [
		wall, dt * 1000.0, _elapsed, Time.get_ticks_msec() / 1000.0,
		script_usec / 1000.0, Engine.get_physics_frames() - _physics_seen,
		scheduler.last_frame_usec / 1000.0 if scheduler != null else 0.0, _builds,
		RenderingServer.viewport_get_measured_render_time_cpu(vp),
		RenderingServer.viewport_get_measured_render_time_gpu(vp),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		Performance.get_monitor(Performance.OBJECT_COUNT)]
	print(line)
	if OS.has_feature("web") and _bench_time > 0.0:
		_web_post("/log", line, false)


## Статистика длительностей кадров (мс): p95, p99, максимум, число кадров дольше 33 и 50 мс.
static func frame_stats(frames: PackedFloat32Array) -> Dictionary:
	var sorted := frames.duplicate()
	sorted.sort()
	var n := sorted.size()
	var at := func(q: float) -> float: return sorted[clampi(ceili(q * n) - 1, 0, n - 1)] if n > 0 else 0.0
	var over33 := 0
	var over50 := 0
	for v in sorted:
		over33 += int(v > 33.0)
		over50 += int(v > 50.0)
	return {"p95": at.call(0.95), "p99": at.call(0.99), "max": sorted[n - 1] if n > 0 else 0.0,
			"over33": over33, "over50": over50}


## Метка этапа загрузки и игры (замеры): строка «mark NAME T ms» в консоли; в браузере — ещё
## performance.mark('ex:NAME') и window.__exPhase (их читает зонд tools/web/gl_probe.js). Дёшево — можно всегда.
static func mark(mark_name: String) -> void:
	print("mark %s %d ms" % [mark_name, Time.get_ticks_msec()])
	if OS.has_feature("web"):
		JavaScriptBridge.eval("performance.mark('ex:%s'); window.__exPhase = '%s';" % [mark_name, mark_name])


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
		var host: Variant = JavaScriptBridge.eval("window.location.hostname", true)
		if search is String:
			result.merge(url_params(search, release_filter(OS.is_debug_build(), String(host))), true)
	return result


## Отбрасывать ли из адреса всё, кроме диагностики: да — в release-сборке на чужом хосте (опубликованная игра);
## debug-экспорт и локальный сервер замеров (LOCAL_HOSTS) берут всё.
static func release_filter(debug_build: bool, host: String) -> bool:
	return not debug_build and not LOCAL_HOSTS.has(host)


## Параметры из адреса страницы (window.location.search: «?seed=7&bench=30»). release — опубликованная
## сборка: из адреса берутся только WEB_RELEASE_PARAMS, прочие отбрасываются (строка в консоли браузера).
static func url_params(search: String, release: bool) -> Dictionary:
	var result := {}
	var ignored := PackedStringArray()
	for pair in search.trim_prefix("?").split("&", false):
		var kv := pair.split("=", true, 1)
		if release and not WEB_RELEASE_PARAMS.has(kv[0]):
			ignored.append(kv[0])
			continue
		result[kv[0]] = kv[1] if kv.size() > 1 else ""
	if not ignored.is_empty():
		print("DevTools: release build ignores URL parameters %s (debug export only; allowed: %s)" % [
				", ".join(ignored), ", ".join(PackedStringArray(WEB_RELEASE_PARAMS))])
	return result
