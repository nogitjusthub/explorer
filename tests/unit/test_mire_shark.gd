extends TestCase
## Илозуб (GDD §5.6): ареал — зыбун и вода рядом; в зыбуне — засада на месте, из воды — подход только по
## ареалу; замах запирает цель, укус при пролёте рядом с машиной, возврат в ареал после прыжка на сушу,
## потеря интереса.

const DT := 1.0 / 60.0


func _mire(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int) -> void:
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			f.set_flags(tx, tz, ChunkData.FLAG_MIRE)


func _make(f: TerrainFixture, at: Vector2, vehicle_at: Vector2) -> MireShark:
	var v := Vehicle.new(load("res://data/vehicles/rover.tres"), f.query)
	v.state.pos = vehicle_at
	var s := MireShark.new()
	s.rules = BalanceRules.new()
	s.vehicle = v
	s.query = f.query
	s.terrain = f.terrain
	s.noise = NoiseField.new()
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = 7
	s.setup(at)
	return s


func _dispose(s: MireShark) -> void:
	s.vehicle.free()
	s.free()


func _in_habitat(f: TerrainFixture, p: Vector2) -> bool:
	return MireShark.habitat(f.query, Grid.tile_of_world(p.x, p.y))


func test_habitat_is_quicksand_and_water_next_to_it() -> void:
	var f := TerrainFixture.new(4)
	f.set_flags(10, 10, ChunkData.FLAG_MIRE)
	f.set_flat(11, 11, 3)
	f.set_water(11, 11, 4)
	f.set_flat(15, 10, 3)
	f.set_water(15, 10, 4)
	assert_true(MireShark.habitat(f.query, Vector2i(10, 10)), "quicksand")
	assert_true(MireShark.habitat(f.query, Vector2i(11, 11)), "water next to quicksand")
	assert_false(MireShark.habitat(f.query, Vector2i(15, 10)), "water far from quicksand")
	assert_false(MireShark.habitat(f.query, Vector2i(10, 12)), "dry land")


## В зыбуне — засада: услышал машину вне досягаемости — не двигается и не бросается, интерес не теряет;
## машина въехала в зону прыжка — бросок, даже тихая (не слышно).
func test_ambush_in_quicksand() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 10, 20, 11)
	var start := Vector2(5.5, 10.5)
	var s := _make(f, start, Vector2(15.5, 16.5))
	s.start_hunt()
	var t := 0.0
	while t < s.rules.fauna_give_up_s + 4.0:
		s.step(DT)
		t += DT
		assert_eq(s.state, MireShark.State.STALK, "waits in ambush")
	assert_true(s.pos.distance_to(start) < 0.01, "does not move in the quicksand: %s" % s.pos)
	assert_true(s.aggressive, "keeps waiting while the vehicle is near")
	# Тихая машина въезжает в зону прыжка — бросок.
	s.noise.update_vehicle(Vector2(7.5, 12.0), 0.0, 10.0)
	s.vehicle.state.pos = Vector2(7.5, 12.0)
	s.step(DT)
	assert_eq(s.state, MireShark.State.WINDUP, "vehicle in reach — wind-up")
	_dispose(s)
	# Не охотится (не слышал) — всё равно бросается на машину в зоне прыжка.
	var g := TerrainFixture.new(4)
	_mire(g, 4, 10, 20, 11)
	var quiet := _make(g, start, Vector2(7.5, 12.0))
	quiet.step(DT)
	assert_eq(quiet.state, MireShark.State.WINDUP, "ambush strikes a silent vehicle in reach")
	_dispose(quiet)


## Из воды у зыбуна — подбирается к машине, не выходя из ареала, медленно; не подобраться — сдаётся.
func test_stalks_through_water_and_gives_up() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 9, 20, 9)
	for tx in range(4, 21):
		f.set_flat(tx, 10, 3)
		f.set_water(tx, 10, 4)       # мелкая вода вдоль зыбуна — тоже ареал
	# Машина на суше в 6 тайлах от воды — не допрыгнуть.
	var s := _make(f, Vector2(5.5, 10.5), Vector2(15.5, 16.5))
	s.start_hunt()
	assert_eq(s.state, MireShark.State.STALK, "hunt starts at once")
	var outside := 0
	var leaped := false
	var max_speed := 0.0
	var t := 0.0
	while t < 5.0:
		var before := s.pos
		s.step(DT)
		t += DT
		max_speed = maxf(max_speed, before.distance_to(s.pos) / DT)
		if not _in_habitat(f, s.pos):
			outside += 1
		if s.state != MireShark.State.STALK:
			leaped = true
	assert_eq(outside, 0, "never leaves its habitat while stalking")
	assert_false(leaped, "no wind-up when the vehicle is out of reach")
	assert_near(s.pos.x, 15.5, 0.6, "waits at the water edge nearest to the vehicle")
	assert_true(s.pos.y > 10.5 and s.pos.y < 11.0, "at the edge: %s" % s.pos)
	assert_true(max_speed <= s.rules.shark_speed + 0.01, "approach speed %.2f ≤ shark_speed" % max_speed)
	# Не подобраться ближе — через fauna_give_up_s сдаётся и ныряет.
	while s.aggressive and t < 15.0:
		s.step(DT)
		t += DT
	assert_false(s.aggressive, "loses interest")
	assert_near(t, 4.0 + s.rules.fauna_give_up_s, 1.5, "after fauna_give_up_s without progress")
	# Сдался — CALM_S не слышит даже шумную машину, потом снова охотится.
	s.noise.update_vehicle(s.vehicle.state.pos, 10.0, 10.0)
	var calm := 0.0
	while not s.aggressive and calm < MireShark.CALM_S + 2.0:
		s.step(DT)
		calm += DT
	assert_true(s.aggressive, "hears the vehicle again")
	assert_near(calm, MireShark.CALM_S, 0.2, "ignores the vehicle for CALM_S")
	_dispose(s)


