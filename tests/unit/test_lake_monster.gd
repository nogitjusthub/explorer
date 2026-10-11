extends TestCase
## Несса (GDD §5.6, LKM-01): геометрия удара, выбор основания на глубокой воде, тайминг броска,
## честность (уйти с полосы — промах), потеря интереса.

const DT := 1.0 / 60.0


## Глубокое озеро: дно на ярусе 1, зеркало на 4 (глубина 3) в прямоугольнике; вокруг — суша на ярусе 4.
func _lake(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int) -> void:
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			f.set_flat(tx, tz, 1)
			f.set_water(tx, tz, 4)


func _monster(f: TerrainFixture, v: Vehicle, at: Vector2) -> LakeMonster:
	var m := LakeMonster.new()
	m.rules = BalanceRules.new()
	m.vehicle = v
	m.query = f.query
	m.terrain = f.terrain
	m.rng = RandomNumberGenerator.new()
	m.rng.seed = 5
	m.setup(at)
	(Engine.get_main_loop() as SceneTree).root.add_child(m)     # частицы живут в мировых координатах
	return m


func _vehicle(f: TerrainFixture, id: String, at: Vector2) -> Vehicle:
	var v := Vehicle.new(load("res://data/vehicles/%s.tres" % id), f.query)
	v.state.pos = at
	v.state.tile = Grid.tile_of_world(at.x, at.y)
	v.state.y = Grid.tier_to_y(f.query.surface_tier_float(at.x, at.y))
	return v


func test_strike_geometry() -> void:
	var r := BalanceRules.new()
	var base := Vector2(10.0, 10.0)
	assert_near(LakeMonster.strike_length(base, Vector2(12.7, 10.0), r.nessie_reach), 2.7, 1e-4)
	assert_near(LakeMonster.strike_length(base, Vector2(30.0, 10.0), r.nessie_reach), r.nessie_reach, 1e-4, "no longer than the neck")
	assert_near(LakeMonster.strike_length(base, Vector2(10.5, 10.0), r.nessie_reach), LakeMonster.REACH_MIN, 1e-4, "needs a swing")
	var dir := Vector2(0.6, 0.8)
	var at := LakeMonster.impact_point(base, dir, 2.5)
	assert_true(at.is_equal_approx(Vector2(11.5, 12.0)), "the head lands at the end of the line")
	var side := Vector2(-dir.y, dir.x)
	assert_true(LakeMonster.in_impact_zone(base, dir, 2.5, at), "under the head")
	assert_true(LakeMonster.in_impact_zone(base, dir, 2.5, at + side * 0.5), "the head is wide")
	assert_true(LakeMonster.in_impact_zone(base, dir, 2.5, at - dir * 0.7), "just short of the end")
	assert_false(LakeMonster.in_impact_zone(base, dir, 2.5, at + side * 1.0), "off the line")
	assert_false(LakeMonster.in_impact_zone(base, dir, 2.5, base + dir * 0.8), "under the neck near the base: only the head hits")
	assert_false(LakeMonster.in_impact_zone(base, dir, 2.5, at + dir * 0.8), "beyond the head")
	assert_false(LakeMonster.in_impact_zone(base, dir, 2.5, base - dir * 2.5), "behind her")


func test_plan_goes_around_the_shore_to_strike_range() -> void:
	var f := TerrainFixture.new(4)
	# Озеро-подкова: два рукава, между ними суша. Несса в левом, машина у верха правого — по суше
	# близко, по воде — кругом.
	_lake(f, 0, 0, 14, 3)
	_lake(f, 0, 0, 3, 14)
	_lake(f, 11, 0, 14, 14)
	var target := Vector2(12.5, 16.9)
	var path := LakeMonster.plan(f.query, Vector2i(1, 13), target, 2.2, 2.85)
	assert_true(path.size() > 20, "detour along the lake: %d tiles" % path.size())
	assert_eq(path[0], Vector2i(1, 13), "starts where she is")
	for i in path.size():
		assert_true(LakeMonster.habitat(f.query, path[i]), "only deep water: %s" % path[i])
		if i > 0:
			var step := path[i] - path[i - 1]
			assert_true(absi(step.x) <= 1 and absi(step.y) <= 1, "neighbours")
	var goal := path[path.size() - 1]
	var d := Vector2(goal.x + 0.5, goal.y + 0.5).distance_to(target)
	assert_true(d >= 2.2 and d <= 2.85, "ends at neck's length from the vehicle: %.2f" % d)


