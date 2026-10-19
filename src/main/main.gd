extends Node
## Корень игрового цикла (GameFlow, ARCHITECTURE §3.2): старт → забег → итог.
## Владеет RunState и связывает с ним машину, находки, челноки и HUD. Отладочные режимы запуска и
## параметры командной строки — в DevTools.

enum Phase { START, DROP, RUN, OVER, RESULTS }

const SUN_ENERGY := 1.25
const AMBIENT_ENERGY := 0.5
## Фонарь машины — точечный свет, который в мире горит всегда (днём — почти нулевой яркости): каждый объект в
## кадре задет хотя бы одним точечным светом, поэтому шейдеру нужен один вариант («с точечным светом»), а не два
## (вариант выбирается по тому, задевает ли объект такой свет). Вдвое меньше программ GPU — в браузере это
## секунды загрузки. Ночь (если будет) — та же лампа ярче: новых вариантов не появится.
const LAMP_RANGE := 48.0                 ## тайлов: весь кадр с упреждением камеры и челнок в небе
const LAMP_ENERGY := 0.001               ## днём не видно (нулевую яркость движок мог бы пропустить)
const LAMP_HEIGHT := 1.5
const EVAC_SCENE_S := 3.4         ## эвакуация: машину втягивает в челнок, он уходит вверх
const LANDING_TRIES := 40
const LANDING_DRY := 5            ## капсула садится не ближе 5 тайлов к воде (если такое место нашлось)
const SPAWN_HEADING := -PI * 0.75
const SPAWN_PAD_OFFSET := 2.0     ## без десанта машина стоит на краю площадки — в зоне погрузки, не под челноком
const LOADING_JOB_BUDGET_USEC := 30000  ## под экраном загрузки кадров не видно — мир догружается с большим бюджетом
const LOADING_SYNTH_USEC := 20000       ## …и звуки синтезируются быстрее
const SHADERS_QUIET_FRAMES := 3         ## загрузка кончается после стольких кадров без фоновой сборки шейдеров

var run_seed: int
var terrain: TerrainData
var generator: TerrainGenerator
var query: TerrainQuery
var scheduler: JobScheduler
var streamer: WorldStreamer
var vehicle: Vehicle
var rig: IsoCameraRig
var pickups: PickupField
var hud: Hud
var shuttles: ShuttleController
var threats: ThreatDirector
var fauna: FaunaDirector
var dev: DevTools
var run: RunState
var rules: BalanceRules
var phase := Phase.START
var sandbox := false               ## автопилот: забег бесконечный, гибель — возрождение

var _toast: Toast
var _pause: PauseOverlay
var _map: WorldMap
var _help: HelpScreen
var _no_drop := false
var _sun: DirectionalLight3D
var _lamp: OmniLight3D               ## фонарь машины (LAMP_*)
var _env: Environment
var _weather_k := {&"storm": 0.0, &"murk": 0.0}
var _spawn := Vector2.ZERO
var _over_timer := 0.0
var _refused_key := -1             ## находка, на которую уже показали «трюм полон»
var _hangar: HangarScreen
var _warmup: Warmup
var _world_pending := false        ## мир вокруг старта ещё грузится в фоне (пока игрок в трюме)
var _begin_waiting := false        ## игрок уже нажал «Высадка» — ждём мир за затемнением
var _loading: LoadingScreen        ## экран загрузки (мир, прогрев, звуки, трюм) — до трюма и после «Заново»
var _begin_after_loading := false  ## «Заново»: после загрузки — сразу десант
var _sounds_total := 1             ## звуков в очереди синтеза в начале загрузки (для прогресса)
var _sounds_marked := false        ## метка sounds_done уже поставлена
var _shaders_peak := 0             ## больше всего программ в фоновой сборке за загрузку (для прогресса)
var _shaders_quiet := 0            ## кадров подряд без программ в фоновой сборке
var _audio: AudioDirector
var _job_budget := 0


