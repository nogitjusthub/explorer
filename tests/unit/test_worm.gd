extends TestCase
## Песчаный червь (GDD §5.4): слышит едущую машину издалека (worm_hear_r × шум), стоящую — нет; не слыша —
## ждёт на месте (не подкрадывается) и через worm_wait_s уходит; бросок — только после того, как вал (пыль,
## гул) шёл HUNT_MIN_S, даже если погоня началась вплотную; услышав, погоню не бросает — уходит, только если
## машина LOSE_S вне его грунта.

const DT := 1.0 / 60.0


func _make(f: TerrainFixture, at: Vector2, vehicle_at: Vector2) -> Worm:
	var v := Vehicle.new(load("res://data/vehicles/tank.tres"), f.query)
	v.state.pos = vehicle_at
	var w := Worm.new()
	w.rules = BalanceRules.new()
	w.vehicle = v
	w.query = f.query
	w.terrain = f.terrain
	w.noise = NoiseField.new()
	w.rng = RandomNumberGenerator.new()
	w.rng.seed = 7
	w.setup(at)
	(Engine.get_main_loop() as SceneTree).root.add_child(w)     # гул (AudioStreamPlayer) играет только в дереве
	return w


func _dispose(w: Worm) -> void:
	w.vehicle.free()
	w.free()


func test_standing_vehicle_is_not_heard_worm_waits_then_leaves() -> void:
	var f := TerrainFixture.new()                # весь грунт — ареал червя
	var at := Vector2(30.5, 10.5)
	var w := _make(f, at, Vector2(10.5, 10.5))
	w.noise.update_vehicle(w.vehicle.state.pos, 0.0, 1.0)     # машина стоит
	for _i in roundi((w.rules.worm_wait_s - 1.0) / DT):
		w.step(DT)
	assert_eq(w.state, Worm.State.IDLE, "a standing vehicle is not heard")
	assert_eq(w.pos, at, "does not creep up while it hears nothing")
	assert_true(not w.finished, "still waiting")
	for _i in roundi(2.0 / DT):
		w.step(DT)
	assert_true(w.finished, "gives up after worm_wait_s and goes deep")
	_dispose(w)


func test_moving_vehicle_is_heard_from_far() -> void:
	var f := TerrainFixture.new()
	var w := _make(f, Vector2(38.5, 10.5), Vector2(10.5, 10.5))   # 28 тайлов — дальше слуха прочей фауны
	w.noise.update_vehicle(w.vehicle.state.pos, 1.0, 1.0)     # полный ход — шум 1
	w.step(DT)
	assert_eq(w.state, Worm.State.HUNT, "hears a vehicle at full speed beyond the spawn ring")
	_dispose(w)


func test_slow_vehicle_is_heard_only_near() -> void:
	var f := TerrainFixture.new()
	var w := _make(f, Vector2(30.5, 10.5), Vector2(10.5, 10.5))
	w.noise.update_vehicle(w.vehicle.state.pos, 0.2, 1.0)     # крадётся: шум 0,25 — слышно в 8 тайлах
	w.step(DT)
	assert_eq(w.state, Worm.State.IDLE, "a creeping vehicle 20 tiles away is not heard")
	w.pos = Vector2(16.5, 10.5)
	w.step(DT)
	assert_eq(w.state, Worm.State.HUNT, "heard when it creeps close")
	_dispose(w)


func test_strike_only_after_visible_hunt_even_from_close() -> void:
	var f := TerrainFixture.new()
	var w := _make(f, Vector2(10.9, 10.5), Vector2(10.5, 10.5))   # погоня начинается вплотную
	w.start_hunt()
	var t := 0.0
	while w.state == Worm.State.HUNT and t < 10.0:
		w.step(DT)
		t += DT
	assert_eq(w.state, Worm.State.TELEGRAPH, "a hunt next to the vehicle ends in a strike telegraph")
	assert_true(t >= Worm.HUNT_MIN_S, "the ridge runs at least HUNT_MIN_S first (%.2f s)" % t)
	_dispose(w)


func test_hunt_holds_off_until_min_time() -> void:
	var f := TerrainFixture.new()
	var w := _make(f, Vector2(16.5, 10.5), Vector2(10.5, 10.5))
	w.start_hunt()
	for _i in roundi(Worm.HUNT_MIN_S * 0.8 / DT):
		w.step(DT)
	assert_eq(w.state, Worm.State.HUNT, "still hunting")
	assert_true(w.pos.distance_to(w.vehicle.state.pos) >= Worm.HOLD_OFF - 0.01, "keeps HOLD_OFF before HUNT_MIN_S")
	_dispose(w)


func test_hunt_never_gives_up_on_a_faster_vehicle() -> void:
	var f := TerrainFixture.new(4, 3)            # тайлы −96…127
	var w := _make(f, Vector2(-80.5, 0.5), Vector2(-60.5, 0.5))
	w.start_hunt()
	for _i in roundi(15.0 / DT):                 # машина уходит быстрее червя — 15 с без сближения
		w.vehicle.state.pos.x += 6.0 * DT
		w.step(DT)
	assert_eq(w.state, Worm.State.HUNT, "once it has heard the vehicle it keeps chasing")
	assert_true(not w.finished, "does not give up")
	_dispose(w)


func test_vehicle_on_rock_worm_leaves_after_lose_s() -> void:
	var f := TerrainFixture.new()
	for tz in range(6, 15):
		for tx in range(6, 15):
			var d := f.terrain.owner_of(tx, tz)
			d.material[d.local_index(tx, tz)] = ChunkData.Mat.ROCK
	var w := _make(f, Vector2(20.5, 10.5), Vector2(10.5, 10.5))
	w.start_hunt()
	for _i in roundi((Worm.LOSE_S - 1.0) / DT):
		w.step(DT)
	assert_true(not w.finished, "waits while the vehicle sits on rock")
	assert_eq(w.state, Worm.State.HUNT, "still hunting")
	for _i in roundi(2.0 / DT):
		w.step(DT)
	assert_true(w.finished, "goes deep after LOSE_S off its ground")
	_dispose(w)
