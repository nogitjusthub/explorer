extends TestCase
## Круг опоры машины (VehicleKinematics.RADIUS): бок и угол корпуса не заходят на высокие соседние тайлы,
## коридор шириной в тайл проходим; наклон модели не «лезет» на стенку, к которой машина прижалась.

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


func test_side_does_not_sink_into_a_wall() -> void:
	var f := TerrainFixture.new()
	f.set_block(0, 12, 30, 12, 8)                                   # стена южнее
	var cls := _rover()
	var s := _state(f, cls, Vector2(10.5, 11.85), 0.0)            # бок уже в стене: 0,15 до ребра
	VehicleKinematics.step(s, Vector2.RIGHT, cls, f.query, DT)
	assert_true(s.pos.y <= 12.0 - VehicleKinematics.RADIUS + 1e-4, "pushed out to RADIUS: %.3f" % s.pos.y)
	for _i in 60:
		VehicleKinematics.step(s, Vector2.RIGHT, cls, f.query, DT)
	assert_true(s.pos.x > 12.0, "keeps driving along the wall")
	assert_true(s.pos.y <= 12.0 - VehicleKinematics.RADIUS + 1e-4, "…without touching it")


func test_corner_of_a_pillar_pushes_out() -> void:
	var f := TerrainFixture.new()
	f.set_flat(11, 11, 8)                                           # столб по диагонали на юго-восток
	var cls := _rover()
	var s := _state(f, cls, Vector2(10.9, 10.9), 0.0)
	VehicleKinematics.step(s, Vector2.ZERO, cls, f.query, DT)
	assert_near(s.pos.distance_to(Vector2(11, 11)), VehicleKinematics.RADIUS, 1e-3, "away from the pillar corner")


func test_one_tile_corridor_is_passable() -> void:
	var f := TerrainFixture.new()
	f.set_block(0, 9, 30, 9, 8)
	f.set_block(0, 11, 30, 11, 8)                                   # коридор z = 10
	var cls := _rover()
	var s := _state(f, cls, Vector2(5.5, 10.5), 0.0)
	for _i in 120:
		VehicleKinematics.step(s, Vector2.RIGHT, cls, f.query, DT)
	assert_true(s.pos.x > 10.0, "drives through: x %.2f" % s.pos.x)
	assert_near(s.pos.y, 10.5, 1e-3, "stays in the middle")


func test_tilt_does_not_climb_a_wall() -> void:
	var f := TerrainFixture.new()
	f.set_block(12, 0, 20, 30, 8)                                   # стена восточнее
	var v := Vehicle.new(_rover(), f.query)
	v.state.pos = Vector2(12.0 - VehicleKinematics.RADIUS, 10.5)   # нос упёрся
	v.state.heading = 0.0
	var b := v._ground_basis()
	var pitch := absf(asin(clampf(-b.z.y, -1.0, 1.0)))
	assert_true(pitch < 0.01, "level nose against the wall: %.3f rad" % pitch)
	v.free()


## «Песочные часы» (как на отладочном снимке seed 26836): скат A (10, 10) поднят только в СВ-углу до 5, скат
## B (11, 9) опущен только в ЮЗ-углу до 5, боковые тайлы — 4, выше B — плато 6. Касаются одной вершиной (11, 10).
func _hourglass(b_sw: int) -> TerrainFixture:
	var f := TerrainFixture.new()
	f.set_block(12, 0, 30, 9, 6)
	f.set_block(11, 0, 11, 8, 6)
	f.set_tile(10, 10, 4, 5, 4, 4)
	f.set_tile(11, 9, 6, 6, 6, b_sw)
	return f


## Едет по диагонали input с места pos; true — ни разу не упала. Итог — в s.
func _drive_through(f: TerrainFixture, s: VehicleState, input: Vector2, seconds: float, cls: VehicleClass = _rover()) -> bool:
	for _i in roundi(seconds / DT):
		VehicleKinematics.step(s, input, cls, f.query, DT)
		if s.falling:
			return false
	return true


func test_hourglass_climbs_through_the_vertex() -> void:
	for cls: VehicleClass in [_rover(), load("res://data/vehicles/hover.tres") as VehicleClass]:
		var f := _hourglass(5)
		var ne := Vector2(1, -1).normalized()
		var s := _state(f, cls, Vector2(10.45, 10.65), ne.angle())   # чуть мимо вершины: пересечёт у неё
		assert_true(_drive_through(f, s, ne, 1.5, cls), "%s: no slide into the low side tile" % cls.id)
		assert_true(s.pos.x > 11.0 and s.pos.y < 10.0, "%s: on the upper ramp or beyond: %s" % [cls.id, s.pos])
		assert_true(s.y > 5.0 * Grid.TIER_H - 1e-3, "%s: climbed, not dropped to tier 4: y %.2f" % [cls.id, s.y])


func test_hourglass_descends_through_the_vertex() -> void:
	var f := _hourglass(5)
	var sw := Vector2(-1, 1).normalized()
	var s := _state(f, _rover(), Vector2(11.6, 9.4), sw.angle())
	assert_true(_drive_through(f, s, sw, 1.5), "no fall into the side tile on the way down")
	assert_true(s.pos.x < 11.0 and s.pos.y > 10.0, "came down onto the lower ramp: %s" % s.pos)


func test_no_bridge_when_the_corners_differ() -> void:
	var f := _hourglass(6)                                         # B не опущен: в вершине 5 против 6
	var ne := Vector2(1, -1).normalized()
	var s := _state(f, _rover(), Vector2(10.45, 10.65), ne.angle())
	assert_false(_drive_through(f, s, ne, 1.5), "no common vertex height — falls into the side tile as before")
