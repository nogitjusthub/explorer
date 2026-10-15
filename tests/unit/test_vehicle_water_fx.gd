extends TestCase
## Вода под машиной (VehicleTrail, как у Нессы, но меньше): на ходу вброд — V-волна от носа и брызги, стоит —
## ничего; тонет — пузыри над ней.

const DT := 1.0 / 60.0


func _trail(f: TerrainFixture) -> VehicleTrail:
	var t := VehicleTrail.new()
	t.setup(load("res://data/vehicles/rover.tres"), f.query)
	(Engine.get_main_loop() as SceneTree).root.add_child(t)
	return t


func _lake() -> TerrainFixture:
	var f := TerrainFixture.new(2)
	for tz in range(5, 20):
		for tx in range(5, 20):
			f.set_water(tx, tz, 3)
	return f


func _state(vel: Vector2) -> VehicleState:
	var s := VehicleState.new()
	s.pos = Vector2(10.5, 10.5)
	s.tile = Vector2i(10, 10)
	s.vel = vel
	s.y = 1.2
	return s


func test_wading_makes_a_wake_and_spray() -> void:
	var t := _trail(_lake())
	var s := _state(Vector2(3.0, 0.0))
	for _i in 30:
		t.track(s, true, DT)
	assert_true(t._wake.visible, "a wake while wading")
	assert_true(t._spray.emitting, "and spray")
	assert_true(t._wake.global_position.x > s.pos.x, "from the bow (ahead of the centre)")
	assert_false(t._bubbles.emitting, "no bubbles while afloat")
	s.vel = Vector2.ZERO
	for _i in 60:
		t.track(s, true, DT)
	assert_false(t._wake.visible, "standing — the wake fades")
	assert_false(t._spray.emitting, "no spray")
	t.free()


func test_drowning_bubbles() -> void:
	var t := _trail(_lake())
	var s := _state(Vector2.ZERO)
	s.drowning = true
	t.track(s, false, DT)
	assert_true(t._bubbles.emitting, "bubbles over the sinking vehicle")
	t.free()


func test_dry_ground_no_water_fx() -> void:
	var t := _trail(TerrainFixture.new(2))
	var s := _state(Vector2(3.0, 0.0))
	for _i in 30:
		t.track(s, true, DT)
	assert_false(t._wake.visible, "no wake on land")
	assert_false(t._spray.emitting, "no spray on land")
	t.free()
