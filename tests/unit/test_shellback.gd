extends TestCase
## Панцирник (GDD §5.4): ходит только склонами и посуху; территориальный — гонит машину только у своего
## места; протаранил — отстаёт и уходит к себе.

const DT := 1.0 / 60.0


## FaunaDirector для одного зверя: готовое поле путей к машине.
class StubDirector:
	extends Node
	var f: FlowField

	func field(_mode: FlowField.Mode) -> FlowField:
		return f


func _field(f: TerrainFixture, target: Vector2i) -> FlowField:
	var result: Array[FlowField] = []
	var job := FlowField.build(f.query, FlowField.Mode.SHELLBACK, target, func(field: FlowField) -> void: result.append(field))
	var steps := 0
	while not job.step(Time.get_ticks_usec() + 1_000_000):
		steps += 1
		if steps >= 64:              # с бюджетом в секунду поле строится за шаг — зависшая задача не вечна
			fail("FlowField.build: job not done after %d steps" % steps)
			return null
	job.on_done()
	return result[0]


func _make(f: TerrainFixture, at: Vector2, vehicle_at: Vector2) -> Shellback:
	var v := Vehicle.new(load("res://data/vehicles/tank.tres"), f.query)
	v.state.pos = vehicle_at
	v.state.tile = Grid.tile_of_world(vehicle_at.x, vehicle_at.y)
	var s := Shellback.new()
	s.rules = BalanceRules.new()
	s.vehicle = v
	s.query = f.query
	s.terrain = f.terrain
	s.noise = NoiseField.new()
	s.noise.update_vehicle(vehicle_at, v.cls.max_speed, v.cls.max_speed)     # машина шумит — слышно
	var d := StubDirector.new()
	d.f = _field(f, v.state.tile)
	s.director = d
	s.rng = RandomNumberGenerator.new()
	s.rng.seed = 7
	s.setup(at)
	(Engine.get_main_loop() as SceneTree).root.add_child(s)     # пыль живёт в мировых координатах
	return s


func _dispose(s: Shellback) -> void:
	s.vehicle.free()
	s.director.free()
	s.free()


func test_walks_only_dry_slopes() -> void:
	var f := TerrainFixture.new(4)
	f.set_flat(12, 10, 3)
	f.set_water(12, 10, 4)          # мель глубиной 1 — танк прошёл бы вброд
	f.set_flat(10, 14, 5)           # стенка в ярус
	var field := _field(f, Vector2i(5, 10))
	assert_eq(field.distance(Vector2i(12, 10)), FlowField.UNREACHED, "no wading")
	assert_true(field.distance(Vector2i(11, 10)) > 0, "dry ground next to it is reachable")
	assert_eq(field.distance(Vector2i(10, 14)), FlowField.UNREACHED, "no climbing a wall")


func test_rams_once_then_backs_off_home() -> void:
	var f := TerrainFixture.new(4)
	var home := Vector2(5.5, 10.5)
	var s := _make(f, home, Vector2(10.5, 10.5))
	var hits := [0]
	s.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	for _i in 600:
		s.step(DT)
		if hits[0] > 0 and not s.aggressive:
			break
	assert_eq(hits[0], 1, "rammed the vehicle")
	assert_false(s.aggressive, "backs off after the ram")
	# Отстал: машина рядом и шумит, но он не слышит её shellback_calm_s и уходит к своему месту.
	var far := s.pos.distance_to(home)
	for _i in int(s.rules.shellback_calm_s * 0.8 / DT):
		s.step(DT)
		assert_false(s.aggressive, "calm for shellback_calm_s")
	assert_true(s.pos.distance_to(home) < maxf(far, Shellback.WANDER_R + 0.5), "went back home")
	assert_eq(hits[0], 1, "no second ram")
	_dispose(s)


## Испуг (calm_down) посреди рытья: пыль стихает, корпус перестаёт дрожать — и не дрожит потом.
func test_calm_down_mid_dig_stops_the_dust_and_the_tremble() -> void:
	var f := TerrainFixture.new(4)
	var s := _make(f, Vector2(5.5, 10.5), Vector2(8.5, 10.5))
	s.state = Shellback.State.APPROACH
	s.aggressive = true
	var t := 0.0
	while s.state != Shellback.State.DIG and t < 2.0:
		s.step(DT)
		t += DT
	assert_eq(s.state, Shellback.State.DIG, "digs before the charge")
	for _i in 5:
		s.step(DT)
	assert_true(s._dust.emitting, "dust while digging")
	assert_true(absf(s._model.rotation.z) > 0.0, "trembles while digging")
	s.calm_down()
	assert_false(s._dust.emitting, "the dust stops")
	assert_eq(s._model.rotation.z, 0.0, "the shell stops trembling")
	for _i in 30:
		s.step(DT)
	assert_eq(s.state, Shellback.State.IDLE, "calm")
	assert_false(s._dust.emitting, "no dust afterwards")
	assert_eq(s._model.rotation.z, 0.0, "no tremble afterwards")
	_dispose(s)


func test_chases_only_on_its_territory() -> void:
	var f := TerrainFixture.new(4)
	var home := Vector2(5.5, 10.5)
	var r := BalanceRules.new()
	var off := home + Vector2(r.shellback_territory_r + 3.0, 0.0)
	var s := _make(f, home, off)
	s.noise.noise_range = 100.0               # слышит издалека — дело только в территории
	for _i in 120:
		s.step(DT)
	assert_false(s.aggressive, "vehicle off its territory is ignored")
	# Погоня началась (машина подъехала), машина ушла с территории — отстаёт.
	s.vehicle.state.pos = home + Vector2(r.shellback_charge_dist + 4.0, 0.0)
	s.step(DT)
	assert_true(s.aggressive, "vehicle on its territory — chase")
	s.vehicle.state.pos = off
	s.step(DT)
	assert_false(s.aggressive, "vehicle left its territory — gives up")
	_dispose(s)
