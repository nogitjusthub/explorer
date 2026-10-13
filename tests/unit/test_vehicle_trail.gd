extends TestCase
## Колея за машиной (VehicleTrail): отпечатки по пути колёс, ховер следа не оставляет, на скачке колея
## не тянется через весь разрыв.


func _trail(f: TerrainFixture, id: StringName) -> VehicleTrail:
	var t := VehicleTrail.new()
	t.setup(Balance.vehicle(id), f.query)
	return t


## Машина едет по прямой вдоль x от x0 на dist тайлов шагами dt со скоростью speed.
func _drive(t: VehicleTrail, x0: float, dist: float, on_ground: bool = true) -> void:
	var s := VehicleState.new()
	s.heading = 0.0
	s.vel = Vector2(4.0, 0.0)
	var dt := 1.0 / 60.0
	var x := x0
	while x < x0 + dist:
		s.pos = Vector2(x, 10.5)
		s.tile = Grid.tile_of_world(s.pos.x, s.pos.y)
		t.track(s, on_ground, dt)
		x += 4.0 * dt


func test_rover_leaves_two_lines_of_marks() -> void:
	var f := TerrainFixture.new(4)
	var t := _trail(f, &"rover")
	_drive(t, 5.0, 4.0)
	var expected := 2 * int(4.0 / VehicleTrail.STEP)
	assert_true(absi(t.mark_count() - expected) <= 4, "two ruts, a mark every 2 texels: %d ~ %d" % [t.mark_count(), expected])
	t.free()


func test_hover_and_airborne_leave_no_marks() -> void:
	var f := TerrainFixture.new(4)
	var hover := _trail(f, &"hover")
	_drive(hover, 5.0, 3.0)
	assert_eq(hover.mark_count(), 0, "the hover leaves no ruts")
	hover.free()
	var rover := _trail(f, &"rover")
	_drive(rover, 5.0, 3.0, false)
	assert_eq(rover.mark_count(), 0, "no ruts while airborne or drowning")
	rover.free()


func test_jump_does_not_stretch_a_mark() -> void:
	var f := TerrainFixture.new(4)
	var t := _trail(f, &"rover")
	_drive(t, 5.0, 1.0)
	var before := t.mark_count()
	_drive(t, 9.0, 0.05)                 # перенос на 4 тайла — колея начинается заново
	assert_true(t.mark_count() - before <= 2, "no mark across the gap")
	t.free()


func test_material_strength() -> void:
	assert_eq(VehicleTrail.strength(ChunkData.Mat.SAND, 0), 1.0, "sand keeps the deepest ruts")
	assert_true(VehicleTrail.strength(ChunkData.Mat.ROCK, 0) < 0.5, "rock barely")
	assert_eq(VehicleTrail.dust_amount(ChunkData.Mat.GROUND, ChunkData.FLAG_MIRE), 0.0, "no dust in mire")
