extends TestCase
## Водоворот (GDD §5.6): 2×2 тайла глубокой воды, тяга по спирали к центру, сильнее для лёгких машин.


func _lake() -> TerrainFixture:
	# Котловина 11×11 тайлов на ярусе 1, вода на ярусе 4 — глубина 3.
	var f := TerrainFixture.new(4)
	f.set_block(0, 0, 10, 10, 1)
	for tz in range(0, 11):
		for tx in range(0, 11):
			f.set_water(tx, tz, 4)
	return f


func test_fits_only_on_deep_water_2x2() -> void:
	var f := _lake()
	assert_true(Whirlpool.fits(f.query, Vector2i(5, 5)), "middle of the lake")
	assert_true(Whirlpool.fits(f.query, Vector2i(1, 1)), "all four tiles around the vertex are deep")
	assert_false(Whirlpool.fits(f.query, Vector2i(0, 5)), "a tile left of the vertex is dry")
	assert_false(Whirlpool.fits(f.query, Vector2i(20, 20)), "dry land")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var at := Whirlpool.find_spot(f.query, Vector2(5.5, 5.5), Vector2.RIGHT, 2.0, 4.0, rng)
	assert_true(at != Vector2.INF and Whirlpool.fits(f.query, Vector2i(at)), "spot found in the lake")


func test_pull_spirals_to_center_and_drags_light_vehicles_more() -> void:
	var r := BalanceRules.new()
	var c := Vector2(5, 5)
	var p := Vector2(7, 5)
	var a := Whirlpool.pull(r, c, p, 0.5, 1.0)
	assert_true(a.dot(c - p) > 0.0, "towards the center")
	assert_true(absf(a.dot(Vector2(0, 1))) > 0.1, "with a swirl")
	assert_true(a.length() > Whirlpool.pull(r, c, p, 2.5, 1.0).length(), "hover is dragged harder than the tank")
	assert_eq(Whirlpool.pull(r, c, c + Vector2(r.whirlpool_pull_r + 0.1, 0), 0.5, 1.0), Vector2.ZERO, "no pull outside")
	assert_eq(Whirlpool.pull(r, c, p, 0.5, 0.0), Vector2.ZERO, "no pull while forming")
