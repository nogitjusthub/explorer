extends TestCase
## Илозуб (GDD §5.6): ареал — зыбун и вода у него (не дальше shark_home_r); в зыбуне — засада на месте, из
## засады — только прыжком; в воде — плавает вокруг своего места, гонится по ареалу не дальше shark_chase_r
## от него; замах запирает цель, укус при пролёте рядом с машиной, возврат в ареал после прыжка на сушу,
## потеря интереса.

const DT := 1.0 / 60.0


func _mire(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int) -> void:
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			f.set_flags(tx, tz, ChunkData.FLAG_MIRE)


func _make(f: TerrainFixture, at: Vector2, vehicle_at: Vector2, cls: String = "rover") -> MireShark:
	var v := Vehicle.new(load("res://data/vehicles/%s.tres" % cls), f.query)
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


func _in_mire(f: TerrainFixture, p: Vector2) -> bool:
	return MireShark.mire(f.query, Grid.tile_of_world(p.x, p.y))


## Озеро: дно яруса bottom под зеркалом 4 в прямоугольнике [x0, x1] × [z0, z1].
func _lake(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int, bottom: int) -> void:
	f.set_block(x0, z0, x1, z1, bottom)
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			f.set_water(tx, tz, 4)


## Озеро с зыбуном по северному и южному берегу (ряды z0 − 1 и z1 + 1): вода — вся в ареале, если озеро
## не шире 2 × shark_home_r.
func _banked_lake(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int, bottom: int) -> void:
	_lake(f, x0, z0, x1, z1, bottom)
	_mire(f, x0, z0 - 1, x1, z0 - 1)
	_mire(f, x0, z1 + 1, x1, z1 + 1)


func test_habitat_is_quicksand_and_water_next_to_it() -> void:
	var f := TerrainFixture.new(4)
	f.set_flags(10, 10, ChunkData.FLAG_MIRE)
	f.set_flat(11, 11, 3)
	f.set_water(11, 11, 4)
	f.set_flat(14, 10, 3)
	f.set_water(14, 10, 4)
	f.set_flat(15, 10, 3)
	f.set_water(15, 10, 4)
	f.set_flat(12, 7, 1)
	f.set_water(12, 7, 4)
	f.set_flat(30, 10, 1)
	f.set_water(30, 10, 4)
	var near := BalanceRules.new().shark_home_r
	assert_eq(near, MireShark.HOME_R, "default home radius matches the balance")
	assert_true(MireShark.habitat(f.query, Vector2i(10, 10), near), "quicksand")
	assert_true(MireShark.habitat(f.query, Vector2i(11, 11), near), "water next to quicksand")
	assert_true(MireShark.habitat(f.query, Vector2i(14, 10), near), "water %d tiles from quicksand" % near)
	assert_true(MireShark.habitat(f.query, Vector2i(12, 7), near), "deep water near quicksand")
	assert_false(MireShark.habitat(f.query, Vector2i(15, 10), near), "water farther from quicksand")
	assert_false(MireShark.habitat(f.query, Vector2i(30, 10), near), "an open lake far from quicksand")
	assert_false(MireShark.habitat(f.query, Vector2i(10, 12), near), "dry land")


## В зыбуне — засада: услышал машину вне досягаемости — не двигается и не бросается, интерес не теряет;
## машина въехала в зону прыжка — бросок, даже тихая (не слышно).
func test_ambush_in_quicksand() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 10, 20, 11)
	var start := Vector2(5.5, 10.5)
	var s := _make(f, start, Vector2(12.5, 16.5))
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


