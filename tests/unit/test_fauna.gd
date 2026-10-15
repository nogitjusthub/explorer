extends TestCase
## Фауна (GDD §5.4): шум, поле путей по проходимости вида.

const DT := 1.0 / 60.0


## FaunaDirector для одной стаи: готовое поле путей к машине.
class StubDirector:
	extends Node
	var f: FlowField

	func field(_mode: FlowField.Mode) -> FlowField:
		return f


func _field(f: TerrainFixture, mode: FlowField.Mode, target: Vector2i) -> FlowField:
	var result: Array[FlowField] = []
	var job := FlowField.build(f.query, mode, target, func(field: FlowField) -> void: result.append(field))
	var steps := 0
	while not job.step(Time.get_ticks_usec() + 1_000_000):
		steps += 1
		if steps >= 64:              # с бюджетом в секунду поле строится за шаг — зависшая задача не вечна
			fail("FlowField.build: job not done after %d steps" % steps)
			return null
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


## Стая у тихой (стоящей) машины в vehicle_at; поле путей — к машине.
func _pack(f: TerrainFixture, at: Vector2, vehicle_at: Vector2) -> HopperPack:
	var v := Vehicle.new(load("res://data/vehicles/rover.tres"), f.query)
	v.state.pos = vehicle_at
	v.state.tile = Grid.tile_of_world(vehicle_at.x, vehicle_at.y)
	var p := HopperPack.new()
	p.rules = BalanceRules.new()
	p.vehicle = v
	p.query = f.query
	p.terrain = f.terrain
	p.noise = NoiseField.new()
	p.noise.update_vehicle(vehicle_at, 0.0, v.cls.max_speed)      # стоит — не слышно
	var d := StubDirector.new()
	d.f = _field(f, FlowField.Mode.HOPPER, v.state.tile)
	p.director = d
	p.rng = RandomNumberGenerator.new()
	p.rng.seed = 5
	p.setup(at, 3)
	return p


func _dispose(p: HopperPack) -> void:
	p.vehicle.free()
	p.director.free()
	p.free()


func test_hoppers_woken_by_the_shuttle_attack_at_the_pad() -> void:
	# Стая появилась в 25 тайлах от севшего челнока: бег на шум — не погоня, её пределы (20 тайлов, 10 с)
	# не тратятся; у площадки стоит машина — стая её кусает, а не уходит.
	var f := TerrainFixture.new(4, 2)
	var pad := Vector2(30.5, 10.5)
	var p := _pack(f, Vector2(5.5, 10.5), pad + Vector2(1.0, 0.0))
	p.noise.add(pad, p.rules.shuttle_noise_r, p.rules.shuttle_noise_s)
	p.wake(pad)
	var hits := [0]
	p.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	for _i in int(20.0 / DT):
		p.step(DT)
		p.noise.tick(DT)
		if hits[0] > 0:
			break
	assert_true(hits[0] > 0, "ran to the pad and bit the vehicle there")
	assert_eq(p.state, HopperPack.State.CHASE, "hunting, not retreating")
	_dispose(p)


func test_hoppers_at_a_quiet_pad_stay_and_patrol() -> void:
	# Машины у площадки нет: стая ждёт, пока шум слышен, потом остаётся патрулировать там.
	var f := TerrainFixture.new(4, 2)
	var pad := Vector2(20.5, 10.5)
	var p := _pack(f, Vector2(5.5, 10.5), Vector2(-25.5, 40.5))
	p.noise.add(pad, 15.0, 8.0)
	p.wake(pad)
	for _i in int(14.0 / DT):
		p.step(DT)
		p.noise.tick(DT)
	assert_eq(p.state, HopperPack.State.IDLE, "settled after the noise faded")
	assert_false(p.finished, "stays on the map")
	assert_true(p.home.distance_to(pad) < 2.0, "patrols around the pad: %s" % p.home)
	_dispose(p)


## Плато на ярус выше (x ≥ 11) — стенка в ярус вдоль x = 11; ramp — съезд с плато на запад у z = 14.
func _cliff(ramp: bool) -> TerrainFixture:
	var f := TerrainFixture.new(4, 2)
	f.set_block(11, -20, 40, 40, 5)
	if ramp:
		f.set_tile(11, 14, 4, 5, 5, 4)
	return f


## Стая гонится за стоящей машиной; возвращает [укусы, время до конца погони или limit].
func _chase_bites(p: HopperPack, limit: float) -> Array:
	var hits := [0]
	p.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	var t := 0.0
	while t < limit and p.state != HopperPack.State.RETREAT:
		p.step(DT)
		t += DT
	return [hits[0], t]


