extends TestCase
## Три класса техники (GDD §4): числа из таблицы, подъём танка, брод, лес, занос и вода ховера.

const DT := 1.0 / 60.0


func _cls(id: StringName) -> VehicleClass:
	return load("res://data/vehicles/%s.tres" % id)


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


func test_table_and_tank_times() -> void:
	# Время на одном баке (GDD §4): полный ход 6,7 / 10 / 5 мин, холостой 33 / 45 / 22 мин.
	var expected := {
		&"rover": [100, 10, 6.67, 33.3], &"tank": [160, 12, 10.0, 45.0], &"hover": [70, 8, 5.0, 22.0]}
	for id: StringName in expected:
		var cls := _cls(id)
		var e: Array = expected[id]
		assert_eq(cls.hp_max, e[0], "%s hp" % id)
		assert_eq(cls.cargo_slots, e[1], "%s cargo" % id)
		var full := cls.fuel_max / (VehicleKinematics.fuel_per_second(cls, 1.0) * 60.0)
		var idle := cls.fuel_max / (VehicleKinematics.fuel_per_second(cls, 0.0) * 60.0)
		assert_near(full, e[2], 0.05, "%s full-throttle minutes" % id)
		assert_near(idle, e[3], 0.5, "%s idle minutes" % id)
	assert_true(Balance.vehicle(&"tank") != null and Balance.vehicle(&"hover") != null, "classes registered")


func test_tank_climbs_without_losing_speed() -> void:
	var f := TerrainFixture.new(4)
	for tz in range(0, 30):
		for tx in range(10, 22):
			var h := 4 + tx - 10
			f.set_tile(tx, tz, h, h + 1, h + 1, h)
	var tank := _cls(&"tank")
	var s := _state(f, tank, Vector2(5.5, 10.5), 0.0)
	var min_on_climb := INF
	for _i in 900:
		VehicleKinematics.step(s, Vector2.RIGHT, tank, f.query, DT)
		if s.pos.x > 15.5 and s.pos.x < 21.0:
			min_on_climb = minf(min_on_climb, s.vel.length())
		if s.pos.x >= 21.0:
			break
	assert_near(min_on_climb, tank.max_speed, 0.01, "tank keeps full speed uphill")


func test_tank_stops_to_turn_on_the_move() -> void:
	var f := TerrainFixture.new(4)
	var tank := _cls(&"tank")
	var s := _state(f, tank, Vector2(5.5, 10.5), 0.0)
	_drive(s, Vector2.RIGHT, tank, f, 180)
	var cruise := s.vel.length()
	# Поворот на 90°: пока угол больше 45°, танк не едет — гасит скорость и доворачивает.
	_drive(s, Vector2.DOWN, tank, f, 20)
	assert_true(s.vel.length() < cruise - 1.0, "slowed while turning: %.2f → %.2f" % [cruise, s.vel.length()])
	_drive(s, Vector2.DOWN, tank, f, 120)
	assert_near(s.forward().angle(), Vector2.DOWN.angle(), 0.01, "turned")
	assert_true(s.vel.length() > 1.0, "drives again after turning")


func test_tank_wades_two_tiers_rover_does_not() -> void:
	var f := TerrainFixture.new(4)
	f.set_block(0, 0, 40, 30, 2)
	for tz in range(0, 30):
		for tx in range(14, 20):
			f.set_water(tx, tz, 4)    # глубина 2 яруса
	var tank := _cls(&"tank")
	var s := _state(f, tank, Vector2(8.5, 10.5), 0.0)
	var max_in_water := 0.0
	for _i in 600:
		VehicleKinematics.step(s, Vector2.RIGHT, tank, f.query, DT)
		if s.pos.x > 16.5 and s.pos.x < 19.5:     # первый тайл воды — торможение до предела
			max_in_water = maxf(max_in_water, s.vel.length())
		if s.pos.x > 22.0:
			break
	assert_false(s.drowning, "tank wades 2 tiers")
	assert_true(s.pos.x > 22.0, "tank crossed, x=%.2f" % s.pos.x)
	assert_true(max_in_water <= tank.max_speed * 0.5 + 1e-3, "half speed in water: %.2f" % max_in_water)
	var rover := _cls(&"rover")
	var r := _state(f, rover, Vector2(8.5, 10.5), 0.0)
	_drive(r, Vector2.RIGHT, rover, f, 300)
	assert_true(r.drowning or r.drowned, "rover drowns at depth 2")


