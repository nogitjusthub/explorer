extends TestCase
## Временные следы угроз (GroundScars): смерч и молния землю не копают — след кладётся квадом поверх и гаснет;
## рельеф и таблица правок не меняются; следов не больше MAX_SCARS (кольцо).


func test_scars_do_not_touch_the_terrain() -> void:
	var f := TerrainFixture.new(5)
	var scars := GroundScars.new()
	scars.query = f.query
	(Engine.get_main_loop() as SceneTree).root.add_child(scars)
	scars.strip(Vector2(4.5, 10.5), Vector2(6.5, 10.5), Tornado.SCAR_WIDTH)
	scars.spot(Vector2(12.5, 12.5), 0.8)
	assert_eq(scars.count(), 2, "a strip piece and a scorch spot")
	assert_eq(f.query.corner(5, 10, 0), 5, "the ground under the strip is not dug")
	assert_eq(f.query.corner(12, 12, 2), 5, "nor under the scorch")
	assert_eq(f.query.flags(12, 12) & ChunkData.FLAG_ROUGH, 0, "no rubble left either")
	assert_true(f.terrain.diffs.get_record(12, 12).is_empty(), "no terrain edits recorded")
	for i in GroundScars.MAX_SCARS + 10:
		scars.spot(Vector2(4.5 + i % 20, 4.5), 0.5)
	assert_eq(scars.count(), GroundScars.MAX_SCARS, "old scars are recycled in a ring")
	scars.free()
