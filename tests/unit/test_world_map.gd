extends TestCase
## Карта мира (GDD §8): память рельефа по чанкам, туман войны (виденное — в радиусе видимости от пути, в тумане
## меньше), находки выгруженных чанков остаются на карте, собранные — нет; оси карты — ромб 4×2 по камере.


func _render_all(m: MapMemory) -> void:
	for _i in 1000:
		if m.pending() == 0:
			return
		m.render_step(100000)


func test_unseen_tiles_are_dim_seen_are_full() -> void:
	var f := TerrainFixture.new()
	var m := MapMemory.new(f.terrain)
	m.chunk_built(Vector2i(0, 0))
	_render_all(m)
	var img := m.image(Vector2i(0, 0))
	assert_true(img != null, "the chunk is drawn")
	assert_near(img.get_pixel(10, 10).a, MapMemory.DIM_A, 0.01, "not seen yet — dim")
	m.mark_seen(Vector2(10.5, 10.5))
	assert_true(m.is_seen(10, 10), "the tile under the vehicle is seen")
	assert_near(img.get_pixel(10, 10).a, 1.0, 0.01, "seen — full colour")
	assert_true(m.is_seen(10 + int(MapMemory.SEEN_R) - 1, 10), "seen within SEEN_R")
	assert_true(not m.is_seen(10 + int(MapMemory.SEEN_R) + 2, 10), "not beyond SEEN_R")
	assert_near(img.get_pixel(30, 30).a, MapMemory.DIM_A, 0.01, "far tiles stay dim")
	assert_true(m.take_dirty().has(Vector2i(0, 0)), "changed images are reported for the texture")
	assert_true(m.take_dirty().is_empty(), "…once")


func test_seen_before_drawn_shows_full_once_drawn() -> void:
	var f := TerrainFixture.new()
	var m := MapMemory.new(f.terrain)
	m.mark_seen(Vector2(5.5, 5.5))               # видели раньше, чем чанк дорисовался
	m.chunk_built(Vector2i(0, 0))
	_render_all(m)
	assert_near(m.image(Vector2i(0, 0)).get_pixel(5, 5).a, 1.0, 0.01, "seen tiles are drawn in full colour")


func test_rendering_is_budgeted_by_rows() -> void:
	var f := TerrainFixture.new()
	var m := MapMemory.new(f.terrain)
	m.chunk_built(Vector2i(0, 0))
	m.chunk_built(Vector2i(0, 0))                # повтор — не второй раз в очередь
	assert_eq(m.pending(), 1, "queued once")
	m.render_step(0)                             # бюджет вышел сразу — одна строка не рисуется
	assert_eq(m.pending(), 1, "nothing done with no budget")


func test_pickups_of_unloaded_chunks_are_remembered() -> void:
	var f := TerrainFixture.new()
	var field := PickupField.new(f.terrain, f.query, 7, BalanceRules.new())
	var coord := Vector2i(0, 0)
	field._by_chunk[coord] = PackedInt64Array()
	field._add(DiffStore.key(3, 4), &"crystal", coord)
	field._add(DiffStore.key(5, 6), &"core", coord)
	field.take(DiffStore.key(5, 6))
	field.on_chunk_removed(coord)
	var known := field.known()
	assert_eq(known.size(), 1, "the uncollected pickup of the unloaded chunk stays on the map")
	assert_eq(known[0]["kind"], &"crystal", "with its kind")
	assert_eq(known[0]["pos"], Vector2(3.5, 4.5), "and its tile")
	field.free()


func test_map_axes_follow_the_camera_quarter() -> void:
	var map := WorldMap.new()
	var ax := map.axes()                         # без камеры — четверть 0, как у камеры по умолчанию
	assert_eq(ax[0], Vector2(2, 1), "world +X goes right-down")
	assert_eq(ax[1], Vector2(-2, 1), "world +Z goes left-down")
	assert_near(absf(ax[0].x * ax[1].y - ax[0].y * ax[1].x), 4.0, 1e-6, "a tile is a 4-pixel 4×2 diamond")
	map.free()


func test_fog_narrows_what_is_seen_and_clearing_widens_it() -> void:
	var f := TerrainFixture.new()
	var m := MapMemory.new(f.terrain)
	m.mark_seen(Vector2(10.5, 10.5), 4.0)        # в тумане — 4 тайла
	assert_true(m.is_seen(13, 10), "within the fog clearing")
	assert_true(not m.is_seen(17, 10), "not beyond it")
	m.mark_seen(Vector2(10.5, 10.5), MapMemory.SEEN_R)   # стоим, туман рассеялся
	assert_true(m.is_seen(17, 10), "seen again once visibility grows, without moving")


func test_clear_weather_gives_full_visibility() -> void:
	var t := ThreatDirector.new()
	assert_near(t.visibility(Vector2(5, 5), 4.0, MapMemory.SEEN_R), MapMemory.SEEN_R, 1e-6, "no fog or dust — the whole frame")
	t.free()
