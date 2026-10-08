extends Node
## Корень игрового цикла (GameFlow, ARCHITECTURE §3.2): старт → забег → итог.
## Владеет RunState и связывает с ним машину, находки, челноки и HUD. Отладочные режимы запуска и
## параметры командной строки — в DevTools.

enum Phase { START, DROP, RUN, OVER, RESULTS }

const SUN_ENERGY := 1.25
const AMBIENT_ENERGY := 0.5
const EVAC_SCENE_S := 3.4         ## эвакуация: машину втягивает в челнок, он уходит вверх
const LANDING_TRIES := 40
const SPAWN_HEADING := -PI * 0.75

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
var _help: HelpScreen
var _no_drop := false
var _sun: DirectionalLight3D
var _env: Environment
var _weather_k := {&"storm": 0.0, &"murk": 0.0}
var _spawn := Vector2.ZERO
var _over_timer := 0.0
var _refused_key := -1             ## находка, на которую уже показали «трюм полон»


func _ready() -> void:
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
		# «Заново» на экране итога: тот же класс, сразу десант — без трюма с выбором.
		Settings.quick_restart = false
		_begin()
	else:
		vehicle.control_enabled = false
		var hangar := HangarScreen.new()
		hangar.vehicle_ids = Balance.vehicle_ids()
		hangar.selected = maxi(hangar.vehicle_ids.find(vehicle.cls.id), 0)
		hangar.vehicle_changed.connect(_on_vehicle_selected)
		hangar.started.connect(_begin)
		rig.turn_enabled = false
		hud.visible = false
		add_child(hangar)


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
	sun.shadow_bias = 0.1
	sun.shadow_normal_bias = 2.0
	add_child(sun)
	_sun = sun
	EventBus.weather_changed.connect(_on_weather_changed)

	terrain = TerrainData.new()
	generator = TerrainGenerator.new(run_seed, TerrainParams.new())
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
	add_child(vehicle)
	vehicle.place(spawn, SPAWN_HEADING)
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

	shuttles = ShuttleController.new()
	shuttles.vehicle = vehicle
	shuttles.query = query
	shuttles.generator = generator
	shuttles.rules = rules
	shuttles.hud = hud
	add_child(shuttles)
	shuttles.evacuate_requested.connect(func() -> void: run.evacuate())
	shuttles.refueled.connect(_restart_engine)
	shuttles.tank_expired.connect(func() -> void: run.end(RunState.CAUSE_EMPTY_TANK))

	threats = ThreatDirector.new()
	threats.rules = rules
	threats.vehicle = vehicle
	threats.query = query
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
	hud.pager.vehicle = vehicle
	hud.pager.camera = rig.camera

	_pause = PauseOverlay.new()
	add_child(_pause)
	_help = HelpScreen.new()
	add_child(_help)

	var warmup := Warmup.new()
	warmup.at = Vector3(spawn.x, vehicle.state.y, spawn.y)
	add_child(warmup)

	var weather_fx := WeatherOverlay.new()
	weather_fx.camera = rig.camera
	add_child(weather_fx)

	var audio := AudioDirector.new()
	audio.vehicle = vehicle
	add_child(audio)
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



## Точка десанта: центр ближайшей к началу координат площадки челнока (ровно и сухо).
func _spawn_point(args: Dictionary) -> Vector2:
	if args.has("spawn"):
		var xz := (args["spawn"] as String).split(",")
		return Vector2(float(xz[0]) + 0.5, float(xz[1]) + 0.5)
	for r in 4:
		for bz in range(-r, r + 1):
			for bx in range(-r, r + 1):
				var pad := generator.pad_of_block(Vector2i(bx, bz))
				if pad.z != TerrainGenerator.NO_PAD:
					return Vector2(pad.x + 0.5, pad.y + 0.5)
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


## Точка высадки (GDD §2.1): рядом с площадкой старта, на сухом ровном тайле без стенок и деревьев —
## там капсула выбьет воронку. Детерминированно по seed; не нашлось — центр площадки.
func _landing_point(pad: Vector2) -> Vector2:
	var rng := DetRng.rng_for(run_seed, 0, 0, 950)
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
		if not walls:
			return Vector2(t.x + 0.5, t.y + 0.5)
	return pad


## Сцена десанта: в обычной игре да; отладочные сценарии без стартового экрана и --no-drop стартуют
## сразу на площадке старта.
func _plays_drop() -> bool:
	return not dev.skips_start() and not _no_drop