func _ready() -> void:
	DevTools.mark("main_ready")
	var args := DevTools.parse_args()
	run_seed = int(args.get("seed", str(int(Time.get_unix_time_from_system()) % 100000)))
	print("Explorer — seed %d (Godot %s)" % [run_seed, Engine.get_version_info().string])
	dev = DevTools.new(args)
	_no_drop = args.has("no-drop")
	rules = dev.tweak_rules(Balance.rules)
	dev.run_seed = run_seed
	_build_world(args)
	_new_run()
	if dev.skips_start():
		if dev.wants_autopilot():
			sandbox = true
			vehicle.autopilot = dev.make_autopilot()
		_begin()
	elif Settings.quick_restart:
		# «Заново» на экране итога: тот же класс, сразу десант — без трюма с выбором; сначала — экран загрузки
		# (шейдеры уже прогреты, догружается только мир).
		Settings.quick_restart = false
		_begin_after_loading = true
	else:
		vehicle.control_enabled = false
		var hangar := HangarScreen.new()
		hangar.vehicle_ids = HangarScreen.display_order(Balance.vehicle_ids())
		# По умолчанию в трюме выбран универсал в центре; «Заново» на экране итога сохраняет машину.
		var first: StringName = vehicle.cls.id if dev.args.has("vehicle") else HangarScreen.DEFAULT_ID
		hangar.selected = maxi(hangar.vehicle_ids.find(first), 0)
		if vehicle.cls.id != hangar.vehicle_ids[hangar.selected]:
			_on_vehicle_selected(hangar.vehicle_ids[hangar.selected])
		hangar.vehicle_changed.connect(_on_vehicle_selected)
		hangar.started.connect(_begin)
		rig.turn_enabled = false
		hud.visible = false
		hangar.locked = true                     # ввод — после экрана загрузки
		add_child(hangar)
		_hangar = hangar
	if _world_pending:
		_loading = LoadingScreen.new()
		add_child(_loading)
		dev.holding = true                       # часы сценариев — от конца загрузки
		_audio.synth_budget_usec = LOADING_SYNTH_USEC
		_sounds_total = maxi(Sfx.pending(), 1)
		_update_loading()
	else:
		LoadingScreen.web_done()                 # отладочный старт без экрана — убрать и оболочку страницы
	DevTools.mark("world_built")


