extends TestCase
## Таран фауны машиной (GDD §5.4): порог — своя скорость тарана класса (у ровера и ховера ниже валки
## деревьев), достаёт до носа модели; машина теряет скорость, как после валки; панцирник выдерживает три
## удара, скакун и илозуб — один, стаю скакунов давит один удар; один контакт — один удар; илозуба таран
## достаёт только над поверхностью; убитые мигают, пропадают и не атакуют.

const DT := 1.0 / 60.0


## FaunaDirector для зверя: полей путей нет (звери идут к машине напрямую).
class StubDirector:
	extends Node

	func field(_mode: FlowField.Mode) -> FlowField:
		return null


func _vehicle(f: TerrainFixture, id: String, at: Vector2) -> Vehicle:
	var v := Vehicle.new(load("res://data/vehicles/%s.tres" % id), f.query)
	v.state.pos = at
	v.state.tile = Grid.tile_of_world(at.x, at.y)
	v.state.y = f.query.surface_y(at.x, at.y)
	return v


func _adopt(c: Creature, f: TerrainFixture, v: Vehicle) -> Creature:
	c.rules = BalanceRules.new()
	c.vehicle = v
	c.query = f.query
	c.terrain = f.terrain
	c.noise = NoiseField.new()
	c.director = StubDirector.new()
	c.rng = RandomNumberGenerator.new()
	c.rng.seed = 3
	(Engine.get_main_loop() as SceneTree).root.add_child(c)     # пыль и облачко — в мировых координатах
	return c


func _dispose(c: Creature) -> void:
	c.vehicle.free()
	c.director.free()
	c.free()


## Машина со скоростью speed по направлению dir касается тела b (центр — чуть ближе края касания);
## удары за этот кадр.
func _touch(c: Creature, b: RamBody, speed: float, dir: Vector2 = Vector2.RIGHT) -> int:
	var s := c.vehicle.state
	s.pos = b.pos - dir * (b.reach_dist() - 0.05)
	s.vel = dir * speed
	s.y = b.y
	return c.ram(s.pos, s.y, s.vel, VehicleKinematics.rams(c.vehicle.cls, speed))


## Машина далеко — касания нет.
func _leave(c: Creature) -> void:
	c.ram(Vector2(-100.0, -100.0), 0.0, Vector2.ZERO, false)


func _wait(c: Creature, seconds: float) -> void:
	for _i in ceili(seconds / DT):
		c.step(DT)


func _mire(f: TerrainFixture, x0: int, z0: int, x1: int, z1: int) -> void:
	for tz in range(z0, z1 + 1):
		for tx in range(x0, x1 + 1):
			f.set_flags(tx, tz, ChunkData.FLAG_MIRE)


func test_threshold_is_the_class_ram_speed() -> void:
	for id in ["rover", "tank", "hover"]:
		var cls: VehicleClass = load("res://data/vehicles/%s.tres" % id)
		var at := cls.ram_speed_frac * cls.max_speed
		assert_true(VehicleKinematics.rams(cls, at), "%s rams at %.2f" % [id, at])
		assert_false(VehicleKinematics.rams(cls, at - 0.1), "%s does not ram slower" % id)
		assert_true(cls.ram_speed_frac <= cls.tree_fell_speed_frac, "%s rams no later than it fells trees" % id)
		var s := VehicleState.new()
		s.vel = Vector2(cls.max_speed, 0.0)
		VehicleKinematics.after_felling(s, cls)
		assert_near(s.vel.length(), cls.tree_speed_after_frac * cls.max_speed, 1e-4, "%s slows down as after a tree" % id)
	# Ровер: 60% Vmax — таран, хотя дерево на этой скорости ещё не валится; медленнее — машина проезжает
	# сквозь зверя без удара.
	var f := TerrainFixture.new(4)
	var v := _vehicle(f, "rover", Vector2(5.5, 10.5))
	var sb := _adopt(Shellback.new(), f, v) as Shellback
	sb.setup(Vector2(10.5, 10.5))
	var at := v.cls.ram_speed_frac * v.cls.max_speed
	assert_false(VehicleKinematics.fells(v.cls, at), "a tree would stop the rover at this speed")
	assert_eq(_touch(sb, sb.bodies[0], at - 0.1), 0, "too slow — no hit")
	_leave(sb)
	assert_eq(_touch(sb, sb.bodies[0], at), 1, "the ram speed — a hit")
	_dispose(sb)


