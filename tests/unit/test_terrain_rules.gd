extends TestCase
## Правила тайла: высота в углах, непрерывность, выбор диагонали.


func test_height_matches_corners() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for _i in 200:
		var base := rng.randi_range(-3, 10)
		var c := [base + rng.randi_range(0, 1), base + rng.randi_range(0, 1), base + rng.randi_range(0, 1), base + rng.randi_range(0, 1)]
		assert_near(TerrainRules.height_in_tile(c[0], c[1], c[2], c[3], 0.0, 0.0), c[0])
		assert_near(TerrainRules.height_in_tile(c[0], c[1], c[2], c[3], 1.0, 0.0), c[1])
		assert_near(TerrainRules.height_in_tile(c[0], c[1], c[2], c[3], 1.0, 1.0), c[2])
		assert_near(TerrainRules.height_in_tile(c[0], c[1], c[2], c[3], 0.0, 1.0), c[3])


func test_height_continuous_across_diagonal() -> void:
	# Две стороны диагонали дают одну высоту на ней самой.
	for c in [[0, 1, 1, 1], [1, 0, 0, 0], [0, 1, 0, 1], [0, 0, 1, 1], [1, 1, 0, 1]]:
		var diag02 := TerrainRules.diagonal_02(c[0], c[1], c[2], c[3])
		for k in 11:
			var t := k / 10.0
			var u := t
			var v := t if diag02 else 1.0 - t
			var a := TerrainRules.height_in_tile(c[0], c[1], c[2], c[3], u + 1e-4, v)
			var b := TerrainRules.height_in_tile(c[0], c[1], c[2], c[3], u - 1e-4, v)
			assert_near(a, b, 1e-2, "corners %s at t=%.1f" % [str(c), t])


func test_single_raised_corner_folds_along_other_diagonal() -> void:
	# Поднят один угол NW: сгиб должен идти по NE–SW, чтобы приподнялся только треугольник у NW.
	assert_false(TerrainRules.diagonal_02(1, 0, 0, 0))
	assert_near(TerrainRules.height_in_tile(1, 0, 0, 0, 0.9, 0.9), 0.0)
