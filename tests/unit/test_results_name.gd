extends TestCase
## Имя в таблице рекордов (ResultsScreen): до Leaderboard.NAME_MAX знаков, набор с клавиатуры, пустые
## позиции и обрезка.


func _key(ch: String, keycode: Key = KEY_NONE) -> InputEventKey:
	var k := InputEventKey.new()
	k.pressed = true
	k.keycode = keycode
	k.unicode = ch.unicode_at(0) if not ch.is_empty() else 0
	return k


func _screen(player_name: String) -> ResultsScreen:
	var r := ResultsScreen.new({}, null)
	r._letters = ResultsScreen.letters_of(player_name)
	return r


func test_name_round_trip_and_limits() -> void:
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("kac")), "KAC", "upper case, trailing blanks trimmed")
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("EXPLORER-42")), "EXPLORER", "cut to 8")
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("")), "???", "empty name")
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("A B")), "A B", "inner blank kept")
	assert_eq(ResultsScreen.letters_of("x").size(), Leaderboard.NAME_MAX)
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("ёжик-7")), "ЁЖИК-7", "Cyrillic, upper case")
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("x_y!@#")), "X_Y!@#", "keyboard symbols")
	assert_eq(ResultsScreen.compose_name(ResultsScreen.letters_of("a\"\\b")), "A\"\\B", "quote and backslash")


func test_typing_cyrillic() -> void:
	var r := _screen("")
	for ch in "кот":
		assert_true(r._type_key(_key(ch)), "Cyrillic letters are typed")
	assert_eq(ResultsScreen.compose_name(r._letters), "КОТ")


func test_typing_wasd_backspace() -> void:
	var r := _screen("")
	for ch in "wasd":
		assert_true(r._type_key(_key(ch)), "letters are typed, not used as movement")
	assert_eq(ResultsScreen.compose_name(r._letters), "WASD")
	assert_eq(r._cursor, 4)
	r._type_key(_key("", KEY_BACKSPACE))
	r._type_key(_key("", KEY_BACKSPACE))
	assert_eq(ResultsScreen.compose_name(r._letters), "WA", "backspace erases backwards")
	assert_false(r._type_key(_key("", KEY_UP)), "arrows stay with the arcade selection")
	assert_false(r._type_key(_key("中")), "characters not on a keyboard are ignored")
	for ch in "123456789":
		r._type_key(_key(ch))
	assert_eq(ResultsScreen.compose_name(r._letters), "WA123459", "the last slot is overwritten, never more than 8")
	r.free()


func test_typing_replaces_the_previous_name() -> void:
	var r := _screen("KACPER")
	assert_eq(r._cursor, 0, "entry starts at the first position")
	r._type_key(_key("b"))
	r._type_key(_key("o"))
	assert_eq(ResultsScreen.compose_name(r._letters), "BO", "the previous name is replaced, not overtyped")
	r.free()


func test_leaderboard_cuts_long_names() -> void:
	var path := "user://test_results_name_%d.json" % Time.get_ticks_usec()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rover": [{"name": "TOOLONGNAME", "score": 100}]}))
	f.close()
	var board := Leaderboard.new(path)
	assert_eq(String(board.entries(&"rover")[0]["name"]), "TOOLONGN")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func test_arrow_keys_pick_letters_and_slots() -> void:
	var r := _screen("AB")
	assert_true(r._arcade(_key("", KEY_RIGHT)), "→ moves to the next slot")
	assert_eq(r._cursor, 1)
	assert_true(r._arcade(_key("", KEY_UP)), "↑ changes the letter")
	assert_eq(ResultsScreen.compose_name(r._letters), "AC", "B → C")
	r._arcade(_key("", KEY_DOWN))
	r._arcade(_key("", KEY_DOWN))
	assert_eq(ResultsScreen.compose_name(r._letters), "AA", "↓ goes back")
	r._arcade(_key("", KEY_LEFT))
	assert_eq(r._cursor, 0, "← back to the first slot")
	var echo := _key("", KEY_UP)
	echo.echo = true
	assert_true(r._arcade(echo), "holding the arrow repeats")
	assert_false(r._fresh, "arcade edits keep the name: the next typed letter does not wipe it")
	r._type_key(_key("z"))
	assert_eq(ResultsScreen.compose_name(r._letters), "ZA", "typing after arrows overwrites only the slot")
	r.free()