func test_plan_backs_off_and_falls_back() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 0, 0, 20, 20)
	# Машина прямо над Нессой — ей нужен размах: отплывает на длину шеи.
	var over := Vector2(10.6, 10.4)
	var path := LakeMonster.plan(f.query, Vector2i(10, 10), over, 2.2, 2.85)
	var goal := path[path.size() - 1]
	var d := Vector2(goal.x + 0.5, goal.y + 0.5).distance_to(over)
	assert_true(d >= 2.2 and d <= 2.85, "backs off to the neck's length: %.2f" % d)
	# Машина далеко на суше — достать нельзя: путь к ближайшей к ней глубокой воде.
	var far := Vector2(28.5, 10.5)
	path = LakeMonster.plan(f.query, Vector2i(5, 10), far, 2.2, 2.85)
	assert_eq(path[path.size() - 1], Vector2i(20, 10), "waits at the nearest deep water")
	# На суше пути нет.
	assert_eq(LakeMonster.plan(f.query, Vector2i(25, 10), far, 2.2, 2.85).size(), 0)


func test_neck_unfolds_head_first() -> void:
	for j in LakeMonster.DISCS + 1:
		assert_eq(LakeMonster.unfold(j, 0.0), 0.0, "folded at the start")
		assert_near(LakeMonster.unfold(j, LakeMonster.EMERGE_S), 1.0, 1e-4, "all unfolded by the end")
	for t: float in [0.1, 0.3, 0.5, 0.7]:
		for j in LakeMonster.DISCS:
			assert_true(LakeMonster.unfold(j + 1, t) >= LakeMonster.unfold(j, t), "upper goes first (t %.1f, %d)" % [t, j])
	assert_true(LakeMonster.unfold(LakeMonster.DISCS, 0.1) > 0.0 and LakeMonster.unfold(0, 0.1) == 0.0, "the column unfolds disc by disc")
	# Поза — буква S: у основания к машине, в середине назад, к голове снова вперёд.
	assert_true(LakeMonster.pose_angle(0.0) > 0.0)
	assert_true(LakeMonster.pose_angle(0.5) < 0.0)
	assert_true(LakeMonster.pose_angle(1.0) > 0.5)
	assert_true(LakeMonster.POSE_S >= 0.6, "the pose telegraphs the strike at least 0.6 s (LKM rule)")


func test_strike_hits_a_still_hover_and_tosses_it() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 0, 0, 20, 20)
	var v := _vehicle(f, "hover", Vector2(12.7, 10.5))
	var m := _monster(f, v, Vector2(10.5, 10.5))
	var hits: Array = []
	m.damaged.connect(func(amount: int, source: StringName) -> void: hits.append([amount, source, m._time]))
	m.start_hunt()
	var states := {}
	var t := 0.0
	while t < 6.0 and hits.is_empty():
		m.step(DT)
		t += DT
		states[m.state] = true
	assert_eq(hits.size(), 1, "one hit")
	if hits.size() == 1:
		assert_eq(hits[0][0], m.rules.nessie_damage)
		assert_eq(hits[0][1], &"nessie")
		var expected := LakeMonster.EMERGE_S + LakeMonster.POSE_S + LakeMonster.STRIKE_S
		assert_near(hits[0][2], expected, 3.0 * DT, "emerge, pose, strike")
	assert_true(states.has(LakeMonster.State.EMERGE) and states.has(LakeMonster.State.POSE), "telegraphs before striking")
	assert_true(v.state.launched, "the hover is tossed")
	assert_true(v.state.vel.x > 0.0, "along the strike, away from her")
	# Потом погружается и отдыхает.
	while t < 9.0 and m.state != LakeMonster.State.COOLDOWN:
		m.step(DT)
		t += DT
	assert_eq(m.state, LakeMonster.State.COOLDOWN, "submerged")
	assert_false(m.finished)
	m.free()
	v.free()