func _begin() -> void:
	if not dev.skips_start():
		Settings.vehicle_id = String(vehicle.cls.id)
		Settings.save_settings()
	rig.turn_enabled = true
	hud.visible = true
	if not _plays_drop():
		_start_run()
		return
	# Десант: машина в капсуле, капсула падает с орбиты на точку старта.
	phase = Phase.DROP
	vehicle.visible = false
	vehicle.control_enabled = false
	var pod := DropPod.new()
	add_child(pod)
	pod.start(Vector3(_spawn.x, query.surface_y(_spawn.x, _spawn.y), _spawn.y))
	pod.landed.connect(_on_drop_landed)
	pod.opened.connect(_start_run)


## Удар капсулы: воронка, пыль, тряска, раскат; фауна рядом разбегается; машина — на дне воронки.
func _on_drop_landed() -> void:
	Deformation.crater(terrain, _spawn, 2.0, 1)
	vehicle.place(_spawn, SPAWN_HEADING)
	vehicle.visible = true
	fauna.scare(_spawn, 15.0)
	EventBus.camera_shake_requested.emit(1.5, 0.8)
	EventBus.screen_flash_requested.emit(0.35)
	EventBus.drop_landed.emit(Vector3(_spawn.x, vehicle.state.y, _spawn.y))


func _start_run() -> void:
	phase = Phase.RUN
	_pause.enabled = true
	_help.pause_game = true
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
	streamer.update_focus(vehicle.state.pos, vehicle.state.vel)
	var p := vehicle.state.pos
	RenderingServer.global_shader_parameter_set(&"vis_center", Vector3(p.x, vehicle.state.y, p.y))
	if phase != Phase.RUN:
		return
	run.tick(dt)
	pickups.run_time = run.time
	_collect_pickups()
	if vehicle.engine_running and run.burn_fuel(dt, vehicle.state.throttle):
		_on_fuel_empty()
	shuttles.step(dt)
	threats.step(dt)
	fauna.level = threats.level
	fauna.step(dt)
	hud.radar.jammed = threats.radar_jammed()


func _process(dt: float) -> void:
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
					hud.popup("ТРЮМ ПОЛОН", Hud.COLOR_DAMAGE)
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


## Пустой бак: двигатель глохнет, 10 с на решение — аварийный челнок или конец забега (GDD §2.3).
func _on_fuel_empty() -> void:
	EventBus.fuel_empty.emit()
	if sandbox:
		run.add_fuel(vehicle.cls.fuel_max)
		return
	vehicle.engine_running = false
	shuttles.on_fuel_empty()


## Топливо снова есть (канистра, аварийный челнок): двигатель заводится.
func _restart_engine() -> void:
	if vehicle.engine_running or run.fuel <= 0.0:
		return
	vehicle.engine_running = true
	vehicle.engine.play()
	shuttles.on_refueled()


func _on_run_ended(cause: StringName) -> void:
	var result := run.result()
	print("run ended: %s, score %d, time %.0f s" % [cause, result["score"], result["time"]])
	if cause != RunState.CAUSE_EVACUATED:
		EventBus.vehicle_died.emit(cause)
	EventBus.run_ended.emit(result)
	if sandbox:
		dev.deaths += 1
		vehicle.place(_spawn, SPAWN_HEADING)
		_new_run()
		shuttles.reset()
		run.announce()
		return
	phase = Phase.OVER
	_pause.enabled = false
	_help.pause_game = false
	shuttles.active = false
	vehicle.control_enabled = false
	if cause != RunState.CAUSE_EVACUATED and cause != &"drowned" and cause != RunState.CAUSE_EMPTY_TANK:
		vehicle.wreck()
		hud.banner("МАШИНА РАЗБИТА", Hud.COLOR_DAMAGE)
	_over_timer = EVAC_SCENE_S if cause == RunState.CAUSE_EVACUATED else rules.death_delay_s


func _show_results() -> void:
	phase = Phase.RESULTS
	hud.visible = false
	var screen := ResultsScreen.new(run.result(), Leaderboard.new())
	screen.restart_requested.connect(_restart.bind(true))
	screen.exit_requested.connect(_restart.bind(false))
	add_child(screen)


## Новый забег: quick — сразу десант на той же машине («Заново»), иначе — в трюм к выбору («Выход»).
func _restart(quick: bool) -> void:
	Settings.quick_restart = quick
	get_tree().reload_current_scene()
