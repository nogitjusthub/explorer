extends TestCase
## Отладочные параметры (DevTools): адрес страницы в release-сборке даёт только диагностику; --event
## пропускает опечатки (с предупреждением), а не молча ничего не делает.


func test_url_params_in_debug_build_take_everything() -> void:
	var p := DevTools.url_params("?seed=7&bench=30&log-slow&event=storm@5", false)
	assert_eq(p, {"seed": "7", "bench": "30", "log-slow": "", "event": "storm@5"})


func test_url_params_in_release_build_take_only_diagnostics() -> void:
	var p := DevTools.url_params("?fuel=999&threat=6&autopilot&idle&event=storm@5&seed=7&spawn=1,2&bench=30" \
			+ "&log-slow&shader-audit", true)
	assert_eq(p, {"log-slow": "", "shader-audit": ""})
	assert_eq(DevTools.url_params("", true), {})
	assert_eq(DevTools.url_params("?", true), {})


func test_parse_events_skips_unknown_kinds_and_bad_items() -> void:
	var events := DevTools.parse_events("storm@5,stromm@3,quake@12.5,hoppers,shark@x,nessie@1")
	assert_eq(events.size(), 3)
	assert_eq(events[0], {"kind": &"storm", "at": 5.0})
	assert_eq(events[1], {"kind": &"quake", "at": 12.5})
	assert_eq(events[2], {"kind": &"nessie", "at": 1.0})
	assert_eq(DevTools.parse_events("").size(), 0)


func test_forced_events_are_separate_lists() -> void:
	var dev := DevTools.new({"event": "storm@5,hoppers@2"})
	var a := dev.forced_events()
	var b := dev.forced_events()
	a.remove_at(0)
	assert_eq(a.size(), 1)
	assert_eq(b.size(), 2, "each director consumes its own copy")
	dev.free()
