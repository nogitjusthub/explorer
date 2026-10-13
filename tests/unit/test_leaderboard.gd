extends TestCase
## Таблица рекордов (GDD §6): топ-10 по классу; испорченный файл не роняет экран итога, а остаётся
## копией в .bad; запись — через временный файл. Файлы — свои во user:// и удаляются в конце теста.


func _path(tag: String) -> String:
	return "user://test_leaderboard_%s_%d.json" % [tag, Time.get_ticks_usec()]


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _cleanup(path: String) -> void:
	for p in [path, path + Leaderboard.BAD_SUFFIX, path + Leaderboard.TMP_SUFFIX]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)


func _entry(score: int, who: String = "AAA") -> Dictionary:
	return {"name": who, "score": score, "time": 60.0, "shipments": 1, "cause": "evacuated", "date": "2026-10-13"}


func test_add_ranks_and_saves_atomically() -> void:
	var path := _path("add")
	var lb := Leaderboard.new(path)
	assert_eq(lb.add(&"rover", _entry(100)), 0)
	assert_eq(lb.add(&"rover", _entry(300)), 0)
	assert_eq(lb.add(&"rover", _entry(200)), 1)
	assert_eq(lb.add(&"tank", _entry(50)), 0, "tables are per class")
	assert_false(FileAccess.file_exists(path + Leaderboard.TMP_SUFFIX), "the temp file is renamed away")
	var again := Leaderboard.new(path)
	var scores := again.entries(&"rover").map(func(e: Dictionary) -> int: return int(e["score"]))
	assert_eq(scores, [300, 200, 100])
	assert_eq(again.entries(&"tank").size(), 1)
	assert_false(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "a good file needs no backup")
	_cleanup(path)


func test_corrupt_json_keeps_backup_and_empty_table() -> void:
	var path := _path("corrupt")
	var garbage := "{\"rover\": [{\"name\": \"AAA\", \"score\": 12"      # оборванная запись
	_write(path, garbage)
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries(&"rover").size(), 0)
	assert_eq(lb.rank_for(&"rover", 10), 0, "rank_for works on the empty table")
	assert_true(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "the damaged file is kept")
	assert_eq(FileAccess.get_file_as_string(path + Leaderboard.BAD_SUFFIX), garbage)
	lb.add(&"rover", _entry(10))
	assert_eq(FileAccess.get_file_as_string(path + Leaderboard.BAD_SUFFIX), garbage,
			"the backup survives the next save")
	_cleanup(path)


func test_bad_entries_are_dropped_not_crashing() -> void:
	var path := _path("entries")
	_write(path, JSON.stringify({
		"rover": [
			{"name": "OLD", "score": 50, "time": 30.0},
			{"name": "NOS"},                                  # без счёта
			{"name": "STR", "score": "lots"},                 # счёт не число
			"not an entry",
			{"name": 7, "score": 400, "time": "x", "cause": null},
		],
		"tank": "not a list",
	}))
	var lb := Leaderboard.new(path)
	var list := lb.entries(&"rover")
	assert_eq(list.size(), 2, "only entries with a numeric score stay")
	assert_eq(int(list[0]["score"]), 400, "sorted by score")
	assert_eq(list[0]["name"], "???", "a non-string name is replaced")
	assert_eq(list[0]["time"], 0.0)
	assert_eq(list[0]["cause"], "")
	assert_eq(lb.entries(&"tank").size(), 0)
	assert_eq(lb.rank_for(&"rover", 100), 1, "rank_for after the cleanup")
	assert_true(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX), "dropped entries stay in the backup")
	_cleanup(path)


func test_not_an_object_is_backed_up() -> void:
	var path := _path("array")
	_write(path, "[1, 2, 3]")
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries(&"rover").size(), 0)
	assert_true(FileAccess.file_exists(path + Leaderboard.BAD_SUFFIX))
	_cleanup(path)


func test_recovers_from_temp_file_when_main_is_missing() -> void:
	var path := _path("tmp")
	_write(path + Leaderboard.TMP_SUFFIX, JSON.stringify({"hover": [_entry(77)]}))
	var lb := Leaderboard.new(path)
	assert_eq(lb.entries(&"hover").size(), 1, "the finished temp file is read")
	lb.add(&"hover", _entry(80))
	assert_true(FileAccess.file_exists(path))
	assert_false(FileAccess.file_exists(path + Leaderboard.TMP_SUFFIX))
	_cleanup(path)
