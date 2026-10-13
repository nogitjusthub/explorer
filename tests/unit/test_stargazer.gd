extends TestCase
## Троеглазка (GDD §5.6): ареал — мелкая вода, глаза по дистанции, разряд только по машине в воде
## или над ней, перезарядка.


## Пруд: дно на ярусе 4, зеркало на ярусе 5 (глубина — ярус) в квадрате 8…14, вокруг суша.
func _pond() -> TerrainFixture:
	var f := TerrainFixture.new(4)
	for tz in range(8, 15):
		for tx in range(8, 15):
			f.set_water(tx, tz, 5)
	return f


func _root() -> Window:
	return (Engine.get_main_loop() as SceneTree).root


func _vehicle(f: TerrainFixture, id: String, at: Vector2) -> Vehicle:
	var v := Vehicle.new(load("res://data/vehicles/%s.tres" % id), f.query)
	_root().add_child(v)
	v.set_physics_process(false)
	v.place(at)
	return v


func _ray(f: TerrainFixture, r: BalanceRules, v: Vehicle, at: Vector2) -> Stargazer:
	var ray := Stargazer.new()
	ray.rules = r
	ray.vehicle = v
	ray.query = f.query
	ray.terrain = f.terrain
	ray.rng = RandomNumberGenerator.new()
	ray.rng.seed = 5
	_root().add_child(ray)
	ray.setup(at)
	return ray


## Шаги по 1/60 с, пока не пройдёт seconds или не наберётся hits_max ударов; прошедшее время.
func _run(ray: Stargazer, seconds: float, hits: Array, hits_max: int = 1000) -> float:
	var t := 0.0
	while t < seconds and hits.size() < hits_max:
		ray.step(1.0 / 60.0)
		t += 1.0 / 60.0
	return t


func test_habitat_is_shallow_water() -> void:
	var f := _pond()
	f.set_flat(12, 12, 2)            # яма — глубина 3 яруса
	f.set_flat(9, 9, 5)              # отмель вровень с зеркалом
	assert_true(Stargazer.habitat(f.query, Vector2i(10, 10)), "a tier of water")
	assert_false(Stargazer.habitat(f.query, Vector2i(5, 5)), "dry land")
	assert_false(Stargazer.habitat(f.query, Vector2i(12, 12)), "deep water")
	assert_false(Stargazer.habitat(f.query, Vector2i(9, 9)), "no depth over the shoal")


func test_eyes_open_one_by_one() -> void:
	assert_eq(Stargazer.eyes_for(3.0), 0)
	assert_eq(Stargazer.eyes_for(2.4), 1, "first eye at 2.5 tiles")
	assert_eq(Stargazer.eyes_for(1.6), 2, "second at 1.7")
	assert_eq(Stargazer.eyes_for(0.3), 2, "the third opens only in the discharge")


func test_reach_only_in_or_over_water() -> void:
	var f := _pond()
	var at := Vector2(10.5, 10.5)
	var s := VehicleState.new()
	s.pos = Vector2(11.3, 10.5)
	s.y = f.query.surface_y(s.pos.x, s.pos.y)
	assert_true(Stargazer.in_reach(f.query, at, s, 1.0), "wading within a tile")
	s.y = Grid.tier_to_y(5)
	assert_true(Stargazer.in_reach(f.query, at, s, 1.0), "hover over the water")
	s.y = Grid.tier_to_y(5) + 2.0
	assert_false(Stargazer.in_reach(f.query, at, s, 1.0), "high above the water (lifted)")
	s.y = f.query.surface_y(s.pos.x, s.pos.y)
	s.pos = Vector2(11.6, 10.5)
	assert_false(Stargazer.in_reach(f.query, at, s, 1.0), "farther than a tile")
	# На берегу рядом — не достаёт.
	s.pos = Vector2(7.7, 10.5)
	s.y = f.query.surface_y(s.pos.x, s.pos.y)
	assert_false(Stargazer.in_reach(f.query, Vector2(8.5, 10.5), s, 1.0), "dry land")
	s.pos = Vector2(11.3, 10.5)
	for flag: String in ["falling", "launched", "drowning"]:
		s.set(flag, true)
		assert_false(Stargazer.in_reach(f.query, at, s, 1.0), flag)
		s.set(flag, false)