## Таран достаёт до носа модели (ram_vehicle_r), а не только до круга колёс (VehicleKinematics.RADIUS).
func test_ram_reaches_the_nose() -> void:
	var f := TerrainFixture.new(4)
	var v := _vehicle(f, "rover", Vector2(5.5, 10.5))
	var pack := _adopt(HopperPack.new(), f, v) as HopperPack
	pack.setup(Vector2(12.5, 10.5), 1)
	var b: RamBody = pack.bodies[0]
	assert_true(pack.rules.ram_vehicle_r > VehicleKinematics.RADIUS, "reaches beyond the wheel circle")
	assert_near(b.reach_dist(), pack.rules.ram_vehicle_r + b.radius, 1e-6)
	var s := v.state
	s.y = b.y
	s.vel = Vector2.RIGHT * v.cls.max_speed
	s.pos = b.pos - Vector2(b.reach_dist() + 0.05, 0.0)
	assert_eq(pack.ram(s.pos, s.y, s.vel, true), 0, "just out of reach — no hit")
	s.pos = b.pos - Vector2(VehicleKinematics.RADIUS + b.radius + 0.05, 0.0)
	assert_eq(pack.ram(s.pos, s.y, s.vel, true), 1, "the nose hits before the wheel circle touches")
	_dispose(pack)


func test_hits_to_kill_per_species() -> void:
	var f := TerrainFixture.new(4)
	var rules := BalanceRules.new()
	assert_eq(rules.ram_hits_shellback, 3)
	assert_eq(rules.ram_hits_hopper, 1)
	assert_eq(rules.ram_hits_shark, 1)

	# Панцирник: удары до последнего — мигает, отлетает по ходу машины, оглушён; последний — гибель.
	var v := _vehicle(f, "rover", Vector2(5.5, 10.5))
	var sb := _adopt(Shellback.new(), f, v) as Shellback
	sb.setup(Vector2(10.5, 10.5))
	var body: RamBody = sb.bodies[0]
	for i in rules.ram_hits_shellback - 1:
		var before := sb.pos
		assert_eq(_touch(sb, body, v.cls.max_speed), 1, "hit %d lands" % (i + 1))
		assert_false(sb.dead, "survives hit %d" % (i + 1))
		assert_true(body.flashing(), "flickers after hit %d" % (i + 1))
		assert_eq(sb.state, Shellback.State.STUN, "stunned")
		_leave(sb)
		_wait(sb, rules.ram_invuln_s + DT)
		assert_near(sb.pos.x - before.x, rules.ram_knockback, 0.1, "knocked back along the ram")
		assert_true(sb.aggressive, "angry after the ram")
	assert_eq(_touch(sb, body, v.cls.max_speed), 1, "last hit lands")
	assert_true(sb.dead, "dies after %d hits" % rules.ram_hits_shellback)
	assert_false(sb.aggressive, "a dead shellback does not chase")
	assert_eq(sb.kills, 1)
	_wait(sb, rules.ram_death_s - 0.1)
	assert_true(body.flashing() and not sb.finished, "flickers before vanishing")
	_wait(sb, 0.1 + RamBody.PUFF_S + 0.1)
	assert_true(sb.finished, "vanished — the director may remove it")
	_dispose(sb)

	# Скакуны: удар по одному — удар по всей стае; каждый гибнет с одного удара — стая гибнет разом.
	var w := _vehicle(f, "rover", Vector2(5.5, 10.5))
	var pack := _adopt(HopperPack.new(), f, w) as HopperPack
	pack.setup(Vector2(12.5, 10.5), 3)
	assert_eq(pack.bodies.size(), 3, "a body per hopper")
	assert_eq(_touch(pack, pack.bodies[2], w.cls.max_speed), 1, "one hit")
	for b in pack.bodies:
		assert_false(b.alive(), "every hopper of the pack dies from it")
	assert_eq(pack.kills, 3, "three killed")
	assert_true(pack.dead, "the whole pack is crushed at once")
	_dispose(pack)

	# Илозуб на суше — один удар.
	var g := TerrainFixture.new(4)
	_mire(g, 4, 4, 9, 16)
	var u := _vehicle(g, "rover", Vector2(14.5, 10.5))
	var shark := _adopt(MireShark.new(), g, u) as MireShark
	shark.setup(Vector2(11.5, 10.5))
	shark.state = MireShark.State.CRAWL
	shark._place()
	assert_eq(_touch(shark, shark.bodies[0], u.cls.max_speed, Vector2.LEFT), 1, "a crawling shark is hit")
	assert_true(shark.dead, "dies from one hit")
	_dispose(shark)


