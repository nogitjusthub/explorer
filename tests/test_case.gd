class_name TestCase
extends RefCounted
## Базовый класс юнит-тестов. Каждый метод test_* запускает tests/run_tests.gd.
## Проверки копят ошибки, а не прерывают тест, — тест сообщает обо всех проблемах сразу.

var failures: PackedStringArray = []
var assertions: int = 0
var _expected_errors: PackedStringArray = []


## Тест намеренно вызывает ошибку движка или push_error с этим фрагментом текста — раннер её не засчитает
## в падение (любая другая ошибка во время теста — падение, см. tests/run_tests.gd).
func expect_error(fragment: String) -> void:
	_expected_errors.append(fragment)


func error_expected(error: String) -> bool:
	for fragment in _expected_errors:
		if error.contains(fragment):
			return true
	return false


func assert_true(condition: bool, msg: String = "") -> void:
	assertions += 1
	if not condition:
		fail("expected true" + _suffix(msg))


func assert_false(condition: bool, msg: String = "") -> void:
	assertions += 1
	if condition:
		fail("expected false" + _suffix(msg))


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	assertions += 1
	if not _same_kind(actual, expected) or actual != expected:
		fail("expected %s, got %s%s" % [var_to_str(expected), var_to_str(actual), _suffix(msg)])


func assert_near(actual: float, expected: float, epsilon: float = 1e-4, msg: String = "") -> void:
	assertions += 1
	if not (absf(actual - expected) <= epsilon):     # так NaN не проходит: любое сравнение с ним — false
		fail("expected %f ± %f, got %f%s" % [expected, epsilon, actual, _suffix(msg)])


func fail(msg: String) -> void:
	failures.append(msg)


func _same_kind(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if ta == tb:
		return true
	var numeric := [TYPE_INT, TYPE_FLOAT]
	return ta in numeric and tb in numeric


func _suffix(msg: String) -> String:
	return "" if msg.is_empty() else " — " + msg