func test_leaving_the_line_dodges_and_shore_rover_is_rocked() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 0, 0, 20, 20)
	# Ховер уходит с полосы, пока Несса в позе — промах.
	var v := _vehicle(f, "hover", Vector2(12.7, 10.5))
	var m := _monster(f, v, Vector2(10.5, 10.5))
	var hits: Array = []
	m.damaged.connect(func(amount: int, _s: StringName) -> void: hits.append(amount))
	m.start_hunt()
	var moved := false
	for _i in 240:
		m.step(DT)
		if m.state == LakeMonster.State.POSE and not moved:
			moved = true
			v.state.pos += Vector2(0.0, 1.2)
	assert_true(moved, "posed")
	assert_eq(hits.size(), 0, "left the line — missed")
	m.free()
	v.free()
	# Ровер на берегу в досягаемости шеи: урон, раскачка, но не бросок.
	var rover := _vehicle(f, "rover", Vector2(22.2, 10.5))
	var m2 := _monster(f, rover, Vector2(19.5, 10.5))
	var hits2: Array = []
	m2.damaged.connect(func(amount: int, _s: StringName) -> void: hits2.append(amount))
	m2.start_hunt()
	for _i in 180:
		m2.step(DT)
	assert_eq(hits2.size(), 1, "the shore is within reach")
	assert_false(rover.state.launched, "wheels are only rocked")
	m2.free()
	rover.free()


func test_loses_interest_when_out_of_reach() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 0, 0, 20, 20)
	var v := _vehicle(f, "rover", Vector2(28.5, 10.5))
	var m := _monster(f, v, Vector2(19.5, 10.5))
	var hits: Array = []
	m.damaged.connect(func(amount: int, _s: StringName) -> void: hits.append(amount))
	m.start_hunt()
	var t := 0.0
	while t < 12.0 and not m.finished:
		m.step(DT)
		t += DT
	assert_true(m.finished, "gives up")
	assert_true(t > m.rules.fauna_give_up_s, "not before fauna_give_up_s: %.1f" % t)
	assert_true(t < m.rules.fauna_give_up_s + LakeMonster.LEAVE_S + 0.5, "soon after: %.1f" % t)
	assert_eq(hits.size(), 0)
	assert_true(m.pos.x < 20.99, "never leaves deep water")
	m.free()
	v.free()


func test_lurks_until_the_vehicle_is_within_reach() -> void:
	var f := TerrainFixture.new(4)
	_lake(f, 0, 0, 20, 20)
	var v := _vehicle(f, "rover", Vector2(35.5, 10.5))
	var m := _monster(f, v, Vector2(15.5, 10.5))
	for _i in 120:
		m.step(DT)
	assert_false(m.aggressive, "the vehicle is far on land — lurks")
	v.state.pos = Vector2(22.0, 10.5)
	for _i in 90:
		m.step(DT)
	assert_true(m.aggressive, "the vehicle came to the shore — hunts")
	m.free()
	v.free()


func test_steps_into_reach_inside_her_own_tile() -> void:
	# Центр её тайла — на длине шеи от машины, а она сама у края тайла, дальше досягаемости: подплывает к
	# центру и бьёт, а не ждёт, пока потеряет интерес.
	var f := TerrainFixture.new(4)
	_lake(f, 0, 0, 20, 20)
	var v := _vehicle(f, "hover", Vector2(13.3, 10.5))
	var m := _monster(f, v, Vector2(10.05, 10.5))
	var hits: Array = []
	m.damaged.connect(func(amount: int, _s: StringName) -> void: hits.append(amount))
	m.start_hunt()
	for _i in 240:
		m.step(DT)
	assert_eq(hits.size(), 1, "strikes from the tile centre")
	m.free()
	v.free()
