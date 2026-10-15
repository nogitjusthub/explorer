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
	r.free()


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


## Каждый знак набора кеглем имени помещается в позицию: с пределом ширины широкий знак (W) выбрасывался
## при отрисовке — набранный, но невидимый.
func test_every_letter_fits_its_slot() -> void:
	for ch in ResultsScreen.LETTERS:
		var w := ResultsScreen.glyph_width(UiKit.FONT, ch)
		assert_true(w <= ResultsScreen.SLOT_W, "%s fits: %.0f px" % [ch, w])
	assert_true(ResultsScreen.glyph_width(UiKit.FONT, "W") > 0.0, "W has a glyph")
	assert_false("player_name" in Settings, "no remembered name: entry always starts empty")


func test_leaderboard_cuts_long_names() -> void:
	var path := "user://test_results_name_%d.json" % Time.get_ticks_usec()
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rover": [{"name": "TOOLONGNAME", "score": 100}]}))
	f.close()
	var board := Leaderboard.new(path)
	assert_eq(String(board.entries()[0]["name"]), "TOOLONGN")
	for p in [path, path + Leaderboard.V1_SUFFIX]:      # файл старого вида — копия .v1 остаётся рядом
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


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
	r._type_key(_key("z"))
	assert_eq(ResultsScreen.compose_name(r._letters), "ZA", "typing after arrows overwrites only the slot")
	r.free()
