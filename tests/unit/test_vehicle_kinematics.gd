extends TestCase
## Кинематика машины (GDD §3.2, §4): урон от падений, топливо, стенки, обрывы, вода, деревья.

const DT := 1.0 / 60.0


func _rover() -> VehicleClass:
	return load("res://data/vehicles/rover.tres")


func _hover() -> VehicleClass:
	var cls := _rover().duplicate() as VehicleClass
	cls.fall_damage_mode = "linear"
	cls.fall_damage_base = 5.0
	cls.max_water_depth = -1
	cls.hovers = true
	return cls


func _state(f: TerrainFixture, cls: VehicleClass, pos: Vector2, heading: float) -> VehicleState:
	var s := VehicleState.new()
	s.pos = pos
	s.heading = heading
	s.tile = Grid.tile_of_world(pos.x, pos.y)
	s.y = VehicleKinematics.ground_y(s, cls, f.query)
	return s


func _drive(s: VehicleState, inp: Vector2, cls: VehicleClass, f: TerrainFixture, steps: int) -> Array[VehicleKinematics.StepResult]:
	var results: Array[VehicleKinematics.StepResult] = []
	for _i in steps:
		results.append(VehicleKinematics.step(s, inp, cls, f.query, DT))
	return results


func test_fall_damage_table() -> void:
	var rover := _rover()
	var hover := _hover()
	var expected_rover := {1: 0, 2: 20, 3: 40, 4: 80, 5: 160}
	var expected_hover := {1: 0, 2: 5, 3: 10, 4: 15, 8: 35}
	for h: int in expected_rover:
		assert_eq(VehicleKinematics.fall_damage(rover, h), expected_rover[h], "rover h=%d" % h)
	for h: int in expected_hover:
		assert_eq(VehicleKinematics.fall_damage(hover, h), expected_hover[h], "hover h=%d" % h)


func test_fuel_rate() -> void:
	var rover := _rover()
	assert_near(VehicleKinematics.fuel_per_second(rover, 0.0) * 60.0, 3.0)
	assert_near(VehicleKinematics.fuel_per_second(rover, 1.0) * 60.0, 15.0)
	assert_near(VehicleKinematics.fuel_per_second(rover, 0.5) * 60.0, 9.0)


func test_accelerates_to_max_speed_on_flat() -> void:
	var f := TerrainFixture.new()
	var rover := _rover()
	var s := _state(f, rover, Vector2(5.5, 10.5), 0.0)
	_drive(s, Vector2.RIGHT, rover, f, 150)
	assert_near(s.vel.length(), rover.max_speed, 0.01)


func test_wall_up_blocks_everyone() -> void:
	var f := TerrainFixture.new(4)
	f.set_block(14, 0, 20, 30, 5)   # уступ в 1 ярус к востоку от x = 14
	var s := _state(f, _rover(), Vector2(8.5, 10.5), 0.0)
	var results := _drive(s, Vector2.RIGHT, _rover(), f, 120)
	assert_true(s.pos.x <= 14.0 - VehicleKinematics.RADIUS + 1e-3, "stopped before the wall, x=%.3f" % s.pos.x)
	assert_true(results.any(func(r: VehicleKinematics.StepResult) -> bool: return r.hit_wall), "hit_wall reported")
	assert_false(s.falling)


func test_partial_wall_passable_near_low_end() -> void:
	# Ребро 13→14: у северного конца перепада нет, у южного — ярус. Тайл 14 — склон на юг.
	var f := TerrainFixture.new(4)
	for tz in range(0, 30):
		f.set_tile(14, tz, 4, 4, 5, 5)
	var rover := _rover()
	var near_low := _state(f, rover, Vector2(10.5, 10.12), 0.0)
	_drive(near_low, Vector2.RIGHT, rover, f, 90)
	assert_true(near_low.pos.x > 14.5, "passed the low end of a partial wall, x=%.2f" % near_low.pos.x)
	var near_high := _state(f, rover, Vector2(10.5, 10.85), 0.0)
	_drive(near_high, Vector2.RIGHT, rover, f, 90)
	assert_true(near_high.pos.x < 14.0, "blocked at the high end, x=%.2f" % near_high.pos.x)


func test_turns_around_in_dead_end() -> void:
	# Тупик: стенки на севере, западе и востоке, выход на юг. Ровер смотрит в стенку.
	var f := TerrainFixture.new(4)
	f.set_flat(10, 9, 6)
	f.set_flat(9, 10, 6)
	f.set_flat(11, 10, 6)
	var rover := _rover()
	var s := _state(f, rover, Vector2(10.5, 10.4), -PI * 0.5)
	_drive(s, Vector2.UP, rover, f, 30)          # упирается в северную стенку
	_drive(s, Vector2.DOWN, rover, f, 180)       # разворот и выезд на юг
	assert_true(s.pos.y > 12.0, "left the dead end, z=%.2f" % s.pos.y)