func test_one_contact_one_hit() -> void:
	var f := TerrainFixture.new(4)
	var v := _vehicle(f, "tank", Vector2(5.5, 10.5))
	var sb := _adopt(Shellback.new(), f, v) as Shellback
	sb.setup(Vector2(10.5, 10.5))
	var body: RamBody = sb.bodies[0]
	var speed := v.cls.max_speed
	# Танк давит панцирника и держится вплотную, пока тот отлетает: один удар за всё касание.
	var hits := 0
	for _i in int(1.5 / DT):
		hits += _touch(sb, body, speed)
		sb.step(DT)
	assert_eq(hits, 1, "pushing through one contact is one hit")
	# Отъехала и въехала снова — новый удар; новое касание в неуязвимости не считается (и это касание уже
	# не ударит).
	_leave(sb)
	_wait(sb, sb.rules.ram_invuln_s + DT)
	assert_eq(_touch(sb, body, speed), 1, "a new contact after the invulnerability — a hit")
	_leave(sb)
	assert_eq(_touch(sb, body, speed), 0, "a new contact within the invulnerability — no hit")
	_wait(sb, sb.rules.ram_invuln_s + DT)
	assert_eq(_touch(sb, body, speed), 0, "still the same contact — no hit")
	# Въехала медленно и разогналась, не отъезжая, — не таран.
	_leave(sb)
	_touch(sb, body, 0.5)
	assert_eq(_touch(sb, body, speed), 0, "speeding up while touching is not a ram")
	# Едет прочь от зверя — не таран.
	_leave(sb)
	var s := v.state
	s.pos = body.pos - Vector2.RIGHT * 0.5
	s.vel = Vector2.LEFT * speed
	assert_eq(sb.ram(s.pos, body.y, s.vel, true), 0, "moving away is not a ram")
	assert_eq(body.hits_left, sb.rules.ram_hits_shellback - 2, "two hits so far")
	_dispose(sb)


## Илозуба таран достаёт, только когда он над поверхностью: в засаде в иле — нет, в замахе — да.
func test_shark_is_rammed_only_above_the_surface() -> void:
	var f := TerrainFixture.new(4)
	_mire(f, 4, 4, 16, 16)
	var v := _vehicle(f, "hover", Vector2(14.5, 10.5))
	var s := _adopt(MireShark.new(), f, v) as MireShark
	s.setup(Vector2(8.5, 10.5))
	s.start_hunt()
	assert_eq(s.state, MireShark.State.STALK)
	assert_eq(_touch(s, s.bodies[0], v.cls.max_speed), 0, "lurking in the mire — out of reach")
	_leave(s)
	s.vehicle.state.pos = Vector2(10.5, 10.5)
	s.step(DT)
	assert_eq(s.state, MireShark.State.WINDUP, "surfaces for the leap")
	assert_eq(_touch(s, s.bodies[0], v.cls.max_speed), 1, "surfaced — rammed")
	assert_true(s.dead, "one hit kills")
	# Мёртвый не прыгает и не кусает.
	var bites := [0]
	s.damaged.connect(func(_amount: int, _source: StringName) -> void: bites[0] += 1)
	s.vehicle.state.pos = Vector2(10.5, 10.5)
	_wait(s, 1.0)
	assert_eq(bites[0], 0, "a dead shark does not bite")
	assert_eq(s.state, MireShark.State.WINDUP, "and does not leap")
	_dispose(s)


