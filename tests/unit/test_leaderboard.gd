extends TestCase
## Таблица рекордов (GDD §6): общий топ-10 для всех машин (машина — в записи); файл старого вида (таблицы по
## классам) сливается в общую, копия — в .v1; испорченный файл не роняет экран итога, а остаётся копией
## в .bad; запись — через временный файл. Файлы — свои во user:// и удаляются в конце теста.


func _path(tag: String) -> String:
	return "user://test_leaderboard_%s_%d.json" % [tag, Time.get_ticks_usec()]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup(path: String) -> void:
	for p in [path, path + Leaderboard.BAD_SUFFIX, path + Leaderboard.TMP_SUFFIX, path + Leaderboard.V1_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _entry(score: int, vehicle: String = "rover", who: String = "AAA") -> Dictionary:
	return {"name": who, "score": score, "time": 60.0, "shipments": 1, "cause": "evacuated", "date": "2026-10-13",
			"vehicle": vehicle}


func _scores(lb: Leaderboard) -> Array:
	return lb.entries().map(func(e: Dictionary) -> int: return int(e["score"]))


func test_one_table_for_all_vehicles() -> void:
	var path := _path("add")
	var lb := Leaderboard.new(path)
	assert_eq(lb.add(_entry(100)), 0)
	assert_eq(lb.add(_entry(300, "hover")), 0)
	assert_eq(lb.add(_entry(200, "tank")), 1)
	assert_eq(lb.add(_entry(50, "tank")), 3, "one table: the tank's 50 goes after everyone")
	assert_false(FileAccess.file_exists(path + Leaderboard.TMP_SUFFIX), "the temp file is renamed away")
	var again := Leaderboard.new(path)
	assert_eq(_scores(again), [300, 200, 100, 50])
	assert_eq(String(again.entries()[0]["vehicle"]), "hover", "the record keeps its vehicle")
	assert_false(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "a good file needs no backup")
	assert_false(FileAccess.file_exists(path + Leaderboard.V1_SUFFIX), "a new-style file needs no v1 copy")
	_cleanup(path)


func test_old_per_class_tables_are_merged() -> void:
	var path := _path("legacy")
	var hover: Array = []
	for i in 9:
		hover.append({"name": "H%d" % i, "score": 10 + i})
	var old := JSON.stringify({"rover": [{"name": "ROV", "score": 500}, {"name": "ROW", "score": 30}],
			"tank": [{"name": "TNK", "score": 700}], "hover": hover})
	_write(path, old)
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries().size(), Leaderboard.SIZE, "12 old records — the best 10 stay")
	assert_eq(_scores(lb).slice(0, 3), [700, 500, 30], "sorted across the old tables")
	assert_eq(String(lb.entries()[0]["vehicle"]), "tank", "the vehicle comes from the old table key")
	assert_eq(FileAccess.get_file_as_string(path + Leaderboard.V1_SUFFIX), old, "the old file is kept as .v1")
	assert_false(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "trimming good records is not damage")
	lb.add(_entry(1000))
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert_true(saved is Dictionary and (saved as Dictionary).keys() == [Leaderboard.KEY], "saved in the new form")
	_cleanup(path)


func test_corrupt_json_keeps_backup_and_empty_table() -> void:
	var path := _path("corrupt")
	var garbage := "{\"entries\": [{\"name\": \"AAA\", \"score\": 12"      # оборванная запись
	_write(path, garbage)
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries().size(), 0)
	assert_eq(lb.rank_for(10), 0, "rank_for works on the empty table")
	assert_true(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "the damaged file is kept")
	assert_eq(FileAccess.get_file_as_string(path + Leaderboard.BAD_SUFFIX), garbage)
	lb.add(_entry(10))
	assert_eq(FileAccess.get_file_as_string(path + Leaderboard.BAD_SUFFIX), garbage,
			"the backup survives the next save")
	_cleanup(path)


func test_bad_entries_are_dropped_not_crashing() -> void:
	var path := _path("entries")
	_write(path, JSON.stringify({
		"entries": [
			{"name": "OLD", "score": 50, "time": 30.0, "vehicle": "tank"},
			{"name": "NOS"},                                  # без счёта
			{"name": "STR", "score": "lots"},                 # счёт не число
			"not an entry",
			{"name": 7, "score": 400, "time": "x", "cause": null, "vehicle": 3},
		],
		"tank": "not a list",
	}))
	var lb := Leaderboard.new(path)
	var list := lb.entries()
	assert_eq(list.size(), 2, "only entries with a numeric score stay")
	assert_eq(int(list[0]["score"]), 400, "sorted by score")
	assert_eq(list[0]["name"], "???", "a non-string name is replaced")
	assert_eq(list[0]["time"], 0.0)
	assert_eq(list[0]["cause"], "")
	assert_eq(list[0]["vehicle"], "", "a non-string vehicle is dropped")
	assert_eq(list[1]["vehicle"], "tank")
	assert_eq(lb.rank_for(100), 1, "rank_for after the cleanup")
	assert_true(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "dropped entries stay in the backup")
	_cleanup(path)


func test_not_an_object_is_backed_up() -> void:
	var path := _path("array")
	_write(path, "[1, 2, 3]")
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries().size(), 0)
	assert_true(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX))
	_cleanup(path)


func test_recovers_from_temp_file_when_main_is_missing() -> void:
	var path := _path("tmp")
	_write(path + Leaderboard.TMP_SUFFIX, JSON.stringify({Leaderboard.KEY: [_entry(77, "hover")]}))
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries().size(), 1, "the finished temp file is read")
	lb.add(_entry(80))
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + Leaderboard.TMP_SUFFIX))
	_cleanup(path)
