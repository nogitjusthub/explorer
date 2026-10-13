extends TestCase
## Водоворот топит (GDD §5.6): ховер в ядре уходит в воду лишь отчасти и болтается, колёсная машина —
## целиком; угасая, воронка отпускает живую машину плавно, утонувшую — нет.

const DT := 1.0 / 60.0


func _cls(id: StringName) -> VehicleClass:
	return load("res://data/vehicles/%s.tres" % id)


## Котловина 11×11 тайлов на ярусе 1, вода на ярусе 4; водоворот в середине, ховер — в его ядре.
func _setup() -> Array:
	var f := TerrainFixture.new(4)
	f.set_block(0, 0, 10, 10, 1)
	for tz in range(0, 11):
		for tx in range(0, 11):
			f.set_water(tx, tz, 4)
	var v := Vehicle.new(_cls(&"hover"), f.query)
	var w := Whirlpool.new()
	w.rules = BalanceRules.new()
	w.vehicle = v
	w.query = f.query
	w.rng = RandomNumberGenerator.new()
	w.rng.seed = 2
	(Engine.get_main_loop() as SceneTree).root.add_child(w)
	w.begin(Vector2(5, 5))
	return [f, v, w]


## Шаг водоворота, машина — в центре воронки (её затянуло).
func _step(v: Vehicle, w: Whirlpool) -> void:
	v.state.pos = w.pos
	v.state.tile = Grid.tile_of_world(w.pos.x, w.pos.y)
	w.step(DT)


func test_sink_depth_by_class() -> void:
	assert_eq(Whirlpool.sink_depth(_cls(&"hover"), 1.0), Whirlpool.HOVER_SINK, "ховер — отчасти")
	assert_eq(Whirlpool.sink_depth(_cls(&"rover"), 1.0), 1.0, "без подушки — целиком")
	assert_eq(Whirlpool.sink_depth(_cls(&"tank"), 1.0), 1.0, "без подушки — целиком")
	assert_near(Whirlpool.sink_depth(_cls(&"hover"), 0.5), Whirlpool.HOVER_SINK * 0.5, 1e-6, "слабеющая воронка отпускает")
	assert_near(Whirlpool.sink_step(0.0, 1.0, 0.75), 0.75 / Whirlpool.SINK_S, 1e-6, "вниз — за SINK_S")
	assert_near(Whirlpool.sink_step(0.4, 0.3, 1.0), 0.3, 1e-6, "вверх — не выше цели")


func test_hover_half_sinks_churns_and_surfaces_smoothly() -> void:
	var setup := _setup()
	var v: Vehicle = setup[1]
	var w: Whirlpool = setup[2]
	var s := v.state
	for i in roundi((w.rules.whirlpool_form_s + 3.0) / DT):
		_step(v, w)
	assert_near(s.pull_under, Whirlpool.HOVER_SINK, 1e-4, "ховер в ядре — не глубже HOVER_SINK")
	assert_near(s.churn, 1.0, 1e-4, "и его болтает")
	var worst_rise := 0.0
	var frames := 0
	while not w.finished and frames < roundi(60.0 / DT):
		var before := s.pull_under
		_step(v, w)
		worst_rise = maxf(worst_rise, before - s.pull_under)
		frames += 1
	assert_true(w.finished, "воронка угасла")
	assert_eq(s.pull_under, 0.0, "живая машина всплыла")
	assert_eq(s.churn, 0.0, "болтанка стихла")
	assert_true(worst_rise <= DT / Whirlpool.SURFACE_S + 1e-5, "всплывает плавно, без рывка (%.4f за кадр)" % worst_rise)
	w.free()
	v.free()


func test_drowned_vehicle_stays_under() -> void:
	var setup := _setup()
	var v: Vehicle = setup[1]
	var w: Whirlpool = setup[2]
	var s := v.state
	for i in roundi((w.rules.whirlpool_form_s + 3.0) / DT):
		_step(v, w)
	EventBus.vehicle_died.emit(&"whirlpool")
	var at_death := s.pull_under
	assert_eq(s.churn, 0.0, "утонула — не болтается")
	var frames := 0
	while not w.finished and frames < roundi(60.0 / DT):
		_step(v, w)
		frames += 1
	assert_true(w.finished, "воронка угасла")
	assert_true(s.pull_under >= at_death, "утонувшая не всплывает (%.2f)" % s.pull_under)
	w.free()
	v.free()


func test_ride_churns_hover_body() -> void:
	# Болтанка в ядре — заметно сильнее обычного колыхания ховера на подушке.
	var cls := _cls(&"hover")
	var amp := []
	for churn in [0.0, 1.0]:
		var m := VehicleModels.build(&"hover")
		var ride := VehicleRide.new()
		var s := VehicleState.new()
		s.churn = churn
		var top := 0.0
		for i in 240:
			ride.update(DT, m, s, cls, 0, true, Vector2.ZERO)
			top = maxf(top, absf(m.body.transform.origin.y) + absf(m.body.rotation.x) + absf(m.body.rotation.z))
		amp.append(top)
		m.root.free()
	assert_true(amp[1] > amp[0] * 2.0, "в ядре болтает (%.3f против %.3f)" % [amp[1], amp[0]])
