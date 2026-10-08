extends TestCase
## Челноки (GDD §2.3): расписание основного, выбор площадки по дистанции, окно и удержание меню,
## аварийный челнок и выбор тайла посадки.


func _fixed_pad(pad: Vector3i) -> Callable:
	return func(_pos: Vector2, _d: float) -> Vector3i: return pad


func test_schedule_intervals_and_distances() -> void:
	var s := ShuttleScheduler.new(BalanceRules.new(), _fixed_pad(ShuttleScheduler.NO_PAD))
	assert_eq(s.interval(0), 90.0)
	assert_eq(s.interval(1), 120.0)
	assert_eq(s.interval(5), 180.0, "capped")
	assert_eq(s.distance(0), 25.0)
	assert_eq(s.distance(2), 55.0)
	assert_eq(s.distance(9), 70.0, "capped")


func test_announce_land_hold_depart() -> void:
	var rules := BalanceRules.new()
	var pad := Vector3i(10, 20, 5)
	var s := ShuttleScheduler.new(rules, _fixed_pad(pad))
	var events: Array[String] = []
	s.announced.connect(func(_p: Vector3i) -> void: events.append("announced"))
	s.landed.connect(func(_p: Vector3i) -> void: events.append("landed"))
	s.departed.connect(func() -> void: events.append("departed"))
	s.tick(59.0, Vector2.ZERO, false)
	assert_false(s.has_pad(), "pad unknown until 30 s before landing")
	s.tick(1.5, Vector2.ZERO, false)
	assert_true(s.has_pad())
	assert_eq(events, ["announced"] as Array[String])
	s.tick(30.0, Vector2.ZERO, false)
	assert_eq(s.state, ShuttleScheduler.State.LANDED)
	assert_near(s.time_left, rules.shuttle_window_s, 0.6)
	assert_true(s.in_zone(Vector2(11.5, 20.5)), "zone radius 2 around the pad center")
	assert_false(s.in_zone(Vector2(13.5, 20.5)))
	s.tick(100.0, Vector2(10.5, 20.5), true)
	assert_eq(s.state, ShuttleScheduler.State.LANDED, "window holds while the menu is open")
	s.tick(rules.shuttle_window_s, Vector2.ZERO, false)
	assert_eq(s.state, ShuttleScheduler.State.WAITING)
	assert_eq(s.k, 1)
	assert_eq(s.time_left, 120.0, "next interval counts from departure")
	assert_false(s.has_pad())
	assert_eq(events, ["announced", "landed", "departed"] as Array[String])


func test_landing_skipped_without_pad() -> void:
	var s := ShuttleScheduler.new(BalanceRules.new(), _fixed_pad(ShuttleScheduler.NO_PAD))
	s.tick(91.0, Vector2.ZERO, false)
	assert_eq(s.state, ShuttleScheduler.State.WAITING)
	assert_eq(s.k, 1)


func test_find_pad_near_target_distance() -> void:
	var gen := TerrainGenerator.new(4, TerrainParams.new())
	var pos := Vector2(10, 10)
	for target in [25.0, 70.0]:
		var pad := ShuttleScheduler.find_pad(gen, pos, target)
		assert_true(pad.z != TerrainGenerator.NO_PAD, "pad found for %.0f" % target)
		var d := pos.distance_to(Vector2(pad.x + 0.5, pad.y + 0.5))
		# Площадки стоят по одной на блок 64×64 — промах до половины диагонали блока.
		assert_true(absf(d - target) < 46.0, "pad at %.0f for target %.0f" % [d, target])


func test_emergency_call_flow() -> void:
	var e := EmergencyCall.new(BalanceRules.new())
	assert_true(e.call_in())
	assert_false(e.call_in(), "one emergency shuttle at a time")
	assert_false(e.tick(9.9))
	assert_true(e.tick(0.2), "lands after 10 s")
	assert_true(e.is_busy())
	e.tick(EmergencyCall.STAY_S + 0.1)
	assert_false(e.is_busy())
	assert_true(e.call_in(), "can be called again")


func test_emergency_landing_tile_is_dry_and_flat_edges() -> void:
	var terrain := TerrainData.new()
	var gen := TerrainGenerator.new(4, TerrainParams.new())
	for cz in range(-1, 2):
		for cx in range(-1, 2):
			terrain.add_chunk(gen.generate(Vector2i(cx, cz)))
	var q := TerrainQuery.new(terrain)
	var found := 0
	for i in 40:
		var pos := Vector2(-20 + i * 1.3 + 0.5, 8.5 - i * 0.7)
		var t := EmergencyCall.landing_tile(q, pos)
		if t == EmergencyCall.NO_TILE:
			continue
		found += 1
		assert_true(t != Grid.tile_of_world(pos.x, pos.y), "not under the vehicle")
		assert_true(pos.distance_to(Vector2(t.x + 0.5, t.y + 0.5)) <= 3.5)
		assert_eq(q.water_tier(t.x, t.y), TerrainQuery.NO_WATER)
		for dir in 4:
			assert_eq(q.edge_rise(t.x, t.y, dir), 0)
			assert_eq(q.edge_drop(t.x, t.y, dir), 0)
	assert_true(found > 20, "usually there is a place to land: %d of 40" % found)
