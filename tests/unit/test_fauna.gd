extends TestCase
## Фауна (GDD §5.4): шум, поле путей по проходимости вида.


func _field(f: TerrainFixture, mode: FlowField.Mode, target: Vector2i) -> FlowField:
	var result: Array[FlowField] = []
	var job := FlowField.build(f.query, mode, target, func(field: FlowField) -> void: result.append(field))
	while not job.step(Time.get_ticks_usec() + 1_000_000):
		pass
	job.on_done()
	return result[0]


func test_noise_scales_with_speed_and_events() -> void:
	var n := NoiseField.new()
	n.update_vehicle(Vector2.ZERO, 6.5 * 0.8, 6.5)
	assert_true(n.hears_vehicle(Vector2(11.0, 0.0)), "full speed is heard at 12 tiles")
	assert_false(n.hears_vehicle(Vector2(13.0, 0.0)), "and no farther")
	n.update_vehicle(Vector2.ZERO, 6.5 * 0.4, 6.5)
	assert_false(n.hears_vehicle(Vector2(7.0, 0.0)), "half noise — half range")
	n.add(Vector2(50.0, 0.0), 30.0, 20.0)
	assert_eq(n.heard_source(Vector2(70.0, 0.0)), Vector2(50.0, 0.0))
	n.tick(21.0)
	assert_eq(n.heard_source(Vector2(70.0, 0.0)), null, "event noise fades")


func test_hoppers_go_around_walls_and_not_through_water() -> void:
	var f := TerrainFixture.new(4)
	# Стена в ярус поперёк пути с проходом по склону у z = 20; озеро — в стороне.
	for tz in range(0, 30):
		if tz != 20:
			f.set_flat(12, tz, 5)
	f.set_tile(12, 20, 4, 5, 5, 4)
	for tz in range(0, 30):
		f.set_flat(13, tz, 5)
	var field := _field(f, FlowField.Mode.HOPPER, Vector2i(20, 10))
	var start := Vector2i(5, 10)
	assert_true(field.distance(start) > 15 + 5, "detour around the wall: %d" % field.distance(start))
	# Шагаем по полю — дошли до цели.
	var t := start
	for _i in 200:
		t = field.next_tile(f.query, t)
	assert_eq(t, Vector2i(20, 10), "reached the target")
	f.set_flat(30, 10, 2)
	f.set_water(30, 10, 4)
	var wet := _field(f, FlowField.Mode.HOPPER, Vector2i(20, 10))
	assert_eq(wet.distance(Vector2i(30, 10)), FlowField.UNREACHED, "hoppers avoid water")


func test_rover_and_hover_outrun_fauna_tank_does_not() -> void:
	# GDD §5.4: скорости погони — быстрее танка, медленнее ровера и ховера.
	var r := BalanceRules.new()
	var tank: VehicleClass = load("res://data/vehicles/tank.tres")
	var rover: VehicleClass = load("res://data/vehicles/rover.tres")
	var hover: VehicleClass = load("res://data/vehicles/hover.tres")
	for s: float in [r.hopper_speed, r.worm_speed, r.shellback_speed, r.shellback_charge_speed]:
		assert_true(s > tank.max_speed, "fauna %.1f catches the tank (%.1f)" % [s, tank.max_speed])
		assert_true(s < rover.max_speed and s < hover.max_speed, "rover and hover outrun fauna %.1f" % s)


func test_creature_loses_interest_without_progress() -> void:
	var c := Creature.new()
	c.rules = BalanceRules.new()
	var dt := 0.1
	# Подбирается: расстояние сокращается — интерес не теряет.
	var d := 20.0
	for _i in 100:
		d -= 0.5
		assert_false(c.lost_interest(dt, maxf(d, 1.0), d <= 1.0), "approaching keeps interest")
	# Машина уходит (или недостижима): ближе не становится — сдаётся через fauna_give_up_s.
	var t := 0.0
	while not c.lost_interest(dt, 5.0 + t):
		t += dt
		assert_true(t < c.rules.fauna_give_up_s + 1.0, "gives up in time")
	assert_near(t, c.rules.fauna_give_up_s, 0.2, "gives up after fauna_give_up_s")
	c.free()
