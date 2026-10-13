extends SceneTree
## Headless-раннер юнит-тестов без аддонов.
## Запуск: godot --headless --path . --script res://tests/run_tests.gd [-- --filter=<подстрока>]
## Код выхода: 0 — все тесты прошли, 1 — есть падения.
## Ошибка выполнения GDScript обрывает метод теста, а call() молча возвращает null — по возврату обрыв
## не отличить от конца. Поэтому раннер слушает лог движка (Logger): SCRIPT ERROR или ERROR (push_error,
## ошибки движка) во время теста — падение, даже если до неё проверки успели пройти. Предупреждения
## не в счёт; ожидаемую ошибку тест объявляет сам (TestCase.expect_error).

const UNIT_DIR := "res://tests/unit/"


## Ошибки, пришедшие в лог движка (из любого потока), — до take().
class ErrorLog:
	extends Logger
	const KIND := ["ERROR", "WARNING", "SCRIPT ERROR", "SHADER ERROR"]
	var _mutex := Mutex.new()
	var _errors := PackedStringArray()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := code if rationale.is_empty() else "%s (%s)" % [rationale, code]
		_mutex.lock()
		_errors.append("%s: %s — %s:%d %s" % [KIND[clampi(error_type, 0, KIND.size() - 1)], text,
				file.get_file(), line, function])
		_mutex.unlock()

	## Накопленные ошибки; список очищается.
	func take() -> PackedStringArray:
		_mutex.lock()
		var out := _errors
		_errors = PackedStringArray()
		_mutex.unlock()
		return out


var _log := ErrorLog.new()


func _initialize() -> void:
	OS.add_logger(_log)
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
			_log.take()                      # ошибки до теста (загрузка скриптов) — не его
			test.call(test_name)
			for error in _log.take():
				if not test.error_expected(error):
					test.fail("%s (test aborted or engine error)" % error)
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
	OS.remove_logger(_log)
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
