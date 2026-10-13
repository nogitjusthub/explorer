extends TestCase
## Заливка ям без выхода (GDD §3.2): большая яма заливается порциями — обход компоненты и подъём её
## тайлов продолжаются с курсора в следующем шаге, бюджет кадра не пробивается.


func test_big_pit_filled_in_slices() -> void:
	var f := TerrainFixture.new(6)
	f.set_block(-20, -20, 19, 19, 2)          # яма 40×40 тайлов, стенки в 4 яруса
	var job := TerrainRepair.PitFillJob.new(f.terrain, -48, -48, 96, 96)
	var steps := 0
	var worst := 0
	while true:
		var before := job.changed
		var done := job.step(0)              # дедлайн уже прошёл: одна порция работы за шаг
		worst = maxi(worst, job.changed - before)
		steps += 1
		if done or steps > 100000:
			break
	assert_eq(job.changed, 1600, "whole pit raised")
	assert_true(worst <= TerrainRepair.PitFillJob.RAISE_BUDGET, "tiles raised in one step: %d" % worst)
	var low := 0
	for tz in range(-20, 20):
		for tx in range(-20, 20):
			for c in 4:
				if f.query.corner(tx, tz, c) != 6:
					low += 1
	assert_eq(low, 0, "pit floor at the exit level")
	assert_eq(TerrainRepair.fill_pits(f.terrain, -48, -48, 96, 96), 0, "nothing left to fill")


func test_two_pits_filled_to_own_levels() -> void:
	# Компоненты не смешиваются: у каждой ямы свой уровень выхода (порциями — тоже).
	var f := TerrainFixture.new(6)
	f.set_block(-10, -10, -1, -1, 2)          # яма среди равнины — выход на ярусе 6
	f.set_block(-32, 20, 31, 21, 5)           # канава до края окна — выезд
	f.set_block(5, 10, 14, 19, 3)             # яма у канавы — выход на ярусе 5
	var job := TerrainRepair.PitFillJob.new(f.terrain, -32, -32, 64, 64)
	while not job.step(0):
		pass
	assert_eq(job.changed, 200, "both pits raised")
	assert_eq(f.query.corner(-5, -5, 0), 6, "first pit up to the plain")
	assert_eq(f.query.corner(10, 15, 0), 5, "second pit up to the ditch")
	assert_eq(TerrainConnectivity.trapped_count(f.query, -32, -32, 64, 64, 0), 0)
