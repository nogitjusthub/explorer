extends SceneTree
## Headless-раннер юнит-тестов без аддонов.
## Запуск: godot --headless --path . --script res://tests/run_tests.gd [-- --filter=<подстрока>]
## Код выхода: 0 — все тесты прошли, 1 — есть падения.

const UNIT_DIR := "res://tests/unit/"


func _initialize() -> void:
	# Autoload-синглтоны входят в дерево до первого кадра — тесты запускаем после него.
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var filter := _parse_filter()
	var passed := 0
	var failed := 0

	for path in _test_files():
		var script := load(path) as GDScript
		# При ошибке разбора (в самом тесте или в скрипте, от которого он зависит) load() отдаёт
		# пустой скрипт без методов — без этой проверки его тесты молча пропали бы из счёта.
		if script == null or not script.can_instantiate():
			print("  FAIL  %s — cannot load script (parse error?)" % path.get_file())
			failed += 1
			continue
		for method: Dictionary in script.get_script_method_list():
			var test_name: String = method["name"]
			if not test_name.begins_with("test_"):
				continue
			var full_name := "%s::%s" % [path.get_file().get_basename(), test_name]
			if not filter.is_empty() and not full_name.contains(filter):
				continue
			var test: TestCase = script.new()
			test.call(test_name)
			# Тест без единой проверки, скорее всего, оборвался на ошибке скрипта.
			if test.assertions == 0 and test.failures.is_empty():
				test.fail("no assertions recorded (script error?)")
			if test.failures.is_empty():
				passed += 1
				print("  ok    %s" % full_name)
			else:
				failed += 1
				print("  FAIL  %s" % full_name)
				for failure in test.failures:
					print("        %s" % failure)

	print("%d passed, %d failed" % [passed, failed])
	quit(1 if failed > 0 else 0)


func _test_files() -> PackedStringArray:
	var files := PackedStringArray()
	var dir := DirAccess.open(UNIT_DIR)
	if dir == null:
		push_error("Test runner: cannot open %s" % UNIT_DIR)
		return files
	for file in dir.get_files():
		if file.begins_with("test_") and file.ends_with(".gd"):
			files.append(UNIT_DIR + file)
	files.sort()
	return files


func _parse_filter() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--filter="):
			return arg.trim_prefix("--filter=")
	return ""