func _build_world(args: Dictionary) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.36, 0.27, 0.42)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.52, 0.72)
	env.ambient_light_energy = AMBIENT_ENERGY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env = env
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, -70.0, 0.0)
	sun.light_color = Color(1.0, 0.88, 0.74)
	sun.light_energy = SUN_ENERGY
	sun.shadow_enabled = not args.has("no-shadows")
	# Одна ортогональная карта теней на небольшую дальность — плотнее тексели. Смещение по нормали
	# берётся из вершинных нормалей меша (ChunkMesher их пишет), иначе грани затеняют сами себя.
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 40.0
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.8
	# Пиксель-арт: тени жёсткие и крупные (без размытия, карта 1024 — тексель тени около пикселя рендера,
	# project.godot: directional_shadow/size, soft_shadow_filter_quality = 0).
	sun.shadow_blur = 0.0
	add_child(sun)
	_sun = sun
	# Фонарь — отдельный узел, а не часть машины: светит и пока машина спрятана (трюм, десант).
	_lamp = OmniLight3D.new()
	_lamp.name = "VehicleLamp"
	_lamp.omni_range = LAMP_RANGE
	_lamp.light_energy = LAMP_ENERGY
	_lamp.light_specular = 0.0
	_lamp.shadow_enabled = false
	add_child(_lamp)
	EventBus.weather_changed.connect(_on_weather_changed)

	terrain = TerrainData.new()
	var terrain_params := TerrainParams.new()
	terrain_params.dunes_enabled = not args.has("no-dunes")   # отладка: тот же мир без дюнных полей
	generator = TerrainGenerator.new(run_seed, terrain_params)
	query = TerrainQuery.new(terrain)
	scheduler = JobScheduler.new()
	scheduler.name = "JobScheduler"
	add_child(scheduler)
	streamer = WorldStreamer.new(terrain, generator, query, scheduler, TerrainMaterials.new())
	add_child(streamer)
	pickups = PickupField.new(terrain, query, run_seed, rules)
	add_child(pickups)
	streamer.chunk_built.connect(pickups.on_chunk_built)
	streamer.chunk_removed.connect(pickups.on_chunk_removed)

	var spawn := _spawn_point(args)
	# Обычный старт и «Заново» — через экран загрузки: мир вокруг точки старта догружается задачами с большим
	# бюджетом, пока под экраном прогреваются шейдеры и синтезируются звуки (синхронно в браузере — замершая
	# страница). Отладочные старты без трюма — синхронно, как раньше.
	_world_pending = not dev.skips_start()
	if _world_pending:
		_job_budget = scheduler.budget_usec
		scheduler.budget_usec = maxi(_job_budget, LOADING_JOB_BUDGET_USEC)
	else:
		var t0 := Time.get_ticks_usec()
		streamer.preload_around(spawn)
		if _plays_drop() and not args.has("spawn"):
			spawn = _landing_point(spawn)
			streamer.preload_around(spawn)
		print("preload: %d chunks in %d ms" % [streamer.loaded_count(), (Time.get_ticks_usec() - t0) / 1000])

	var vehicle_id := StringName(args.get("vehicle", Settings.vehicle_id))
	if Balance.vehicle(vehicle_id) == null:
		vehicle_id = &"rover"
	vehicle = Vehicle.new(Balance.vehicle(vehicle_id), query)
	vehicle.crawl_speed = rules.empty_crawl_speed
	add_child(vehicle)
	vehicle.place(spawn, SPAWN_HEADING)
	vehicle.set_physics_process(not _world_pending)     # под незагруженным рельефом машине нечего делать
	vehicle.damaged.connect(_on_vehicle_damaged)
	vehicle.died.connect(_on_vehicle_died)
	_spawn = spawn

	rig = IsoCameraRig.new()
	rig.target = vehicle
	rig.zoom = float(args.get("zoom", "1"))
	add_child(rig)
	vehicle.camera = rig.camera

	hud = Hud.new()
	add_child(hud)
	hud.radar.pickups = pickups
	hud.radar.vehicle = vehicle
	hud.radar.camera = rig.camera

	# Карта мира: память о рельефе и виденном пишется весь забег (и о чанках, загруженных до этой строки).
	_map = WorldMap.new()
	_map.memory = MapMemory.new(terrain)
	_map.pickups = pickups
	_map.vehicle = vehicle
	_map.rig = rig
	_map.hud = hud
	streamer.chunk_built.connect(_map.memory.chunk_built)
	for coord in terrain.chunks:
		_map.memory.chunk_built(coord)
	add_child(_map)

	shuttles = ShuttleController.new()
	shuttles.vehicle = vehicle
	shuttles.query = query
	shuttles.generator = generator
	shuttles.rules = rules
	shuttles.hud = hud
	add_child(shuttles)
	shuttles.evacuate_requested.connect(func() -> void: run.evacuate())
	shuttles.refueled.connect(_restart_engine)
	shuttles.crushed.connect(_on_crushed)

	threats = ThreatDirector.new()
	threats.rules = rules
	threats.vehicle = vehicle
	threats.query = query
	_map.threats = threats                     # видимость в непогоду — разведанное на карте
	threats.terrain = terrain
	threats.generator = generator
	threats.streamer = streamer
	threats.pickups = pickups
	threats.run_seed = run_seed
	threats.enabled = not args.has("no-threats")
	threats.min_level = int(args.get("threat", "1"))
	threats.forced = dev.forced_events()
	add_child(threats)
	threats.damaged.connect(_on_vehicle_damaged)
	dev.threats = threats

	fauna = FaunaDirector.new()
	fauna.rules = rules
	fauna.vehicle = vehicle
	fauna.query = query
	fauna.terrain = terrain
	fauna.generator = generator
	fauna.scheduler = scheduler
	fauna.run_seed = run_seed
	fauna.enabled = not args.has("no-fauna")
	fauna.forced = dev.forced_events()
	add_child(fauna)
	streamer.chunk_built.connect(fauna.on_chunk_built)
	streamer.chunk_removed.connect(fauna.on_chunk_removed)
	fauna.damaged.connect(_on_vehicle_damaged)
	dev.fauna = fauna

	_pause = PauseOverlay.new()
	add_child(_pause)
	_pause.settings.changed.connect(_apply_controls)    # управление сменили на паузе — камера сразу
	_help = HelpScreen.new()
	add_child(_help)

	# Прогрев шейдеров — раз за сессию (ShaderCache держит их и после «Заново»).
	if not ShaderCache.warmed:
		_warmup = Warmup.new()
		_warmup.at = Vector3(spawn.x, 0.0 if _world_pending else vehicle.state.y, spawn.y)
		_warmup.wait_world = _world_pending      # взгляд на настоящий мир — когда он догрузится за трюмом
		_warmup.rules = rules
		_warmup.vehicle = vehicle
		_warmup.query = query
		_warmup.terrain = terrain
		_warmup.pickups = pickups
		_warmup.noise = fauna.noise
		_warmup.materials = streamer.materials
		_warmup.streamer = streamer
		add_child(_warmup)

	var weather_fx := WeatherOverlay.new()
	weather_fx.camera = rig.camera
	add_child(weather_fx)

	var audio := AudioDirector.new()
	audio.vehicle = vehicle
	add_child(audio)
	_audio = audio
	_toast = Toast.new()
	add_child(_toast)

	var overlay := DebugOverlay.new()
	overlay.run_seed = run_seed
	overlay.vehicle = vehicle
	overlay.streamer = streamer
	overlay.scheduler = scheduler
	overlay.query = query
	overlay.visible = dev.wants_autopilot() or args.has("debug")   # в игре — по F3
	add_child(overlay)

	dev.vehicle = vehicle
	dev.streamer = streamer
	dev.scheduler = scheduler
	dev.terrain = terrain
	dev.query = query
	dev.rig = rig
	dev.toast = _toast
	add_child(dev)



