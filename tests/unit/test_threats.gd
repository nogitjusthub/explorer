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
