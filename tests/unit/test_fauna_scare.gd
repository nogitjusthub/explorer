extends TestCase
## Угрозы пугают малую фауну (FaunaDirector): удар молнии ближе fauna_scare_strike_r, смерч ближе
## fauna_scare_tornado_r, линия разлома ближе fauna_scare_fault_r — стая бросает погоню и отступает домой;
## дальше — продолжает.


func _director(f: TerrainFixture) -> FaunaDirector:
	var v := Vehicle.new(load("res://data/vehicles/rover.tres"), f.query)
	v.state.pos = Vector2(30.5, 30.5)
	v.state.tile = Grid.tile_of_world(30.5, 30.5)
	var d := FaunaDirector.new()
	d.rules = BalanceRules.new()
	d.vehicle = v
	d.query = f.query
	d.terrain = f.terrain
	d.scheduler = JobScheduler.new()
	d.run_seed = 1
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	d.begin()
	d._spawn_timer = 1e9                       # своих зверей не подселяет
	return d


func _chasing(d: FaunaDirector, at: Vector2) -> HopperPack:
	var p := d._spawn_pack(at, 3)
	p.state = HopperPack.State.CHASE
	p.aggressive = true
	return p


func _dispose(d: FaunaDirector) -> void:
	d.vehicle.free()
	d.scheduler.free()
	d.free()


func test_threats_nearby_break_the_chase() -> void:
	var f := TerrainFixture.new(4, 2)
	var d := _director(f)
	var near := _chasing(d, Vector2(20.5, 20.5))
	var far := _chasing(d, Vector2(40.5, 20.5))
	EventBus.lightning_struck.emit(Vector3(22.0, 2.0, 20.5))           # 1,5 тайла от ближней стаи
	assert_eq(near.state, HopperPack.State.RETREAT, "a strike nearby scares the pack")
	assert_false(near.aggressive)
	assert_eq(far.state, HopperPack.State.CHASE, "a far pack keeps chasing")

	var a := _chasing(d, Vector2(20.5, 40.5))
	EventBus.threat_telegraphed.emit(&"tornado", Vector3(24.0, 2.0, 40.5), 0.0, Vector2.RIGHT)
	assert_eq(a.state, HopperPack.State.RETREAT, "a tornado 3.5 tiles away scares it")

	var b := _chasing(d, Vector2(10.5, 10.5))
	EventBus.fault_opened.emit(PackedVector2Array([Vector2(14.0, 0.0), Vector2(14.0, 30.0)]))
	assert_eq(b.state, HopperPack.State.RETREAT, "a fault line 3.5 tiles away scares it")
	assert_eq(far.state, HopperPack.State.CHASE, "the far pack is still not scared")
	_dispose(d)
