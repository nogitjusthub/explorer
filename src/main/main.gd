extends Node
## Корень игрового цикла (GameFlow, ARCHITECTURE §3.2): старт → забег → итог.
## Владеет RunState и связывает с ним машину, находки, челноки и HUD. Отладочные режимы запуска и
## параметры командной строки — в DevTools.

enum Phase { START, RUN, OVER, RESULTS }

const VIS_RADIUS_CLEAR := 1000.0
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
var dev: DevTools
var run: RunState
var rules: BalanceRules
var phase := Phase.START
var sandbox := false               ## автопилот: забег бесконечный, гибель — возрождение

var _toast: Toast
var _spawn := Vector2.ZERO
var _over_timer := 0.0
var _refused_key := -1             ## находка, на которую уже показали «трюм полон»


func _ready() -> void:
	var args := DevTools.parse_args()
	run_seed = int(args.get("seed", str(int(Time.get_unix_time_from_system()) % 100000)))
	print("Explorer — seed %d (Godot %s)" % [run_seed, Engine.get_version_info().string])
	dev = DevTools.new(args)
	rules = dev.tweak_rules(Balance.rules)
	dev.run_seed = run_seed
	_build_world(args)
	_new_run()
	if dev.skips_start():
		if dev.wants_autopilot():
			sandbox = true
			vehicle.autopilot = dev.make_autopilot()
		_begin()
	else:
		vehicle.control_enabled = false
		var start := StartScreen.new()
		start.started.connect(_begin)
		add_child(start)


func _build_world(args: Dictionary) -> void:
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
	sun.shadow_enabled = not args.has("no-shadows")
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
	add_child(streamer)
	pickups = PickupField.new(terrain, query, run_seed, rules)
	add_child(pickups)
	streamer.chunk_built.connect(pickups.on_chunk_built)
	streamer.chunk_removed.connect(pickups.on_chunk_removed)

	var spawn := _spawn_point(args)
	var t0 := Time.get_ticks_usec()
	streamer.preload_around(spawn)
	print("preload: %d chunks in %d ms" % [streamer.loaded_count(), (Time.get_ticks_usec() - t0) / 1000])

	vehicle = Vehicle.new(Balance.vehicle(&"rover"), query)
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

	RenderingServer.global_shader_parameter_set(&"vis_radius", VIS_RADIUS_CLEAR)


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


func _begin() -> void:
	phase = Phase.RUN
	dev.mark_start()
	vehicle.control_enabled = true
	vehicle.engine.play()
	shuttles.active = true
	shuttles.menu_enabled = not sandbox
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
	shuttles.active = false
	vehicle.control_enabled = false
	if cause != RunState.CAUSE_EVACUATED and cause != &"drowned" and cause != RunState.CAUSE_EMPTY_TANK:
		vehicle.wreck()
		hud.banner("МАШИНА РАЗБИТА", Hud.COLOR_DAMAGE)
	_over_timer = rules.death_delay_s


func _show_results() -> void:
	phase = Phase.RESULTS
	hud.visible = false
	var screen := ResultsScreen.new(run.result(), Leaderboard.new())
	screen.restart_requested.connect(func() -> void: get_tree().reload_current_scene())
	add_child(screen)