## Точка старта: край ближайшей к началу координат площадки челнока (ровно и сухо) — там машина стоит
## без десанта; десант ищет место посадки капсулы вокруг неё.
func _spawn_point(args: Dictionary) -> Vector2:
	if args.has("spawn"):
		var xz := (args["spawn"] as String).split(",")
		return Vector2(float(xz[0]) + 0.5, float(xz[1]) + 0.5)
	for r in 4:
		for bz in range(-r, r + 1):
			for bx in range(-r, r + 1):
				var pad := generator.pad_of_block(Vector2i(bx, bz))
				if pad.z != TerrainGenerator.NO_PAD:
					return Vector2(pad.x + 0.5 + SPAWN_PAD_OFFSET, pad.y + 0.5)
	return Vector2(0.5, 0.5)


## Новый RunState; его сигналы уходят в EventBus (HUD и прочие слушатели).
func _new_run() -> void:
	run = RunState.new(vehicle.cls, rules)
	run.hp_changed.connect(EventBus.hp_changed.emit)
	run.fuel_changed.connect(EventBus.fuel_changed.emit)
	run.cargo_changed.connect(EventBus.cargo_changed.emit)
	run.score_changed.connect(EventBus.score_changed.emit)
	run.ended.connect(_on_run_ended)
	dev.run = run
	dev.tweak_run(run)
	shuttles.run = run


## Выбор на стартовом экране: другая машина, новый RunState под её класс.
func _on_vehicle_selected(id: StringName) -> void:
	vehicle.set_class(Balance.vehicle(id))
	_new_run()


## Свет под непогодой: под тучами сцена заметно темнеет, в тумане и пыли — слегка.
func _on_weather_changed(kind: StringName, intensity: float) -> void:
	_weather_k[&"storm" if kind == &"storm" else &"murk"] = intensity
	var storm: float = _weather_k[&"storm"]
	var murk: float = _weather_k[&"murk"]
	_sun.light_energy = SUN_ENERGY * (1.0 - 0.55 * storm) * (1.0 - 0.2 * murk)
	_env.ambient_light_energy = AMBIENT_ENERGY * (1.0 - 0.35 * storm)


## Точка высадки (GDD §2.1): рядом с площадкой старта, на сухом ровном тайле без стенок и деревьев, не ближе
## LANDING_DRY тайлов к воде; если такого нет — самый далёкий от воды из годных. Детерминированно по seed;
## не нашлось ни одного — центр площадки.
func _landing_point(pad: Vector2) -> Vector2:
	var rng := DetRng.rng_for(run_seed, 0, 0, 950)
	var best := pad
	var best_dry := -1
	for _i in LANDING_TRIES:
		var p := pad + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(9.0, 16.0)
		var t := Grid.tile_of_world(p.x, p.y)
		if not query.is_loaded(t.x, t.y) or query.water_tier(t.x, t.y) != TerrainQuery.NO_WATER:
			continue
		if query.has_standing_tree(t.x, t.y):
			continue
		var d := terrain.owner_of(t.x, t.y)
		if (d.flags[d.local_index(t.x, t.y)] & (ChunkData.FLAG_PAD | ChunkData.FLAG_NEST)) != 0:
			continue
		var walls := false
		for dir in 4:
			walls = walls or query.edge_rise(t.x, t.y, dir) != 0 or query.edge_drop(t.x, t.y, dir) != 0
		if walls:
			continue
		var dry := _water_gap(t, LANDING_DRY)
		if dry >= LANDING_DRY:
			return Vector2(t.x + 0.5, t.y + 0.5)
		if dry > best_dry:
			best_dry = dry
			best = Vector2(t.x + 0.5, t.y + 0.5)
	return best