func test_slides_along_wall() -> void:
	var f := TerrainFixture.new(4)
	f.set_block(14, 0, 20, 30, 6)
	var s := _state(f, _rover(), Vector2(13.5, 10.5), 0.0)
	# Давим по диагонали в стенку: машина (сначала доворачивает с места) скользит вдоль неё по z.
	_drive(s, Vector2(1, 1).normalized(), _rover(), f, 90)
	assert_true(s.pos.y > 12.0, "slid along the wall, z=%.2f" % s.pos.y)
	assert_true(s.pos.x < 14.0, "did not pass the wall")


func test_fall_into_adjacent_tile_with_damage() -> void:
	var f := TerrainFixture.new(4)
	f.set_block(14, 0, 20, 30, 1)   # обрыв в 3 яруса
	var s := _state(f, _rover(), Vector2(11.5, 10.5), 0.0)
	var landed: VehicleKinematics.StepResult = null
	for _i in 120:
		var r := VehicleKinematics.step(s, Vector2.RIGHT, _rover(), f.query, DT)
		if r.landed:
			landed = r
			break
	assert_true(landed != null, "landed after falling")
	if landed == null:
		return
	assert_eq(landed.fell_tiers, 3)
	assert_eq(landed.fall_damage, 40)
	assert_eq(Grid.tile_of_world(s.pos.x, s.pos.y), Vector2i(14, 10), "landed strictly in the adjacent tile")


func test_one_tier_ledge_drop_is_free() -> void:
	var f := TerrainFixture.new(4)
	f.set_block(14, 0, 20, 30, 3)
	var s := _state(f, _rover(), Vector2(12.5, 10.5), 0.0)
	var damage := 0
	var landed := false
	for _i in 120:
		var r := VehicleKinematics.step(s, Vector2.RIGHT, _rover(), f.query, DT)
		damage += r.fall_damage
		landed = landed or r.landed
	assert_true(landed)
	assert_eq(damage, 0)


func test_rover_drowns_in_deep_water_hover_crosses() -> void:
	var f := TerrainFixture.new(4)
	for tz in range(0, 30):
		for tx in range(14, 20):
			f.set_flat(tx, tz, 2)
			f.set_water(tx, tz, 5)        # глубина 3 яруса
	# Берег — ровно на уровне дна, чтобы проверять только воду, без обрыва.
	f.set_block(0, 0, 13, 30, 2)
	var rover := _rover()
	var s := _state(f, rover, Vector2(10.5, 10.5), 0.0)
	var drowned := false
	for _i in 300:
		var r := VehicleKinematics.step(s, Vector2.RIGHT, rover, f.query, DT)
		drowned = drowned or r.drowned
	assert_true(s.drowning, "rover entered deep water and is drowning")
	assert_true(drowned, "rover drowned")
	assert_true(s.pos.x < 15.0, "sank near the shore, x=%.2f" % s.pos.x)
	# Ховер держится на зеркале: берег для него — на уровне воды (вода над сухим соседом
	# генератором не допускается, так что «стенка воды» из рельефа выше — только для ровера).
	var g := TerrainFixture.new(5)
	for tz in range(0, 30):
		for tx in range(14, 20):
			g.set_flat(tx, tz, 2)
			g.set_water(tx, tz, 5)
	var hover := _hover()
	var h := _state(g, hover, Vector2(10.5, 10.5), 0.0)
	_drive(h, Vector2.RIGHT, hover, g, 120)
	assert_true(h.pos.x > 15.0, "hover crossed the water, x=%.2f" % h.pos.x)
	assert_near(h.y, 5 * Grid.TIER_H, 1e-3, "hover rides on the water level")


func test_fall_into_deep_water_drowns_without_damage() -> void:
	var f := TerrainFixture.new(4)
	for tz in range(0, 30):
		for tx in range(14, 20):
			f.set_flat(tx, tz, 0)
			f.set_water(tx, tz, 3)        # обрыв 4 яруса в воду глубиной 3
	var rover := _rover()
	var s := _state(f, rover, Vector2(11.5, 10.5), 0.0)
	var damage := 0
	var drowned := false
	for _i in 400:
		var r := VehicleKinematics.step(s, Vector2.RIGHT, rover, f.query, DT)
		damage += r.fall_damage
		drowned = drowned or r.drowned
	assert_eq(damage, 0, "water cushions the fall")
	assert_true(drowned, "rover drowned after falling into deep water")
	assert_eq(s.tile, Vector2i(14, 10), "fell strictly into the adjacent tile")


func test_shallow_water_slows_rover() -> void:
	var f := TerrainFixture.new(4)
	for tz in range(0, 30):
		for tx in range(0, 30):
			f.set_water(tx, tz, 5)        # глубина 1 ярус
	var rover := _rover()
	var s := _state(f, rover, Vector2(5.5, 10.5), 0.0)
	_drive(s, Vector2.RIGHT, rover, f, 120)
	assert_near(s.vel.length(), rover.max_speed * rover.water_speed_mult, 0.01)


