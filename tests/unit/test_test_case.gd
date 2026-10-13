extends TestCase
## Сам каркас тестов: assert_near не пропускает NaN; лог ошибок раннера считает ошибки и скрипта, и движка,
## но не предупреждения; ожидаемую ошибку тест может объявить.

const RUNNER := preload("res://tests/run_tests.gd")


func test_assert_near_rejects_nan() -> void:
	var t := TestCase.new()
	t.assert_near(NAN, 0.0)
	t.assert_near(0.0, NAN)
	t.assert_near(1.0, 1.00001)
	assert_eq(t.failures.size(), 2, "NaN never passes, a close value does")


func test_error_log_counts_errors_not_warnings() -> void:
	var error_log: Variant = RUNNER.ErrorLog.new()
	var no_trace: Array[ScriptBacktrace] = []
	error_log._log_error("boom", "res://x.gd", 7, "Invalid access to property", "", false,
			Logger.ERROR_TYPE_SCRIPT, no_trace)
	error_log._log_error("push_warning", "x.cpp", 1, "just a warning", "", false, Logger.ERROR_TYPE_WARNING, no_trace)
	error_log._log_error("push_error", "x.cpp", 2, "an error", "", false, Logger.ERROR_TYPE_ERROR, no_trace)
	var errors: PackedStringArray = error_log.take()
	assert_eq(errors.size(), 2)
	assert_true(errors[0].begins_with("SCRIPT ERROR: Invalid access to property"), errors[0])
	assert_true(errors[1].begins_with("ERROR: an error"), errors[1])
	assert_eq(error_log.take().size(), 0, "take() empties the log")


func test_expected_error_is_matched_by_fragment() -> void:
	var t := TestCase.new()
	t.expect_error("ConfigFile parse error")
	assert_true(t.error_expected("ERROR: ConfigFile parse error at user://x.cfg:1"))
	assert_false(t.error_expected("SCRIPT ERROR: Invalid call"))
