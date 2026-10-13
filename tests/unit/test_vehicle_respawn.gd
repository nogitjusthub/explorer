extends TestCase
## Возрождение машины в песочнице автопилота (Vehicle.respawn): после челнока сверху (crush) или луча
## эвакуации (lift) машина снова цела, видна и управляема.


func _vehicle(f: TerrainFixture) -> Vehicle:
	var v := Vehicle.new(load("res://data/vehicles/rover.tres"), f.query)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.set_physics_process(false)
	v.place(Vector2(5.5, 5.5))
	return v


func test_respawn_after_crush() -> void:
	var f := TerrainFixture.new(4)
	var v := _vehicle(f)
	v.invert_controls(3.0)
	v.out_of_fuel = true
	v.crush()
	v.control_enabled = false
	assert_true(v.wrecked)
	v.respawn(Vector2(10.5, 12.5), 1.0)
	assert_false(v.wrecked, "not wrecked any more")
	assert_true(v.control_enabled)
	assert_true(v.visible)
	assert_false(v.out_of_fuel)
	assert_eq(v.inverted_left, 0.0, "no inverted controls left")
	assert_eq(v._model.root.scale, Vector3.ONE, "the flattened hull is rebuilt")
	assert_eq(v.state.pos, Vector2(10.5, 12.5))
	assert_near(v.state.heading, 1.0, 1e-6)
	v.free()


func test_respawn_after_lift() -> void:
	var f := TerrainFixture.new(4)
	var v := _vehicle(f)
	v.lift(Vector3(5.5, 3.0, 5.5), 0.1)
	for _i in 12:
		v._physics_process(1.0 / 60.0)
	assert_false(v.visible, "taken into the shuttle")
	assert_false(v.control_enabled)
	v.respawn(Vector2(8.5, 8.5))
	assert_true(v.visible)
	assert_true(v.control_enabled)
	assert_eq(v._lift_t, -1.0, "the tractor beam is off")
	assert_near(v._model.root.rotation.y, 0.0, 1e-6, "the spin in the beam is gone")
	v.free()