func test_tree_blocks_slow_rover_and_falls_at_full_speed() -> void:
	var f := TerrainFixture.new(4)
	f.set_tree(20, 10)
	var rover := _rover()
	# Медленно: старт вплотную — разогнаться до 90% не успевает, упирается.
	var slow := _state(f, rover, Vector2(19.0, 10.5), 0.0)
	_drive(slow, Vector2.RIGHT, rover, f, 30)
	assert_true(f.query.has_standing_tree(20, 10), "tree still standing after a slow push")
	assert_true(slow.pos.x < 20.5 - 0.6, "rover stopped at the tree")
	# С разгона: дерево падает, скорость не выше половины максимума.
	var fast := _state(f, rover, Vector2(5.5, 10.5), 0.0)
	var felled := false
	for _i in 200:
		var r := VehicleKinematics.step(fast, Vector2.RIGHT, rover, f.query, DT)
		if r.felled_tree:
			felled = true
			assert_true(fast.vel.length() <= rover.max_speed * rover.tree_speed_after_frac + 1e-3, "speed capped after felling")
			break
	assert_true(felled, "tree felled at full speed")
	assert_false(f.query.has_standing_tree(20, 10))


func test_uphill_speed_limit() -> void:
	# Пандус на восток: с x = 10 каждый тайл выше на ярус. За тайл подъёма подряд предел −1/6 Vmax, не ниже 1/3.
	var f := TerrainFixture.new(4)
	for tz in range(0, 30):
		for tx in range(10, 22):
			var h := 4 + tx - 10
			f.set_tile(tx, tz, h, h + 1, h + 1, h)
	var rover := _rover()
	var s := _state(f, rover, Vector2(5.5, 10.5), 0.0)
	var max_after_four := 0.0
	for _i in 600:
		VehicleKinematics.step(s, Vector2.RIGHT, rover, f.query, DT)
		if s.pos.x > 15.5 and s.pos.x < 21.0:
			max_after_four = maxf(max_after_four, s.vel.length())
		if s.pos.x >= 21.0:
			break
	assert_true(s.uphill_tiles >= 4, "uphill tiles counted: %d" % s.uphill_tiles)
	assert_true(max_after_four <= rover.max_speed / 3.0 + 1e-3, "speed on a long climb: %.2f" % max_after_four)


func test_no_input_slows_down() -> void:
	var f := TerrainFixture.new(4)
	var rover := _rover()
	var s := _state(f, rover, Vector2(5.5, 10.5), 0.0)
	s.vel = Vector2(rover.max_speed, 0)
	_drive(s, Vector2.ZERO, rover, f, 30)
	assert_near(s.vel.length(), rover.max_speed - rover.brake_decel * 0.5, 0.05)


func test_turns_in_place_then_accelerates() -> void:
	# Стоит носом на восток, нужно на запад: сначала разворот на месте, потом разгон.
	var f := TerrainFixture.new(4)
	var rover := _rover()
	var start := Vector2(10.5, 10.5)
	var s := _state(f, rover, start, 0.0)
	_drive(s, Vector2.LEFT, rover, f, 30)          # 0,5 с — разворот ещё идёт
	assert_true(absf(wrapf(PI - s.heading, -PI, PI)) > VehicleKinematics.ALIGN_ANGLE, "still turning")
	assert_near(s.vel.length(), 0.0, 1e-3, "does not move while turning in place")
	assert_true(s.pos.distance_to(start) < 1e-3, "stays in place")
	_drive(s, Vector2.LEFT, rover, f, 90)          # разворот закончен — разгон на запад
	assert_true(s.vel.x < -2.0, "accelerates to the west after the turn: vx=%.2f" % s.vel.x)
	assert_true(absf(s.pos.y - start.y) < 0.2, "no arc: z drift %.2f" % (s.pos.y - start.y))


func test_reverse_input_turns_instead_of_reversing() -> void:
	var f := TerrainFixture.new(4)
	var rover := _rover()
	var s := _state(f, rover, Vector2(10.5, 10.5), 0.0)
	s.vel = Vector2(rover.max_speed, 0)
	VehicleKinematics.step(s, Vector2.LEFT, rover, f.query, DT)
	assert_true(s.vel.x > 0.0, "still moving forward on the first frame of a U-turn")
	_drive(s, Vector2.LEFT, rover, f, 150)
	assert_true(s.vel.x < -(rover.max_speed - 1.0), "after the turn drives the new way, vx=%.2f" % s.vel.x)


func test_launch_arc_lands_by_fall_rules() -> void:
	var f := TerrainFixture.new(6)
	f.set_block(14, 0, 30, 30, 4)     # к востоку от x = 14 — на 2 яруса ниже
	var rover := _rover()
	var s := _state(f, rover, Vector2(12.5, 10.5), 0.0)
	VehicleKinematics.launch(s, Vector2(15.5, 10.5), 1.0, rover, f.query)
	var landed: VehicleKinematics.StepResult = null
	for _i in 180:
		var r := VehicleKinematics.step(s, Vector2.ZERO, rover, f.query, DT)
		if r.landed:
			landed = r
			break
	assert_true(landed != null, "landed")
	assert_eq(s.tile, Vector2i(15, 10), "landed at the target tile")
	assert_eq(landed.fell_tiers, 2)
	assert_eq(landed.fall_damage, 20, "fall damage by height difference")
	assert_false(s.launched)