func test_hoppers_level_check() -> void:
	var f := _cliff(false)
	assert_false(Creature.same_level(f.query, Vector2(11.4, 10.5), Vector2(10.5, 10.5)), "a one-tier cliff between")
	assert_true(Creature.same_level(f.query, Vector2(12.4, 10.5), Vector2(11.5, 10.5)), "on the plateau")
	assert_true(Creature.same_level(f.query, Vector2(9.4, 10.5), Vector2(10.5, 10.5)), "below it")
	var r := _cliff(true)
	assert_true(Creature.same_level(r.query, Vector2(10.5, 14.5), Vector2(11.9, 14.5)), "up the ramp — one level")
	# Мель: машина в воде у берега вровень с ней — на уровне зеркала; под уступом берега — нет.
	r.set_flat(5, 10, 3)
	r.set_water(5, 10, 4)
	assert_true(Creature.same_level(r.query, Vector2(6.3, 10.5), Vector2(5.5, 10.5)), "rover in shallows at a flush shore")
	r.set_block(6, 9, 6, 11, 5)
	assert_false(Creature.same_level(r.query, Vector2(6.3, 10.5), Vector2(5.5, 10.5)), "shallows under a bank")


func test_hoppers_do_not_bite_across_a_cliff() -> void:
	# Машина стоит вплотную под скалой в ярус, стая — наверху, на соседнем тайле (ближе REACH): укусов нет.
	# Обхода нет — стая ждёт у края, не дёргаясь, и через fauna_give_up_s уходит.
	var f := _cliff(false)
	var p := _pack(f, Vector2(11.4, 10.5), Vector2(10.6, 10.5))
	var start := p.pos
	var r := _chase_bites(p, 20.0)
	assert_eq(r[0], 0, "no bites from the cliff top")
	assert_eq(p.state, HopperPack.State.RETREAT, "loses interest")
	assert_true(r[1] < p.rules.fauna_give_up_s + 2.0, "after fauna_give_up_s: %.1f s" % r[1])
	assert_true(p.pos.x >= 11.0, "never fell off the cliff: %s" % p.pos)
	assert_true(p.pos.distance_to(start) < 1.0, "waits at the edge: %s" % p.pos)
	_dispose(p)


func test_hoppers_go_around_a_cliff_and_bite_on_the_same_level() -> void:
	# Есть съезд: стая сверху обегает уступ по полю путей и кусает уже снизу.
	var f := _cliff(true)
	var p := _pack(f, Vector2(11.4, 10.5), Vector2(10.6, 10.5))
	var hits := []
	p.damaged.connect(func(_amount: int, _source: StringName) -> void: hits.append(p.pos))
	var t := 0.0
	while t < 10.0 and hits.is_empty():
		p.step(DT)
		t += DT
	assert_false(hits.is_empty(), "came down the ramp and bit")
	if not hits.is_empty():
		assert_true((hits[0] as Vector2).x < 11.0, "bit from below the cliff: %s" % hits[0])
	_dispose(p)


func test_hoppers_bite_on_the_same_tier() -> void:
	var f := TerrainFixture.new(4, 2)
	var p := _pack(f, Vector2(11.4, 10.5), Vector2(10.6, 10.5))
	var r := _chase_bites(p, 3.0)
	assert_true(r[0] > 0, "bites a vehicle next to it")
	_dispose(p)


func test_shellback_does_not_ram_across_a_cliff() -> void:
	# Рывок по краю плато мимо машины под скалой (ближе CONTACT по плоскости) — тарана нет.
	var f := _cliff(false)
	var v := Vehicle.new(load("res://data/vehicles/rover.tres"), f.query)
	v.state.pos = Vector2(10.6, 10.5)
	v.state.tile = Vector2i(10, 10)
	var s := Shellback.new()
	s.rules = BalanceRules.new()
	s.vehicle = v
	s.query = f.query
	s.terrain = f.terrain
	s.noise = NoiseField.new()
	s.rng = RandomNumberGenerator.new()
	s.setup(Vector2(11.3, 8.0))
	s.state = Shellback.State.CHARGE
	s.aggressive = true
	s._charge_dir = Vector2(0.0, 1.0)
	s._charge_left = s.rules.shellback_charge_dist
	var hits := [0]
	s.damaged.connect(func(_amount: int, _source: StringName) -> void: hits[0] += 1)
	for _i in 30:
		s.step(DT)
	assert_true(s.pos.y > 10.5, "charged past the vehicle: %s" % s.pos)
	assert_eq(hits[0], 0, "no ram from the cliff top")
	v.free()
	s.free()