## Засада не сходит с зыбуна: машина шумит вокруг (у его места, вне досягаемости) — не двигается; бросок —
## единственный выход; машина ушла дальше shark_chase_r — сдаётся и в покое снова сидит в зыбуне.
func test_ambush_never_leaves_quicksand_except_to_leap() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 4, 8, 10)
	_lake(f, 9, 4, 14, 10, 2)
	var den := Vector2(7.5, 7.5)
	var s := _make(f, den, Vector2(30.5, 7.5))
	var t := 0.0
	while t < 8.0:
		var at := den + Vector2.from_angle(t * 0.8) * 5.0      # кружит вокруг, шумит
		s.vehicle.state.pos = at
		s.noise.update_vehicle(at, 10.0, 10.0)
		s.step(DT)
		t += DT
		assert_true(s.state == MireShark.State.IDLE or s.state == MireShark.State.STALK, "only watches")
		assert_true(s.pos.distance_to(den) < 0.001, "sits still in the quicksand: %s" % s.pos)
	assert_true(s.aggressive, "heard the vehicle")
	# Въехала в зону прыжка — бросок из засады (в воду).
	s.vehicle.state.pos = Vector2(9.8, 7.5)
	s.noise.update_vehicle(s.vehicle.state.pos, 10.0, 10.0)
	var leaped := false
	t = 0.0
	while t < 2.0:
		s.step(DT)
		t += DT
		leaped = leaped or s.state == MireShark.State.LEAP
	assert_true(leaped, "leaves the ambush only by the leap")
	# Машина ушла далеко — сдаётся, возвращается в зыбун и сидит там.
	s.vehicle.state.pos = Vector2(30.5, 7.5)
	s.noise.update_vehicle(s.vehicle.state.pos, 10.0, 10.0)
	t = 0.0
	while t < 12.0 and not (s.state == MireShark.State.IDLE and _in_mire(f, s.pos)):
		s.step(DT)
		t += DT
	assert_false(s.aggressive, "gave up")
	assert_true(_in_mire(f, s.pos), "back in the quicksand: %s" % s.pos)
	var rest := s.pos
	for _i in 120:
		s.step(DT)
	assert_true(s.pos.distance_to(rest) < 0.001, "lurks there again")
	_dispose(s)


## Из воды у зыбуна — плывёт к машине, не выходя из ареала; не подобраться — сдаётся.
func test_stalks_through_water_and_gives_up() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 9, 20, 9)
	for tx in range(4, 21):
		f.set_flat(tx, 10, 3)
		f.set_water(tx, 10, 4)       # мелкая вода вдоль зыбуна — тоже ареал
	# Машина на суше в 6 тайлах от воды — не допрыгнуть.
	var s := _make(f, Vector2(5.5, 10.5), Vector2(11.5, 16.5))
	s.start_hunt()
	assert_eq(s.state, MireShark.State.STALK, "hunt starts at once")
	var outside := 0
	var leaped := false
	var max_speed := 0.0
	var arrived := -1.0
	var t := 0.0
	while t < 4.0:
		var before := s.pos
		s.step(DT)
		t += DT
		max_speed = maxf(max_speed, before.distance_to(s.pos) / DT)
		if not _in_habitat(f, s.pos) or _in_mire(f, s.pos):
			outside += 1
		if s.state != MireShark.State.STALK:
			leaped = true
		if arrived < 0.0 and s.pos.distance_to(Vector2(11.5, 10.9)) < 0.5:
			arrived = t
	assert_eq(outside, 0, "swims only in the water of its habitat")
	assert_false(leaped, "no wind-up when the vehicle is out of reach")
	assert_near(s.pos.x, 11.5, 0.6, "waits at the water edge nearest to the vehicle")
	assert_true(s.pos.y > 10.5 and s.pos.y < 11.0, "at the edge: %s" % s.pos)
	assert_true(max_speed <= s.rules.shark_speed + 0.01, "approach speed %.2f ≤ shark_speed" % max_speed)
	assert_true(max_speed > s.rules.shark_speed * 0.9, "swims at full speed: %.2f" % max_speed)
	assert_true(arrived > 0.0 and arrived < 6.0 / s.rules.shark_speed + 1.0, "got there fast: %.1f s" % arrived)
	# Не подобраться ближе — через fauna_give_up_s сдаётся и ныряет.
	while s.aggressive and t < 15.0:
		s.step(DT)
		t += DT
	assert_false(s.aggressive, "loses interest")
	assert_near(t, arrived + s.rules.fauna_give_up_s, 1.0, "after fauna_give_up_s without progress")
	# Сдался — CALM_S не слышит даже шумную машину, потом снова охотится.
	s.noise.update_vehicle(s.vehicle.state.pos, 10.0, 10.0)
	var calm := 0.0
	while not s.aggressive and calm < MireShark.CALM_S + 2.0:
		s.step(DT)
		calm += DT
	assert_true(s.aggressive, "hears the vehicle again")
	assert_near(calm, MireShark.CALM_S, 0.2, "ignores the vehicle for CALM_S")
	_dispose(s)