## Убитая особь замирает; кусает первая живая в строю; мёртвая стая не кусает и уходит.
func test_dead_hoppers_do_not_attack() -> void:
	var f := TerrainFixture.new(4)
	var v := _vehicle(f, "rover", Vector2(10.5, 10.5))
	var pack := _adopt(HopperPack.new(), f, v) as HopperPack
	pack.setup(Vector2(11.5, 10.5), 3)
	var front: RamBody = pack.bodies[0]
	var frozen := (pack._members[0]["node"] as Node3D).position
	front.hit()
	assert_false(front.alive())
	assert_eq(pack._front(), 1, "the next live hopper bites now")
	pack.state = HopperPack.State.CHASE
	pack.aggressive = true
	var bites := [0]
	pack.damaged.connect(func(_amount: int, _source: StringName) -> void: bites[0] += 1)
	_wait(pack, 2.0)
	assert_true(bites[0] > 0, "the survivors keep biting")
	assert_eq((pack._members[0]["node"] as Node3D).position, frozen, "the dead one stays where it fell")
	assert_false((pack._members[0]["node"] as Node3D).visible, "and vanished")
	for b in pack.bodies:
		if b.alive():
			_leave(pack)
			_touch(pack, b, v.cls.max_speed)
	assert_true(pack.dead and not pack.aggressive, "all dead")
	bites[0] = 0
	pack.vehicle.state.pos = pack.pos + Vector2(0.6, 0.0)
	_wait(pack, pack.rules.ram_death_s + RamBody.PUFF_S + 0.1)
	assert_eq(bites[0], 0, "a dead pack does not bite")
	assert_true(pack.finished, "and goes away")
	_dispose(pack)


## Директор: таран давит стаю разом и раз за кадр сбрасывает скорость, как валка дерева; ховер платит HP,
## как за дерево, — за всю стаю один раз; убитые учтены и убраны.
func test_director_ram_slows_the_vehicle_and_removes_the_dead() -> void:
	var f := TerrainFixture.new(4)
	for id in ["rover", "tank", "hover"]:
		var v := _vehicle(f, id, Vector2(5.5, 10.5))
		var d := FaunaDirector.new()
		d.rules = BalanceRules.new()
		d.vehicle = v
		d.query = f.query
		d.terrain = f.terrain
		d.scheduler = JobScheduler.new()
		d.run_seed = 1
		d.begin()
		d._spawn_timer = 1e9                       # своих зверей не подселяет
		var pack := d._spawn_pack(Vector2(9.5, 10.5), 3)
		var dmg: Array = []
		d.damaged.connect(func(amount: int, source: StringName) -> void: dmg.append([amount, source]))
		_ram_into(d, pack.bodies[0])
		var s := v.state
		assert_eq(d.stats["rams"], 1, "%s: one hit" % id)
		assert_eq(d.stats["kills"], 3, "%s: three kills counted" % id)
		assert_true(pack.dead, "%s: the whole pack is crushed at once" % id)
		assert_near(s.vel.length(), v.cls.tree_speed_after_frac * v.cls.max_speed, 1e-4, "%s slows down as after a tree" % id)
		var cost: Array = [[v.cls.tree_fell_damage, &"ram"]] if v.cls.tree_fell_damage > 0 else []
		assert_eq(dmg, cost, "%s pays for the pack as for one tree" % id)
		# Убитая стая мигает, пропадает и уходит из списка.
		s.vel = Vector2.ZERO
		for _i in ceili((d.rules.ram_death_s + RamBody.PUFF_S) / DT) + 2:
			d.step(DT)
		assert_false(d._creatures.has(pack), "%s: the dead pack is removed" % id)
		d.scheduler.free()
		d.free()
		v.free()


## Машина директора d отъезжает (касаний нет), затем на полном ходу въезжает в тело b.
func _ram_into(d: FaunaDirector, b: RamBody) -> void:
	var s := d.vehicle.state
	s.pos = Vector2(-100.0, -100.0)
	s.vel = Vector2.ZERO
	d._ram()
	s.pos = b.pos - Vector2(b.reach_dist() - 0.05, 0.0)
	s.y = b.y
	s.vel = Vector2(d.vehicle.cls.max_speed, 0.0)
	d._ram()