## Сдвиг дальше соседнего тайла (толчок танка — 1,6 тайла) — шагами меньше тайла: первое непроходимое
## ребро останавливает его; через воду или с обрыва не перескочить.
func test_long_move_on_grid_stops_at_the_first_blocked_edge() -> void:
	var f := TerrainFixture.new(4)
	var from := Vector2(12.6, 10.5)
	var to := Vector2(14.2, 10.5)                    # шаг по тайлам (2, 0)
	assert_eq(Creature.move_on_grid(f.query, FlowField.Mode.HOPPER, from, to), to, "open ground — all the way")
	var diag := Vector2(14.2, 12.3)                  # (2, 2)
	assert_eq(Creature.move_on_grid(f.query, FlowField.Mode.HOPPER, from, diag), diag, "long diagonal over open ground")
	f.set_flat(13, 10, 3)
	f.set_water(13, 10, 4)                           # вода в соседнем тайле
	assert_eq(Creature.move_on_grid(f.query, FlowField.Mode.HOPPER, from, to), from, "water next door — stays")
	var g := TerrainFixture.new(4)
	g.set_block(14, 0, 30, 20, 2)                    # обрыв в два яруса за соседним тайлом
	var stop := Creature.move_on_grid(g.query, FlowField.Mode.HOPPER, from, to)
	assert_eq(Grid.tile_of_world(stop.x, stop.y), Vector2i(13, 10), "stops at the edge: %s" % stop)


## Танк расшвыривает стаю у воды и у обрыва: стая остаётся у края — не в воде и не внизу.
func test_tank_bump_does_not_throw_the_pack_into_water_or_off_a_ledge() -> void:
	for water: bool in [true, false]:
		var f := TerrainFixture.new(4)
		if water:
			for tz in range(5, 16):
				for tx in range(13, 16):
					f.set_flat(tx, tz, 3)
					f.set_water(tx, tz, 4)
		else:
			f.set_block(13, 0, 30, 30, 2)
		var p := _pack(f, Vector2(12.6, 10.5), Vector2(12.0, 10.5))
		p.vehicle.cls = load("res://data/vehicles/tank.tres")
		p.vehicle.state.vel = Vector2(3.0, 0.0)
		p._tank_bump(p.vehicle.state.pos)
		assert_true(p._stun > 0.0, "the pack was bumped (water: %s)" % water)
		assert_true(p.pos.x < 13.0, "stays at the edge, not thrown over it (water: %s): %s" % [water, p.pos])
		_dispose(p)
	# На ровном месте толчок — на всю длину.
	var o := TerrainFixture.new(4)
	var q := _pack(o, Vector2(12.6, 10.5), Vector2(12.0, 10.5))
	q.vehicle.cls = load("res://data/vehicles/tank.tres")
	q.vehicle.state.vel = Vector2(3.0, 0.0)
	q._tank_bump(q.vehicle.state.pos)
	assert_near(q.pos.x, 12.6 + HopperPack.BUMP_LEN, 0.01, "thrown BUMP_LEN on open ground")
	_dispose(q)


## Меши и материал особи — общие у всех стай (строятся раз); мигание тарана — наложение на узлах одной
## особи, другие стаи не мигают.
func test_hopper_kit_is_shared_between_packs() -> void:
	var f := TerrainFixture.new(4)
	var a := _pack(f, Vector2(5.5, 5.5), Vector2(20.5, 20.5))
	var b := _pack(f, Vector2(9.5, 5.5), Vector2(20.5, 20.5))
	var ma: Dictionary = a._members[0]
	var mb: Dictionary = b._members[0]
	var body_a := ma["body"] as MeshInstance3D
	var body_b := mb["body"] as MeshInstance3D
	assert_true(body_a.mesh == body_b.mesh, "the torso mesh is shared between packs")
	assert_true(body_a.mesh.surface_get_material(0) == body_b.mesh.surface_get_material(0), "and its material")
	(a.bodies[0] as RamBody).hit()
	assert_true(body_a.material_overlay != null, "the rammed hopper flashes")
	assert_true(body_b.material_overlay == null, "a hopper of another pack does not")
	assert_true((a._members[1]["body"] as MeshInstance3D).material_overlay == null, "nor its pack mates")
	_dispose(a)
	_dispose(b)


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


## Отступившая стая (сдалась или испугалась) на глазах не пропадает: отбегает, возвращается к месту появления и
## патрулирует там; пока не успокоилась (CALM_S), на машину рядом не кидается снова.
func test_retreating_pack_goes_home_not_away() -> void:
	var f := TerrainFixture.new(4, 2)
	var home := Vector2(10.5, 10.5)
	var p := _pack(f, home, Vector2(14.5, 10.5))
	for _i in int(1.5 / DT):                               # заметила машину рядом — погоня
		p.step(DT)
	assert_true(p.aggressive, "chasing the vehicle")
	p.flee()
	for _i in int(9.0 / DT):
		p.step(DT)
		assert_false(p.finished, "never vanishes")
		assert_false(p.aggressive, "does not attack again while calming down")
	assert_eq(p.state, HopperPack.State.IDLE, "back to patrolling")
	assert_true(p.pos.distance_to(home) <= p.rules.hopper_patrol_r + 1.0, "around its home: %s" % p.pos)
	_dispose(p)