## Расстояние (по Чебышёву) от тайла t до ближайшей воды, не больше limit.
func _water_gap(t: Vector2i, limit: int) -> int:
	for r in range(1, limit):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var tx := t.x + dx
				var tz := t.y + dz
				if query.is_loaded(tx, tz) and query.water_tier(tx, tz) != TerrainQuery.NO_WATER:
					return r
	return limit


## Сцена десанта: в обычной игре да; отладочные сценарии без стартового экрана и --no-drop стартуют
## сразу на площадке старта.
func _plays_drop() -> bool:
	return not dev.skips_start() and not _no_drop


## Мир за трюмом ещё не готов: догружается или прогреваются шейдеры.
func _preparing() -> bool:
	return _world_pending or (_warmup != null and is_instance_valid(_warmup) and not _warmup.done)


func _begin() -> void:
	DevTools.mark("begin")
	if _hangar != null and _preparing():
		# «Высадка» раньше, чем мир готов: трюм держит затемнение с надписью, пока не догрузится.
		_begin_waiting = true
		if _hangar != null and is_instance_valid(_hangar):
			_hangar.waiting = true
		return
	if not dev.skips_start():
		Settings.vehicle_id = String(vehicle.cls.id)
		Settings.save_settings()
	rig.turn_enabled = true
	hud.visible = true
	run.announce()                     # HUD сразу с полным баком и бронёй — и во время десанта
	if not _plays_drop():
		_start_run()
		return
	# Десант: машина в капсуле, капсула падает с орбиты на точку старта.
	phase = Phase.DROP
	vehicle.visible = false
	vehicle.control_enabled = false
	var pod := DropPod.new()
	pod.query = query
	add_child(pod)
	pod.start(Vector3(_spawn.x, query.surface_y(_spawn.x, _spawn.y), _spawn.y))
	pod.landed.connect(_on_drop_landed)
	pod.opened.connect(_start_run)


## Касание капсулы: мягкая посадка на тормозных двигателях — пыль, лёгкая тряска, глухой удар; фауна
## рядом разбегается (шум двигателей).
func _on_drop_landed() -> void:
	DevTools.mark("drop_landed")
	vehicle.place(_spawn, SPAWN_HEADING)
	vehicle.visible = true
	fauna.scare(_spawn, 15.0)
	EventBus.camera_shake_requested.emit(0.6, 0.4)
	EventBus.drop_landed.emit(Vector3(_spawn.x, vehicle.state.y, _spawn.y))


func _start_run() -> void:
	DevTools.mark("run_start")
	phase = Phase.RUN
	_pause.enabled = true
	_help.pause_game = true
	_map.enabled = true
	_apply_controls()
	hud.visible = true
	dev.mark_start()
	vehicle.control_enabled = true
	vehicle.engine.play()
	shuttles.active = true
	shuttles.menu_enabled = not sandbox
	threats.begin()
	fauna.begin()
	run.announce()
	EventBus.run_started.emit(run_seed, vehicle.cls.id)


func _physics_process(dt: float) -> void:
	var t0 := Time.get_ticks_usec()
	_step(dt)
	dev.script_usec += Time.get_ticks_usec() - t0     # для --log-slow: сколько занял шаг игры


func _step(dt: float) -> void:
	streamer.update_focus(vehicle.state.pos, vehicle.state.vel)
	var p := vehicle.state.pos
	RenderingServer.global_shader_parameter_set(&"vis_center", Vector3(p.x, vehicle.state.y, p.y))
	if phase != Phase.RUN:
		return
	run.tick(dt)
	pickups.run_time = run.time
	_collect_pickups()
	if not vehicle.out_of_fuel and run.burn_fuel(dt, vehicle.state.throttle):
		_on_fuel_empty()
	if run.fuel > 0.0 and run.fuel < rules.low_fuel_frac * vehicle.cls.fuel_max:
		EventBus.threat_telegraphed.emit(&"low_fuel", Vector3.ZERO, 0.0, Vector2.ZERO)   # пейджер: «МАЛО ТОПЛИВА»
	shuttles.step(dt)
	threats.step(dt)
	fauna.level = threats.level
	fauna.step(dt)
	hud.radar.jammed = threats.radar_jammed()


