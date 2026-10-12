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


## Скакун — помесь «Чужого» и раптора (GDD §5.4): модель ростом 0,35–0,45, длиной около 0,5 (в игре × SIZE), хвост
## короткий; модель лёгкая, меши общие на стаю. Стоя — ноги на земле; крик — на дыбах с разинутой пастью;
## на бегу ноги ходят враз и корпус наклонён; укус — передний бросается вперёд.
func test_hopper_model_and_poses() -> void:
	var f := TerrainFixture.new(4)
	var pack := HopperPack.new()
	pack.rules = BalanceRules.new()
	pack.query = f.query
	pack.rng = RandomNumberGenerator.new()
	pack.rng.seed = 3
	pack.setup(Vector2(5.5, 5.5), 3)
	var front: Dictionary = pack._members[0]
	var m: Dictionary = pack._members[1]
	var parts: Array[Node] = (m["node"] as Node).find_children("*", "MeshInstance3D", true, false)
	assert_true(parts.size() <= 18, "light model: %d parts" % parts.size())
	assert_true((m["body"] as MeshInstance3D).mesh == (front["body"] as MeshInstance3D).mesh, "meshes shared by the pack")
	var box := _model_box(m["node"])
	assert_near(box.position.y, 0.0, 0.02, "feet on the ground")
	assert_true(box.end.y > 0.35 and box.end.y < 0.45, "height %.2f (model units, before SIZE)" % box.end.y)
	assert_true(box.size.z > 0.4 and box.size.z < 0.6, "length %.2f (model units, before SIZE)" % box.size.z)
	var tail: Node3D = m["tail"]
	var tail_box := _part_box(tail, (m["body"] as Node3D).transform * tail.transform)
	assert_true(tail_box.size.z < (box.size.z - tail_box.size.z) * 0.55, "short tail: %.2f" % tail_box.size.z)
	var head_y := _head_y(m)

	pack.state = HopperPack.State.ALERT
	pack._timer = 0.3
	for i in 30:
		pack._place_all(1.0 / 60.0)
	assert_true((m["jaw"] as Node3D).rotation.x < -0.5, "the scream: jaw open")
	assert_true((m["throat"] as Node3D).visible, "red mouth shows")
	assert_true(_head_y(m) > head_y + 0.05, "rears up")

	pack.state = HopperPack.State.CHASE
	pack._heading = Vector2(0.0, -1.0)
	var gap := 0.0
	var lean := 0.0
	for i in 60:
		pack.pos += Vector2(0.0, -1.0) * pack.rules.hopper_speed / 60.0
		pack._moving = true
		pack._place_all(1.0 / 60.0)
		var feet: Array = m["feet"]
		gap = maxf(gap, absf((feet[0] as Node3D).position.y - (feet[1] as Node3D).position.y))
		lean = minf(lean, (m["body"] as Node3D).rotation.x)
	assert_true(gap > 0.03, "legs alternate: %.3f" % gap)
	assert_true(lean < -0.2, "leans forward in the chase")

	pack._moving = false
	for i in 60:
		pack._place_all(1.0 / 60.0)
	var at := (front["node"] as Node3D).position
	pack._lunge = HopperPack.LUNGE_S
	for i in 9:
		pack._lunge -= 1.0 / 60.0
		pack._place_all(1.0 / 60.0)
	var thrown := (front["node"] as Node3D).position - at
	assert_true(-thrown.z > HopperPack.LUNGE_LEN * 0.8, "the front one lunges: %.2f" % -thrown.z)
	assert_true((front["jaw"] as Node3D).rotation.x < -0.4, "biting with the jaw open")
	pack.free()


## Габариты модели особи в её осях (от корня, без его разворота).
func _model_box(root: Node3D) -> AABB:
	var acc: Array = [null]
	for c in root.get_children():
		_gather_box(c, (c as Node3D).transform, acc)
	return acc[0]


func _part_box(part: Node3D, xf: Transform3D) -> AABB:
	var acc: Array = [null]
	_gather_box(part, xf, acc)
	return acc[0]


func _gather_box(n: Node3D, xf: Transform3D, acc: Array) -> void:
	if n is MeshInstance3D and n.visible:
		var b := xf * (n as MeshInstance3D).get_aabb()
		acc[0] = b if acc[0] == null else (acc[0] as AABB).merge(b)
	for c in n.get_children():
		_gather_box(c, xf * (c as Node3D).transform, acc)


func _head_y(m: Dictionary) -> float:
	return ((m["body"] as Node3D).transform * (m["head"] as Node3D).transform).origin.y