## Погоня — не дальше shark_chase_r от своего места: машина ушла дальше — бросает погоню, плывёт домой и
## CALM_S не слышит её, даже вернувшуюся.
func test_breaks_off_beyond_the_chase_radius() -> void:
	var f := TerrainFixture.new(4)
	_banked_lake(f, 2, 4, 26, 10, 1)
	var den := Vector2(4.5, 7.5)
	var near := Vector2(10.5, 7.5)
	var s := _make(f, den, near, "hover")
	s.noise.update_vehicle(near, 7.5, 7.5)
	var farthest := 0.0
	var t := 0.0
	while t < 1.0:
		s.step(DT)
		t += DT
	assert_true(s.aggressive, "hears the hover near its place and hunts")
	var far := den + Vector2(s.rules.shark_chase_r + 2.0, 0.0)
	s.vehicle.state.pos = far
	s.noise.update_vehicle(far, 7.5, 7.5)
	t = 0.0
	while s.aggressive and t < 3.0:
		s.step(DT)
		t += DT
		farthest = maxf(farthest, s.pos.distance_to(den))
	assert_false(s.aggressive, "breaks off once the hover is beyond shark_chase_r")
	# Машина вернулась и шумит — илозуб её не слышит CALM_S и плывёт домой.
	s.vehicle.state.pos = near
	s.noise.update_vehicle(near, 7.5, 7.5)
	t = 0.0
	while t < MireShark.CALM_S - 0.5:
		s.step(DT)
		t += DT
		farthest = maxf(farthest, s.pos.distance_to(den))
		assert_false(s.aggressive, "no immediate re-aggro")
	assert_true(s.pos.distance_to(den) <= MireShark.WANDER_R + 0.6, "swam back home: %s" % s.pos)
	t = 0.0
	while not s.aggressive and t < 1.5:
		s.step(DT)
		t += DT
	assert_true(s.aggressive, "calm over — hunts again")
	assert_true(farthest <= s.rules.shark_chase_r + 1.0, "never farther than the chase radius: %.1f" % farthest)
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


func test_swim_speed_against_vehicles() -> void:
	# В воде плывёт как остальная фауна бежит: быстрее танка, медленнее ровера и ховера на полном ходу; ровер
	# вброд и в зыбуне медленнее илозуба — тут он и ловит. На суше ковыляет медленнее танка.
	var r := BalanceRules.new()
	var tank: VehicleClass = load("res://data/vehicles/tank.tres")
	var rover: VehicleClass = load("res://data/vehicles/rover.tres")
	var hover: VehicleClass = load("res://data/vehicles/hover.tres")
	assert_true(r.shark_speed > tank.max_speed, "faster than the tank")
	assert_true(r.shark_speed < rover.max_speed and r.shark_speed < hover.max_speed, "rover and hover outrun it")
	assert_true(rover.max_speed * rover.water_speed_mult < r.shark_speed, "rover wading is slower")
	assert_true(rover.max_speed * rover.mire_speed_mult < r.shark_speed, "rover stuck in quicksand is slower")
	assert_true(MireShark.CRAWL_SPEED < tank.max_speed)


## В покое плавает вокруг своего места (не дальше WANDER_R, в зыбун не заплывает); ховер на воде у зыбуна —
## слышит его, плывёт, прыгает и кусает.
func test_cruises_home_water_and_hunts_a_hover() -> void:
	var f := TerrainFixture.new(4)
	_banked_lake(f, 2, 4, 14, 10, 1)
	var den := Vector2(4.5, 7.5)
	var s := _make(f, den, Vector2(30.5, 7.5), "hover")
	s.noise.update_vehicle(s.vehicle.state.pos, 7.5, 7.5)    # полный ход — слышно в 12 тайлах
	var hits := [0]
	s.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	var t := 0.0
	var cruised := 0.0
	var farthest := 0.0
	var outside := 0
	while t < 6.0:
		var before := s.pos
		s.step(DT)
		t += DT
		cruised += before.distance_to(s.pos)
		farthest = maxf(farthest, s.pos.distance_to(den))
		if not _in_habitat(f, s.pos) or _in_mire(f, s.pos):
			outside += 1
	assert_eq(s.state, MireShark.State.IDLE, "out of earshot — cruises")
	assert_true(cruised > 1.0, "swims about, not frozen: %.2f" % cruised)
	assert_true(farthest <= MireShark.WANDER_R + 0.6, "stays around its place: %.2f" % farthest)
	assert_eq(outside, 0, "only in the water, never into the quicksand")
	# Ховер у его места — илозуб слышит его и идёт на сближение.
	s.vehicle.state.pos = Vector2(11.5, 7.5)
	s.noise.update_vehicle(s.vehicle.state.pos, 7.5, 7.5)
	var leap_at := -1.0
	t = 0.0
	while t < 6.0 and hits[0] == 0:
		s.step(DT)
		t += DT
		if (s.state == MireShark.State.STALK or s.state == MireShark.State.IDLE) and not _in_habitat(f, s.pos):
			outside += 1
		if leap_at < 0.0 and s.state == MireShark.State.WINDUP:
			leap_at = t
	assert_true(leap_at > 0.0, "winds up in the water")
	assert_true(leap_at < 3.0, "closes in quickly: %.1f s" % leap_at)
	assert_eq(hits[0], 1, "bites the hover")
	assert_eq(outside, 0, "stays in its water")
	_dispose(s)