func test_cooldown_in_range() -> void:
	var r := BalanceRules.new()
	var g := RandomNumberGenerator.new()
	var seen := {}
	for i in 40:
		g.seed = i
		var c := Stargazer.cooldown(r, g)
		assert_true(c >= r.ray_cooldown_min_s and c <= r.ray_cooldown_max_s, "%.2f s" % c)
		seen[snappedf(c, 0.5)] = true
	assert_true(seen.size() > 3, "cooldowns vary")


func test_shock_then_recharge() -> void:
	var f := _pond()
	var r := BalanceRules.new()
	var v := _vehicle(f, "rover", Vector2(11.2, 10.5))
	var ray := _ray(f, r, v, Vector2(10.5, 10.5))
	var hits: Array = []
	ray.damaged.connect(func(amount: int, source: StringName) -> void: hits.append([amount, source]))
	ray.step(1.0 / 60.0)
	assert_eq(hits.size(), 1, "instant shock")
	if hits.size() == 1:
		assert_eq(hits[0][0], r.ray_damage)
		assert_eq(hits[0][1], &"ray")
	assert_near(v.inverted_left, r.shock_invert_s, 1e-3, "controls inverted")
	assert_eq(ray.open_eyes(), 3, "the third eye is open")
	var t := _run(ray, r.ray_cooldown_min_s - 0.1, hits, 2)
	assert_eq(hits.size(), 1, "no shock while recharging")
	assert_eq(ray.open_eyes(), 0, "eyes closed while recharging")
	t += _run(ray, r.ray_cooldown_max_s - t + 0.1, hits, 2)
	assert_eq(hits.size(), 2, "shocks again once recharged")
	assert_true(t >= r.ray_cooldown_min_s - 0.05, "not before the cooldown: %.2f s" % t)
	ray.free()
	v.free()


func test_hover_over_water_is_shocked() -> void:
	var f := _pond()
	var r := BalanceRules.new()
	var v := _vehicle(f, "hover", Vector2(10.5, 11.3))
	var ray := _ray(f, r, v, Vector2(10.5, 10.5))
	var hits: Array = []
	ray.damaged.connect(func(amount: int, _source: StringName) -> void: hits.append(amount))
	_run(ray, 0.2, hits)
	assert_eq(hits.size(), 1, "hover above the water")
	ray.free()
	v.free()


## Рельеф под троеглазкой изменился (землетрясение, воронка) — тело ложится на новое дно не позже PLACE_S:
## и когда машина рядом, и когда далеко.
func test_body_follows_the_bottom_after_a_quake() -> void:
	for near: bool in [true, false]:
		var f := _pond()
		var r := BalanceRules.new()
		var v := _vehicle(f, "rover", Vector2(7.7, 10.5) if near else Vector2(1.0, 10.5))
		var ray := _ray(f, r, v, Vector2(10.5, 10.5))
		var hits: Array = []
		_run(ray, 0.5, hits)
		var before := ray._root.position.y
		f.set_flat(10, 10, 3)                              # дно ушло на ярус вниз
		_run(ray, Stargazer.PLACE_S + 0.1, hits)
		assert_near(ray._root.position.y, before - Grid.TIER_H, 0.02, "lies on the new bottom (near: %s)" % near)
		ray.free()
		v.free()


func test_no_shock_on_shore_eyes_watch() -> void:
	var f := _pond()
	var r := BalanceRules.new()
	var v := _vehicle(f, "rover", Vector2(7.7, 10.5))
	var ray := _ray(f, r, v, Vector2(8.5, 10.5))
	var hits: Array = []
	ray.damaged.connect(func(amount: int, _source: StringName) -> void: hits.append(amount))
	_run(ray, 12.0, hits)
	assert_eq(hits.size(), 0, "on the shore within a tile — no shock")
	assert_eq(ray.open_eyes(), 2, "two eyes watch the vehicle")
	v.place(Vector2(6.5, 10.5))
	_run(ray, 1.0, hits)
	assert_eq(ray.open_eyes(), 1, "farther — one eye")
	v.place(Vector2(1.0, 10.5))
	_run(ray, 1.0, hits)
	assert_eq(ray.open_eyes(), 0, "out of range — eyes closed")
	# Разбитую машину в воде не бьёт.
	v.place(Vector2(9.2, 10.5))
	v.wreck()
	_run(ray, 1.0, hits)
	assert_eq(hits.size(), 0, "wrecked vehicle")
	ray.free()
	v.free()
