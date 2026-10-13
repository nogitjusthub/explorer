extends TestCase
## Гибель над водой (Vehicle.sink_on_water): ховер на воде идёт ко дну, как тонущая машина, но без новой
## гибели; машина на суше остаётся на месте.


func _vehicle(f: TerrainFixture, id: String) -> Vehicle:
	var v := Vehicle.new(load("res://data/vehicles/%s.tres" % id), f.query)
	(Engine.get_main_loop() as SceneTree).root.add_child(v)
	v.set_physics_process(false)
	return v


## Озеро: дно на ярусе 2, зеркало на ярусе 4, вокруг — суша яруса 4.
func _lake() -> TerrainFixture:
	var f := TerrainFixture.new(4)
	f.set_block(3, 3, 8, 8, 2)
	for tz in range(3, 9):
		for tx in range(3, 9):
			f.set_water(tx, tz, 4)
	return f


func test_wrecked_hover_sinks_to_the_bottom() -> void:
	var f := _lake()
	var v := _vehicle(f, "hover")
	v.place(Vector2(5.5, 5.5))
	var bottom := f.query.surface_y(5.5, 5.5)
	assert_true(v.state.y > bottom + 0.5, "the hover floats on the water surface")
	v.wreck()
	v.sink_on_water()
	assert_true(v.state.drowning, "goes down like a drowning vehicle")
	for _i in 600:
		var r := VehicleKinematics.step(v.state, Vector2.ZERO, v.cls, f.query, 1.0 / 60.0)
		assert_false(r.drowned, "no second death")
	assert_near(v.state.y, bottom, 1e-3, "rests on the lake bottom")
	v.free()


func test_wreck_on_land_stays_put() -> void:
	var f := _lake()
	var v := _vehicle(f, "rover")
	v.place(Vector2(1.5, 1.5))
	var y := v.state.y
	v.wreck()
	v.sink_on_water()
	assert_false(v.state.drowning, "no water — nothing to sink into")
	assert_near(v.state.y, y, 1e-6)
	v.free()