## Ровер в мелкой воде у берега: илозуб из глубины подплывает и бьёт.
func test_bites_a_rover_wading_in_shallows() -> void:
	var f := TerrainFixture.new(4)
	_banked_lake(f, 2, 4, 14, 10, 1)
	_lake(f, 2, 9, 14, 10, 3)                                  # мель у южного берега
	var s := _make(f, Vector2(4.5, 5.5), Vector2(10.5, 9.5))
	s.start_hunt()
	var hits := [0]
	s.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	var t := 0.0
	while t < 6.0 and hits[0] == 0:
		s.step(DT)
		t += DT
	assert_eq(hits[0], 1, "bites the wading rover: %s, state %d" % [s.pos, s.state])
	_dispose(s)


## Плывёт плавно и решительно: по изогнутому каналу — без остановок на тайлах и без зигзагов ступеньками.
func test_swims_smoothly_along_a_channel() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 2, 4, 20, 5, 2)                                   # канал на восток…
	_lake(f, 19, 4, 20, 20, 2)                                 # …и поворот на юг
	_mire(f, 2, 3, 21, 3)                                      # зыбун по берегам — канал в ареале
	_mire(f, 21, 4, 21, 20)
	var s := _make(f, Vector2(3.5, 4.5), Vector2(19.5, 23.0))  # машина на берегу за концом канала
	s.rules.shark_chase_r = 30.0                               # здесь важна плавность, не поводок
	s.start_hunt()
	var t := 0.0
	var min_speed := INF
	var max_turn := 0.0
	var prev_dir := Vector2.ZERO
	while t < 8.0 and s.state == MireShark.State.STALK and s.pos.distance_to(s.vehicle.state.pos) > 4.5:
		var before := s.pos
		s.step(DT)
		t += DT
		var step := s.pos - before
		if t > 1.0:
			min_speed = minf(min_speed, step.length() / DT)
		if step.length() > 0.001:
			var dir := step.normalized()
			if prev_dir != Vector2.ZERO:
				max_turn = maxf(max_turn, absf(prev_dir.angle_to(dir)))
			prev_dir = dir
	assert_true(s.pos.y > 15.0, "went down the channel: %s" % s.pos)
	assert_true(min_speed > s.rules.shark_speed * 0.5, "no hesitation: min speed %.2f" % min_speed)
	assert_true(max_turn < 0.2, "turns in an arc, not zig-zag: %.2f rad/frame" % max_turn)
	_dispose(s)


## Гоняет илозуба seconds секунд: [был ли замах, укусов].
func _strikes(s: MireShark, seconds: float) -> Array:
	var hits := [0]
	s.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	var windup := false
	var t := 0.0
	while t < seconds:
		s.step(DT)
		t += DT
		windup = windup or s.state == MireShark.State.WINDUP
	return [windup, hits[0]]


## Не прыгает на уступ: машина на берегу ярусом выше воды (и зыбуна) — не на его уровне; берег вровень с
## водой — прыжок.
func test_no_leap_up_a_one_tier_bank() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 2, 2, 10, 20, 2)
	_mire(f, 6, 2, 6, 20)                                     # полоса зыбуна в воде — вода рядом в ареале
	f.set_block(11, 0, 20, 30, 5)                             # берег — на ярус выше зеркала
	var s := _make(f, Vector2(9.5, 10.5), Vector2(11.6, 10.5))
	s.start_hunt()
	var r := _strikes(s, 3.0)
	assert_false(r[0], "no wind-up at a vehicle up on the bank")
	assert_eq(r[1], 0, "no bites")
	_dispose(s)
	var g := TerrainFixture.new(4)
	_mire(g, 2, 2, 10, 20)
	g.set_block(11, 0, 20, 30, 5)                             # зыбун под уступом в ярус
	var m := _make(g, Vector2(9.5, 10.5), Vector2(11.6, 10.5))
	assert_true(m.leap_clear(m.pos, Vector2(11.6, 10.5)), "the arc itself would clear a one-tier step")
	m.start_hunt()
	r = _strikes(m, 3.0)
	assert_false(r[0], "the ambush does not strike up the step either")
	assert_eq(r[1], 0, "no bites")
	_dispose(m)
	var h := TerrainFixture.new(4)
	_lake(h, 2, 2, 10, 20, 2)                                 # берег вровень с водой
	_mire(h, 6, 2, 6, 20)
	var w := _make(h, Vector2(9.5, 10.5), Vector2(11.6, 10.5))
	w.start_hunt()
	w.step(DT)
	assert_eq(w.state, MireShark.State.WINDUP, "a vehicle on a flush shore is in reach")
	_dispose(w)


