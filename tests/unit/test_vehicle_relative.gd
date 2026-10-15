extends TestCase
## Управление «относительно машины» (меню настроек, VehicleKinematics.step_relative): W — вперёд, S — назад
## не быстрее REVERSE_FRAC Vmax, против хода — сначала тормоз; A / D — поворот носа на ходу и на месте; у стенки
## задним ходом — скольжение тоже задом.

const DT := 1.0 / 60.0


func _rover() -> VehicleClass:
	return load("res://data/vehicles/rover.tres")


func _state(f: TerrainFixture, cls: VehicleClass, pos: Vector2, heading: float) -> VehicleState:
	var s := VehicleState.new()
	s.pos = pos
	s.heading = heading
	s.tile = Grid.tile_of_world(pos.x, pos.y)
	s.y = VehicleKinematics.ground_y(s, cls, f.query)
	return s


func _run(s: VehicleState, drive: float, turn: float, cls: VehicleClass, f: TerrainFixture, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		VehicleKinematics.step_relative(s, drive, turn, cls, f.query, DT)


func test_forward_and_reverse_speeds() -> void:
	var f := TerrainFixture.new()
	var cls := _rover()
	var s := _state(f, cls, Vector2(10.5, 10.5), 0.0)
	_run(s, 1.0, 0.0, cls, f, 4.0)
	assert_near(s.vel.length(), cls.max_speed, 0.05, "W — full speed forward")
	assert_true(s.vel.dot(s.forward()) > 0.0, "moving forward")
	_run(s, -1.0, 0.0, cls, f, 6.0)
	assert_true(s.vel.dot(s.forward()) < 0.0, "S — now backing up")
	assert_near(s.vel.length(), cls.max_speed * VehicleKinematics.REVERSE_FRAC, 0.05, "reverse is capped")
	assert_near(s.heading, 0.0, 1e-4, "backing up does not turn the vehicle around")


func test_reverse_brakes_through_zero_first() -> void:
	var f := TerrainFixture.new()
	var cls := _rover()
	var s := _state(f, cls, Vector2(10.5, 10.5), 0.0)
	_run(s, 1.0, 0.0, cls, f, 3.0)
	var v0 := s.vel.length()
	VehicleKinematics.step_relative(s, -1.0, 0.0, cls, f.query, DT)
	assert_true(s.vel.dot(s.forward()) > 0.0, "one frame of S at speed — still rolling forward")
	assert_near(v0 - s.vel.length(), cls.brake_decel * DT, 0.01, "…braking at brake_decel")


func test_turns_in_place_and_while_driving() -> void:
	var f := TerrainFixture.new()
	var cls := _rover()
	var s := _state(f, cls, Vector2(10.5, 10.5), 0.0)
	_run(s, 0.0, 1.0, cls, f, 0.2)
	assert_near(s.heading, deg_to_rad(cls.turn_rate_deg) * 0.2, 0.02, "D — nose to the right at the turn rate")
	assert_true(s.pos.distance_to(Vector2(10.5, 10.5)) < 0.01, "in place without W")
	var h := s.heading
	_run(s, 1.0, -1.0, cls, f, 0.2)
	assert_true(s.heading < h, "A — nose to the left while driving")


func test_backing_along_a_wall_slides_backwards() -> void:
	var f := TerrainFixture.new()
	f.set_block(0, 12, 30, 14, 8)                                   # стена южнее
	var cls := _rover()
	var s := _state(f, cls, Vector2(10.5, 11.5), -PI * 0.75)      # нос на северо-запад: корма к стене
	_run(s, -1.0, 0.0, cls, f, 2.0)
	assert_true(s.pos.y < 12.0 - VehicleKinematics.RADIUS + 0.01, "stops at the wall")
	assert_true(s.vel.dot(s.forward()) <= 0.0, "slides along it still in reverse")
