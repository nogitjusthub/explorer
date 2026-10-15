extends TestCase
## «Камера: вид сзади» (IsoCameraRig.chase): восемь фиксированных азимутов через 45° — камера не следит за
## курсом плавно (укачивало), а стоит, пока курс не ушёл от её азимута дальше половины шага с запасом, и
## поворачивает на ближайший за CHASE_TURN_TIME.

const DT := 1.0 / 60.0


func _setup() -> Array:
	var f := TerrainFixture.new(4)
	var v := Vehicle.new(load("res://data/vehicles/rover.tres"), f.query)
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(v)
	v.set_physics_process(false)
	v.place(Vector2(5.5, 5.5))
	var rig := IsoCameraRig.new()
	rig.target = v
	root.add_child(rig)
	rig.set_process(false)
	rig.chase = true
	return [v, rig]


## Курс машины, при котором экранное «вверх» смотрит по азимуту w (обратное к want в IsoCameraRig).
func _heading_for(w: float) -> float:
	return atan2(-cos(w), -sin(w))


func _steps(rig: IsoCameraRig, seconds: float) -> void:
	for _i in roundi(seconds / DT):
		rig._process(DT)


func _off(a: float, b: float) -> float:
	return absf(wrapf(a - b, -PI, PI))


func test_snaps_to_eight_fixed_angles() -> void:
	var s := _setup()
	var v: Vehicle = s[0]
	var rig: IsoCameraRig = s[1]
	v.state.heading = _heading_for(deg_to_rad(10.0))
	_steps(rig, 1.0)
	assert_near(_off(rig._yaw, 0.0), 0.0, 1e-4, "10° off a fixed angle — the camera sits on 0°")
	v.state.heading = _heading_for(deg_to_rad(30.0))
	_steps(rig, 1.0)
	assert_near(_off(rig._yaw, 0.0), 0.0, 1e-4, "30° — still within half a step plus the margin: stays")
	v.state.heading = _heading_for(deg_to_rad(35.0))
	_steps(rig, 1.0)
	assert_near(_off(rig._yaw, PI / 4.0), 0.0, 1e-4, "35° — past the margin: turns to 45°")
	v.state.heading = _heading_for(deg_to_rad(15.0))
	_steps(rig, 1.0)
	assert_near(_off(rig._yaw, PI / 4.0), 0.0, 1e-4, "back to 15° — 30° off 45°: no flip-flop at the border")
	v.free()
	rig.free()


func test_turn_is_a_transition_not_a_jump() -> void:
	var s := _setup()
	var v: Vehicle = s[0]
	var rig: IsoCameraRig = s[1]
	v.state.heading = _heading_for(0.0)
	_steps(rig, 1.0)
	v.state.heading = _heading_for(deg_to_rad(50.0))
	var max_step := IsoCameraRig.CHASE_STEP / IsoCameraRig.CHASE_TURN_TIME * DT
	var last := rig._yaw
	for _i in roundi(IsoCameraRig.CHASE_TURN_TIME * 0.5 / DT):
		rig._process(DT)
		assert_true(_off(rig._yaw, last) <= max_step + 1e-5, "turns at a fixed rate")
		last = rig._yaw
	assert_true(_off(rig._yaw, 0.0) > 0.05 and _off(rig._yaw, PI / 4.0) > 0.05, "halfway through the turn")
	_steps(rig, IsoCameraRig.CHASE_TURN_TIME)
	assert_near(_off(rig._yaw, PI / 4.0), 0.0, 1e-4, "settled on the next angle")
	v.free()
	rig.free()