func test_tank_fells_trees_from_low_speed() -> void:
	var f := TerrainFixture.new(4)
	f.set_tree(12, 10)
	var tank := _cls(&"tank")
	# Старт за полтора тайла: танк успевает набрать 25% (1 тайл/с), но не больше.
	var s := _state(f, tank, Vector2(10.6, 10.5), 0.0)
	var felled := false
	for _i in 120:
		var r := VehicleKinematics.step(s, Vector2.RIGHT, tank, f.query, DT)
		if r.felled_tree:
			felled = true
			assert_true(s.vel.length() <= tank.max_speed * tank.tree_speed_after_frac + 1e-3, "speed capped after felling")
			break
	assert_true(felled, "tank fells a tree from low speed")


func test_hover_drifts_in_turns_rover_does_not() -> void:
	var f := TerrainFixture.new(4, 2)
	var hover := _cls(&"hover")
	var rover := _cls(&"rover")
	for cls in [hover, rover]:
		var s := _state(f, cls, Vector2(-40.5, 10.5), 0.0)
		_drive(s, Vector2.RIGHT, cls, f, 120)
		_drive(s, Vector2(0.0, 1.0), cls, f, 12)
		var slip := absf(s.vel.normalized().cross(s.forward()))
		if cls == hover:
			assert_true(slip > 0.3, "hover slides sideways in a turn: %.2f" % slip)
		else:
			assert_near(slip, 0.0, 1e-3, "rover goes where it points")


func test_hover_leaves_lake_onto_shore_at_water_level() -> void:
	# Озеро: дно на 2, вода на 5; берег к востоку на ярусе 5 — для ховера ступеньки нет.
	var f := TerrainFixture.new(4)
	f.set_block(0, 0, 13, 30, 6)       # высокий берег на западе: спуск на воду — обрыв в 1 ярус
	for tz in range(0, 30):
		for tx in range(14, 20):
			f.set_flat(tx, tz, 2)
			f.set_water(tx, tz, 5)
	f.set_block(20, 0, 40, 30, 5)
	var hover := _cls(&"hover")
	var s := _state(f, hover, Vector2(10.5, 10.5), 0.0)
	var landed_damage := -1
	for _i in 300:
		var r := VehicleKinematics.step(s, Vector2.RIGHT, hover, f.query, DT)
		if r.landed:
			landed_damage = r.fall_damage
		if s.pos.x > 24.0:
			break
	assert_eq(landed_damage, 0, "dropped onto the water without damage")
	assert_true(s.pos.x > 24.0, "hover climbed out of the lake onto the shore, x=%.2f" % s.pos.x)
	assert_near(s.y, 5 * Grid.TIER_H, 1e-3)


func test_hover_pays_hp_for_trees() -> void:
	var f := TerrainFixture.new(4)
	f.set_tree(20, 10)
	var hover := _cls(&"hover")
	var s := _state(f, hover, Vector2(5.5, 10.5), 0.0)
	var damage := 0
	for _i in 200:
		damage += VehicleKinematics.step(s, Vector2.RIGHT, hover, f.query, DT).tree_damage
	assert_eq(damage, 10, "hover takes 10 HP for a felled tree")


func test_wall_hit_at_speed_costs_fixed_damage() -> void:
	var f := TerrainFixture.new(4)
	f.set_block(14, 0, 20, 30, 6)      # стенка в 2 яруса к востоку от x = 14
	var rover := _cls(&"rover")
	# С разгона в лоб: урон один раз.
	var fast := _state(f, rover, Vector2(5.5, 10.5), 0.0)
	var total := 0
	for r in _drive(fast, Vector2.RIGHT, rover, f, 180):
		total += r.wall_damage
	assert_eq(total, rover.wall_hit_damage, "head-on hit at full speed")
	# Медленный упор: старт вплотную, до 2/3 скорости не разгоняется.
	var slow := _state(f, rover, Vector2(12.9, 10.5), 0.0)
	total = 0
	for r in _drive(slow, Vector2.RIGHT, rover, f, 120):
		total += r.wall_damage
	assert_eq(total, 0, "slow push into a wall")
	# По касательной (20° к стене, курс 70°) на полной скорости: скорость «в стену» мала — урона нет.
	var course := Vector2.from_angle(deg_to_rad(70.0))
	var glance := _state(f, rover, Vector2(11.0, 2.5), course.angle())
	glance.vel = course * rover.max_speed
	total = 0
	var touched := false
	for r in _drive(glance, course, rover, f, 150):
		total += r.wall_damage
		touched = touched or r.hit_wall
	assert_true(touched, "reached the wall")
	assert_eq(total, 0, "glancing contact")
