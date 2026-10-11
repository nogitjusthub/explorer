extends TestCase
## Анимация хода (VehicleRide): сила тряски по скорости, грунту и классу; антенна-хлыст отклоняется
## по инерции; у моделей корпус и антенна — на своих шарнирах.

const DT := 1.0 / 60.0


func _cls(id: StringName) -> VehicleClass:
	return load("res://data/vehicles/%s.tres" % id)


func test_shake_strength() -> void:
	var rover := _cls(&"rover")
	var tank := _cls(&"tank")
	var hover := _cls(&"hover")
	var rough := ChunkData.FLAG_ROUGH
	var idle := VehicleRide.shake_strength(rover, 0.0, 0)
	var smooth := VehicleRide.shake_strength(rover, rover.max_speed * 0.6, 0)
	var bumpy := VehicleRide.shake_strength(rover, rover.max_speed * 0.6, rough)
	assert_true(idle > 0.0 and idle < smooth * 0.5, "на холостом — чуть-чуть")
	assert_true(VehicleRide.shake_strength(rover, rover.max_speed, 0) > smooth, "сильнее на скорости")
	assert_true(bumpy > smooth * 1.5, "на неровном грунте сильнее")
	assert_true(VehicleRide.shake_strength(tank, tank.max_speed * 0.6, rough) < bumpy, "танк трясётся слабее")
	assert_eq(VehicleRide.shake_strength(hover, hover.max_speed, rough), 0.0, "ховер не трясётся")
	assert_eq(VehicleRide.shake_strength(rover, 2.0, ChunkData.FLAG_MIRE), 0.0, "в зыбучем — не тряска")


## Смещение кончика антенны (в координатах корпуса) после frames кадров с ускорением accel
## (x — вперёд, y — вправо; знак скорости антенне не важен — только её изменение).
func _tip_shift(id: StringName, accel: Vector2, frames: int) -> Vector3:
	var cls := _cls(id)
	var m := VehicleModels.build(id)
	var ride := VehicleRide.new()
	var s := VehicleState.new()
	var fwd := s.forward()
	var right := Vector2(-fwd.y, fwd.x)
	for i in frames:
		s.vel = (fwd * accel.x + right * accel.y) * DT * (i + 1)
		ride.update(DT, m, s, cls, 0, true, Vector2.ZERO)
	var shift := m.antenna.transform * m.beacon_pos - (m.antenna.position + m.beacon_pos)
	m.root.free()
	return shift


func test_antenna_whips_by_inertia() -> void:
	# Перед модели — по −Z, правый борт — +X.
	for id: StringName in [&"rover", &"tank", &"hover"]:
		assert_true(_tip_shift(id, Vector2(5.0, 0.0), 8).z > 0.01, "%s: разгон — антенна назад" % id)
		assert_true(_tip_shift(id, Vector2(-5.0, 0.0), 8).z < -0.01, "%s: торможение — вперёд" % id)
		assert_true(_tip_shift(id, Vector2(0.0, 8.0), 8).x < -0.01, "%s: поворот вправо — наружу, влево" % id)


func test_settles_when_inactive() -> void:
	# Ровер трясётся на неровном грунте; разбит — тряска стихает, антенна успокаивается.
	var cls := _cls(&"rover")
	var m := VehicleModels.build(&"rover")
	var ride := VehicleRide.new()
	var s := VehicleState.new()
	var moved := 0.0
	for i in 90:
		s.vel = s.forward() * minf(cls.accel * DT * i, cls.max_speed * cls.rough_speed_mult)
		ride.update(DT, m, s, cls, ChunkData.FLAG_ROUGH, true, Vector2.ZERO)
		moved = maxf(moved, m.body.transform.origin.length())
	assert_true(moved > 0.01, "на ходу корпус трясётся")
	s.vel = Vector2.ZERO
	for i in 180:
		ride.update(DT, m, s, cls, ChunkData.FLAG_ROUGH, false, Vector2.ZERO)
	assert_true(m.body.transform.origin.length() < 0.002, "тряска стихла")
	assert_true(m.antenna.rotation.length() < 0.02, "антенна успокоилась")
	m.root.free()


func test_models_have_sprung_body_and_antenna() -> void:
	for id: StringName in [&"rover", &"tank", &"hover"]:
		var m := VehicleModels.build(id)
		assert_true(m.body != null and m.body.get_parent() == m.root, "%s: корпус — в root" % id)
		assert_true(m.antenna != null and m.antenna.get_parent() == m.body, "%s: антенна — на корпусе" % id)
		assert_true(m.antenna.get_child_count() >= 2, "%s: штырь и огонёк — на шарнире антенны" % id)
		m.root.free()