## Режим управления из настроек: «вид сзади» — камера за курсом (только во время вылазки).
func _apply_controls() -> void:
	rig.chase = Settings.chase() and phase == Phase.RUN


## Экран загрузки: прогресс по мир / прогрев / звуки / свет трюма; всё готово — экран уходит, трюм открывается
## (или «Заново» — сразу десант).
func _update_loading() -> void:
	var world := 1.0 if not _world_pending else streamer.ready_fraction(_spawn)
	var warm := _warmup.progress() if _warmup != null and is_instance_valid(_warmup) else 1.0
	var sounds := 1.0 - float(Sfx.pending()) / _sounds_total
	if Sfx.pending() == 0 and not _sounds_marked:
		_sounds_marked = true
		DevTools.mark("sounds_done")
	var hangar_ready := _hangar == null or not is_instance_valid(_hangar) or _hangar.warmed
	# Браузер ещё собирает программы в фоне (веб) — объекты с ними пока не рисуются: ждём.
	var shaders := ShaderCache.pending_programs()
	if shaders > _shaders_peak:
		_shaders_peak = shaders
	# Ноль — несколько кадров подряд: готовая программа объекта заказывает его следующие проходы только при
	# отрисовке (после этого кадра).
	_shaders_quiet = 0 if shaders > 0 else _shaders_quiet + 1
	var compiled := 1.0 - float(shaders) / maxi(_shaders_peak, 1)
	var p := 0.4 * world + 0.35 * warm + 0.1 * compiled + 0.1 * sounds + (0.05 if hangar_ready else 0.0)
	var text := "сборка мира" if world < 1.0 else ("прогрев графики" if warm < 1.0 or shaders > 0 else ("звуки" if sounds < 1.0 else "трюм"))
	_loading.set_progress(p, text)
	if not _preparing() and Sfx.pending() == 0 and hangar_ready and _shaders_quiet >= SHADERS_QUIET_FRAMES:
		_on_loaded()


func _on_loaded() -> void:
	DevTools.mark("loading_done")
	dev.holding = false
	_loading.finish()
	_loading = null
	_audio.synth_budget_usec = AudioDirector.SYNTH_BUDGET_USEC
	if _hangar != null and is_instance_valid(_hangar):
		_hangar.locked = false
	if _begin_after_loading:
		_begin_after_loading = false
		_begin()


## Мир вокруг старта догрузился (трюм): точка высадки, машина на место, обычный бюджет задач.
func _on_world_ready() -> void:
	DevTools.mark("world_ready")
	_world_pending = false
	print("world ready in background: %d chunks, %d ms after start" % [streamer.loaded_count(), Time.get_ticks_msec()])
	scheduler.budget_usec = _job_budget
	if _plays_drop() and not dev.args.has("spawn"):
		_spawn = _landing_point(_spawn)
	vehicle.place(_spawn, SPAWN_HEADING)
	vehicle.set_physics_process(true)
	rig.snap_to_target()               # «Заново»: загрузка кончается в этом же кадре — без пролёта камеры
	if _warmup != null and is_instance_valid(_warmup):
		_warmup.look_at_world(Vector3(_spawn.x, vehicle.state.y, _spawn.y))


func _process(dt: float) -> void:
	_lamp.position = Vector3(vehicle.state.pos.x, vehicle.state.y + LAMP_HEIGHT, vehicle.state.pos.y)
	if _world_pending and streamer.ready_around(_spawn):
		_on_world_ready()
	if _loading != null:
		_update_loading()
	if _begin_waiting and not _preparing():
		_begin_waiting = false
		if _hangar != null and is_instance_valid(_hangar):
			_hangar.waiting = false
		_begin()
	if phase == Phase.OVER:
		_over_timer -= dt
		if _over_timer <= 0.0:
			_show_results()