func test_windup_locks_target_and_dodging_avoids_the_bite() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 4, 16, 16)
	var s := _make(f, Vector2(8.5, 10.5), Vector2(10.5, 10.5))
	var hits: Array = []
	s.damaged.connect(func(amount: int, source: StringName) -> void: hits.append([amount, source]))
	s.start_hunt()
	s.step(DT)
	assert_eq(s.state, MireShark.State.WINDUP, "vehicle within reach — wind-up")
	# Машина уезжает с места, пока илозуб замахивается.
	s.vehicle.state.pos = Vector2(10.5, 13.0)
	var windup := DT
	while s.state == MireShark.State.WINDUP:
		s.step(DT)
		windup += DT
	assert_near(windup, s.rules.shark_telegraph_s, 0.05, "wind-up lasts shark_telegraph_s")
	assert_eq(s.target, Vector2(10.5, 10.5), "target locked at the start of the wind-up")
	var t := 0.0
	while s.state == MireShark.State.LEAP and t < 2.0:
		s.step(DT)
		t += DT
	assert_true(hits.is_empty(), "left the spot — no bite")
	assert_near(s.pos.x, 8.5 + s.rules.shark_lunge_dist, 0.2, "leaps shark_lunge_dist")
	assert_near(s.pos.y, 10.5, 0.01, "straight at the locked target")
	assert_near(t, s.rules.shark_lunge_dist / s.rules.shark_lunge_speed, 0.05, "at shark_lunge_speed")
	assert_eq(s.state, MireShark.State.DIVE, "landed in the quicksand — dives")
	_dispose(s)


func test_lunge_bites_once_when_passing_the_vehicle() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 4, 16, 16)
	var s := _make(f, Vector2(8.5, 10.5), Vector2(10.5, 10.5))
	var hits: Array = []
	s.damaged.connect(func(amount: int, source: StringName) -> void: hits.append([amount, source]))
	s.start_hunt()
	var t := 0.0
	while t < s.rules.shark_telegraph_s + 1.2:
		s.step(DT)
		t += DT
	assert_eq(hits.size(), 1, "one bite per leap")
	if hits.size() == 1:
		assert_eq(hits[0][0], s.rules.shark_damage)
		assert_eq(hits[0][1], &"shark")
	assert_true(s.pos.x < 10.5 - 0.3, "bounces off the vehicle, not through it: %s" % s.pos)
	_dispose(s)


func test_no_leap_through_a_cliff() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 4, 8, 16)
	f.set_block(9, 0, 9, 30, 6)
	var s := _make(f, Vector2(8.5, 10.5), Vector2(10.5, 10.5))
	assert_false(s.leap_clear(s.pos, Vector2(10.5, 10.5)), "a two-tier wall blocks the leap")
	assert_true(s.leap_clear(s.pos, Vector2(8.5, 12.5)), "open quicksand does not")
	s.start_hunt()
	for _i in 120:
		s.step(DT)
	assert_eq(s.state, MireShark.State.STALK, "no wind-up behind the cliff")
	_dispose(s)


func test_crawls_back_after_landing_on_dry_land() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 4, 9, 16)
	var s := _make(f, Vector2(8.5, 10.5), Vector2(10.6, 10.5))
	s.start_hunt()
	s.step(DT)
	s.vehicle.state.pos = Vector2(10.6, 15.0)              # увернулась
	var states := {}
	var landed_at := Vector2.INF
	var t := 0.0
	while t < 5.0:
		s.step(DT)
		t += DT
		states[s.state] = true
		if s.state == MireShark.State.LANDED and landed_at == Vector2.INF:
			landed_at = s.pos
		if s.state == MireShark.State.DIVE:
			break
	assert_true(states.has(MireShark.State.CRAWL), "flops and crawls on dry land")
	assert_false(_in_habitat(f, landed_at), "landed outside the quicksand: %s" % landed_at)
	assert_eq(s.state, MireShark.State.DIVE, "back in the quicksand — dives")
	assert_true(_in_habitat(f, s.pos), "ends in the quicksand: %s" % s.pos)
	assert_true(s.aggressive, "still hunting")
	_dispose(s)


func test_slower_than_the_tank() -> void:
	# Подход медленнее танка — уехать легко; в зыбуне ровер (×0,3) медленнее илозуба — тут он и ловит.
	var r := BalanceRules.new()
	var tank: VehicleClass = load("res://data/vehicles/tank.tres")
	var rover: VehicleClass = load("res://data/vehicles/rover.tres")
	assert_true(r.shark_speed < tank.max_speed, "tank outruns the shark")
	assert_true(rover.max_speed * rover.mire_speed_mult < r.shark_speed, "rover stuck in quicksand is slower")
	assert_true(MireShark.CRAWL_SPEED < tank.max_speed)