## Укус — только на уровне, откуда прыгнул: машина в замахе ушла с него (на уступ рядом, на пути прыжка;
## дуга уступ перелетает) — мимо. Осталась на его уровне — укус.
func test_no_bite_after_the_vehicle_left_its_level() -> void:
	for left: bool in [true, false]:
		var f := TerrainFixture.new(4)
		_mire(f, 2, 2, 11, 20)
		f.set_block(12, 0, 20, 30, 5)                         # уступ в ярус за зыбуном
		var s := _make(f, Vector2(10.5, 10.5), Vector2(11.5, 10.5))
		s.start_hunt()
		s.step(DT)
		assert_eq(s.state, MireShark.State.WINDUP, "vehicle on its level — wind-up")
		s.vehicle.state.pos = Vector2(12.4, 10.5) if left else Vector2(11.7, 10.5)
		var r := _strikes(s, 2.0)
		assert_eq(r[1], 0 if left else 1, "bites only on its level (left: %s)" % left)
		_dispose(s)


## Директор с машиной в (16,5; 16,5) над всюду разлитым озером (дно 2, зеркало 4).
func _lake_director(f: TerrainFixture) -> FaunaDirector:
	for cz in range(-2, 3):
		for cx in range(-2, 3):
			var d: ChunkData = f.terrain.chunks[Vector2i(cx, cz)]
			for i in ChunkData.N * ChunkData.N:
				d.water_level[i] = 4 + Grid.HEIGHT_OFFSET
	var v := Vehicle.new(load("res://data/vehicles/hover.tres"), f.query)
	v.state.pos = Vector2(16.5, 16.5)
	v.state.tile = Vector2i(16, 16)
	var dir := FaunaDirector.new()
	dir.rules = BalanceRules.new()
	dir.rules.nessie_min_level = 99                              # в озере — только илозуб
	dir.vehicle = v
	dir.query = f.query
	dir.terrain = f.terrain
	dir.run_seed = 11
	dir.level = 2
	dir.begin()
	return dir


func _sharks(dir: FaunaDirector) -> Array:
	return dir._creatures.filter(func(c: Creature) -> bool: return c is MireShark)


## Появляется только у зыбуна: в открытом озере без зыбуна — нет (и отладочный --event=shark тоже); есть
## пятно зыбуна — в воде не дальше shark_home_r от него.
func test_spawns_only_near_quicksand() -> void:
	var f := TerrainFixture.new(2, 2)
	var dir := _lake_director(f)
	for _i in 5:
		dir._spawn()
	dir._force(&"shark")
	assert_eq(_sharks(dir).size(), 0, "no mire shark in an open lake")
	_mire(f, 31, 15, 33, 17)                                    # пятно зыбуна в 15 тайлах от машины
	for _i in 5:
		dir._spawn()
	assert_eq(_sharks(dir).size(), 1, "one mire shark at T2 near the quicksand")
	dir._force(&"shark")
	var sharks := _sharks(dir)
	assert_eq(sharks.size(), 2, "--event=shark spawns one too")
	var r := dir.rules.shark_home_r
	for c: Creature in sharks:
		var t := Grid.tile_of_world(c.pos.x, c.pos.y)
		assert_true(t.x >= 31 - r and t.x <= 33 + r and t.y >= 15 - r and t.y <= 17 + r,
				"within shark_home_r of the quicksand: %s" % c.pos)
	assert_true((sharks[1] as Creature).aggressive, "the forced one hunts")
	var d := (sharks[0] as Creature).pos.distance_to(dir.vehicle.state.pos)
	assert_true(d >= dir.rules.shark_spawn_min - 1.0 and d <= dir.rules.shark_spawn_max + 1.0, "in the ring: %.1f" % d)
	dir.vehicle.free()
	dir.free()