## Подбор находок в радиусе (GDD §6): груз — в трюм с вытеснением дешёвого, ремкомплект и канистра
## действуют сразу; при полном HP или баке они остаются лежать.
func _collect_pickups() -> void:
	var s := vehicle.state
	if s.falling or s.drowning:
		return
	for p in pickups.near(s.pos, rules.pickup_radius):
		var key: int = p["key"]
		var kind := Balance.pickup(p["kind"])
		var shown := 0
		if kind.cargo:
			var offer := run.offer_cargo(kind)
			if not offer.accepted:
				if key != _refused_key:
					_refused_key = key
					hud.popup("НЕТ МЕСТА ДЛЯ ГРУЗА", Hud.COLOR_DAMAGE)
				continue
			for displaced in offer.displaced:
				pickups.drop(displaced.id, s.pos, rules.pickup_radius + 0.5)
			shown = kind.value
		elif kind.hp_restore > 0:
			if run.hp >= vehicle.cls.hp_max:
				continue
			run.heal(kind.hp_restore)
			shown = kind.hp_restore
		else:
			if run.fuel >= vehicle.cls.fuel_max - 0.5:
				continue
			var frac := pickups.canister_fraction(key, kind)
			run.add_fuel(vehicle.cls.fuel_max * frac)
			shown = roundi(frac * 100.0)
			_restart_engine()
		pickups.take(key)
		dev.pickups_collected += 1
		EventBus.pickup_collected.emit(kind.id, shown)


func _on_vehicle_damaged(amount: int, source: StringName) -> void:
	if phase != Phase.RUN:
		return
	var before := run.hp
	run.damage(amount, source)
	if run.hp < before:
		EventBus.vehicle_damaged.emit(before - run.hp, source, vehicle.global_position)


func _on_vehicle_died(cause: StringName) -> void:
	if phase == Phase.RUN:
		run.end(cause)


## Пустой бак (GDD §7.3): машина ползёт на минимальной скорости — до канистры, до площадки челнока
## или до суши, откуда можно вызвать аварийный. Забег не обрывается.
func _on_fuel_empty() -> void:
	EventBus.fuel_empty.emit()
	if sandbox:
		run.add_fuel(vehicle.cls.fuel_max)
		return
	vehicle.out_of_fuel = true


## Топливо снова есть (канистра, аварийный челнок): машина едет как обычно.
func _restart_engine() -> void:
	if run.fuel > 0.0:
		vehicle.out_of_fuel = false


## Челнок сел на машину (GDD §2.3): корпус сплющен, конец забега.
func _on_crushed() -> void:
	if phase != Phase.RUN:
		return
	vehicle.crush()
	run.invulnerable = 0.0
	run.damage(run.hp, &"shuttle")


func _on_run_ended(cause: StringName) -> void:
	var result := run.result()
	print("run ended: %s, score %d, time %.0f s" % [cause, result["score"], result["time"]])
	if cause != RunState.CAUSE_EVACUATED:
		EventBus.vehicle_died.emit(cause)
	EventBus.run_ended.emit(result)
	if sandbox:
		dev.deaths += 1
		vehicle.respawn(_spawn, SPAWN_HEADING)     # цела и управляема — и после челнока сверху, и после луча
		_new_run()
		shuttles.reset()
		run.announce()
		return
	phase = Phase.OVER
	_pause.enabled = false
	_help.pause_game = false
	_map.enabled = false
	_map.set_open(false)
	rig.turn_enabled = false           # Q / E — не камера: забег кончился (на экране итога — набор имени)
	rig.chase = false
	shuttles.stop()                    # открытое меню челнока или вызова закрывается вместе с забегом
	vehicle.control_enabled = false
	if cause == &"whirlpool":
		hud.banner(DeathText.banner(&"sunk"), Hud.COLOR_DAMAGE)     # затянуло под воду — корпус цел
	elif cause != RunState.CAUSE_EVACUATED and cause != &"drowned":
		if not vehicle.wrecked:
			vehicle.wreck()
		hud.banner(DeathText.banner(&"wrecked"), Hud.COLOR_DAMAGE)
	if cause != RunState.CAUSE_EVACUATED:
		vehicle.sink_on_water()        # разбитая или затянутая на воде — идёт ко дну
	_over_timer = EVAC_SCENE_S if cause == RunState.CAUSE_EVACUATED else rules.death_delay_s


func _show_results() -> void:
	DevTools.mark("results")
	phase = Phase.RESULTS
	hud.visible = false
	var screen := ResultsScreen.new(run.result(), Leaderboard.new())
	screen.restart_requested.connect(_restart.bind(true))
	screen.exit_requested.connect(_restart.bind(false))
	add_child(screen)


## Новый забег: quick — сразу десант на той же машине («Заново»), иначе — в трюм к выбору («Выход»).
func _restart(quick: bool) -> void:
	DevTools.mark("restart_quick" if quick else "restart_exit")
	Settings.quick_restart = quick
	get_tree().reload_current_scene()
