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
	assert_true(n.hears_vehicle(Vector2(19.0, 0.0)), "full speed is heard at 20 tiles")
	n.update_vehicle(Vector2.ZERO, 6.5 * 0.4, 6.5)
	assert_false(n.hears_vehicle(Vector2(12.0, 0.0)), "half noise — half range")
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
