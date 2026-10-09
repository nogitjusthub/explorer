extends TestCase
## Угрозы (GDD §5, §7.1): уровень угрозы, паузы погоды, профиль разлома.


func test_threat_level_grows_with_time_and_distance() -> void:
	var r := BalanceRules.new()
	assert_eq(ThreatDirector.threat_level(r, 0.0, 0.0), 1)
	assert_eq(ThreatDirector.threat_level(r, 90.0, 0.0), 2)
	assert_eq(ThreatDirector.threat_level(r, 200.0, 600.0), 4)
	assert_eq(ThreatDirector.threat_level(r, 2000.0, 5000.0), 6, "capped")


func test_weather_pauses_shrink_with_level() -> void:
	var r := BalanceRules.new()
	assert_near(ThreatDirector.clear_duration(r, 1, 0.5), r.clear_t1_s, 1e-3)
	assert_near(ThreatDirector.clear_duration(r, 6, 0.5), r.clear_t6_s, 1e-3)
	assert_true(ThreatDirector.clear_duration(r, 4, 1.0) < ThreatDirector.clear_duration(r, 2, 0.0) + 20.0)
	assert_true(ThreatDirector.quake_interval(r, 4, 0.5) < ThreatDirector.quake_interval(r, 3, 0.5), "regular from T4")


func test_fault_profile() -> void:
	# На линии: сторона «+» поднята на up, «−» опущена на down; на пандусе стороны совпадают.
	assert_eq(Deformation.fault_delta(10, 0, true, false, 20, 3, 2), 3)
	assert_eq(Deformation.fault_delta(10, 0, false, false, 20, 3, 2), -2)
	assert_eq(Deformation.fault_delta(10, 0, true, true, 20, 3, 2), Deformation.fault_delta(10, 0, false, true, 20, 3, 2))
	# Спад к краю полосы — не круче яруса на тайл, к концам линии — на нет.
	for s in range(0, 10):
		assert_true(absi(Deformation.fault_delta(10, s + 1, true, false, 20, 3, 2) - Deformation.fault_delta(10, s, true, false, 20, 3, 2)) <= 1)
	assert_eq(Deformation.fault_delta(0, 0, true, false, 20, 3, 2), 0)
	assert_eq(Deformation.fault_delta(20, 0, true, false, 20, 3, 2), 0)


func test_weather_front_density_and_creep() -> void:
	var front := WeatherFront.new()
	front.rules = BalanceRules.new()
	front.radius = 20.0
	front.rules.murk_max_s = 1000.0
	front.center = Vector2(100.0, 0.0)
	assert_near(front.density(Vector2(100.0, 0.0)), 1.0, 1e-3, "dense in the middle")
	assert_eq(front.density(Vector2(140.0, 0.0)), 0.0, "nothing far outside")
	# Масса ползёт: точка, до которой край не дошёл, со временем оказывается внутри.
	var p := Vector2(70.0, 0.0)
	var before := front.density(p)
	front.center += Vector2(-1.0, 0.0) * 25.0
	assert_true(front.density(p) > before + 0.5, "front creeps in")
	# Кислотный: выше уровня газа плотность сходит на нет.
	front.gas_y = 3.0
	assert_true(front.density(Vector2(85.0, 0.0), 2.0) > 0.8)
	assert_eq(front.density(Vector2(85.0, 0.0), 5.0), 0.0, "no gas on a plateau")
	front.free()


func test_murk_variant_roll() -> void:
	var r := BalanceRules.new()
	var plains := ChunkData.Biome.PLATEAU
	assert_eq(ThreatDirector.murk_variant(r, 1, plains, 0.99), WeatherFront.Variant.FOG, "T1: only fog")
	var seen := {}
	for i in 100:
		seen[ThreatDirector.murk_variant(r, 3, plains, i / 100.0)] = true
	assert_eq(seen.size(), 3, "T3: fog, acid and dust are all possible")
	var lake_dust := 0
	var open_dust := 0
	for i in 100:
		if ThreatDirector.murk_variant(r, 3, ChunkData.Biome.LAKESIDE, i / 100.0) == WeatherFront.Variant.DUST:
			lake_dust += 1
		if ThreatDirector.murk_variant(r, 3, ChunkData.Biome.CRATERS, i / 100.0) == WeatherFront.Variant.DUST:
			open_dust += 1
	assert_true(open_dust > lake_dust, "dust storms prefer open land")


func test_acid_gas_settles_in_lowlands() -> void:
	var f := TerrainFixture.new(6)
	f.set_block(14, 8, 16, 12, 3)    # низина в поле зрения
	assert_eq(WeatherFront.gas_level(f.query, Vector2(10.5, 10.5), 12), 3)


func test_tornado_throws_where_landing_is_not_higher() -> void:
	var f := TerrainFixture.new(6)
	f.set_block(12, 0, 30, 30, 9)    # к востоку — высокое плато
	var target := Tornado.throw_target(f.query, Vector2(10.5, 10.5), 4.0, 0.0)
	assert_true(f.query.surface_tier(target.x, target.y) <= 6.0, "not onto the plateau: %s" % target)
	assert_near(target.distance_to(Vector2(10.5, 10.5)), 4.0, 1e-3)


func test_fault_polyline_shape() -> void:
	# GDD §5.3: 1–4 отрезка не короче 5 тайлов, угол между соседними 135…180°, сгибы чередуются.
	var rng := RandomNumberGenerator.new()
	var counts := {}
	for k in 60:
		rng.seed = k
		var length := 12.0 + k % 23
		var path := Quake.make_path(Vector2(100, -40), rng.randf() * TAU, length, rng)
		var lengths := FaultLine.path_lengths(path)
		assert_near(lengths[lengths.size() - 1], length, 0.01, "total length")
		assert_true(FaultLine.path_bounds(path).grow(0.5).has_point(Vector2(100, -40)), "placed around the center")
		var n := path.size() - 1
		counts[n] = true
		assert_true(n >= 1 and n <= 4, "1–4 segments: %d" % n)
		var prev_turn := 0.0
		for i in n:
			assert_true(path[i].distance_to(path[i + 1]) >= Quake.SEGMENT_MIN - 0.01, "segment ≥ 5 tiles")
			if i > 0:
				var turn := (path[i] - path[i - 1]).angle_to(path[i + 1] - path[i])
				assert_true(absf(turn) <= deg_to_rad(Quake.MAX_BEND) + 1e-4, "bend ≤ 45°")
				if i > 1 and absf(turn) > 1e-3 and absf(prev_turn) > 1e-3:
					assert_true(signf(turn) != signf(prev_turn), "bends alternate")
				prev_turn = turn
	assert_true(counts.size() >= 3, "several segment counts seen: %s" % [counts.keys()])
	# Знак расстояния: слева от направления — «+».
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var cc := FaultLine.path_coords(line, FaultLine.path_lengths(line), Vector2(5, 2))
	assert_near(cc.x, 5.0, 1e-4, "along")
	assert_near(cc.y, 2.0, 1e-4, "signed distance")
