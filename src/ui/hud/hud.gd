class_name Hud
extends CanvasLayer
## HUD (GDD §8): слева вверху — HP, топливо, трюм; по центру вверху — счёт; под ним — всплывающие
## сообщения о находках и уроне; справа вверху — радар и пейджер; внизу по центру — таймер основного
## челнока, над ним — аварийный вызов и при пустом баке «НЕТ ТОПЛИВА»; по центру экрана — крупные объявления.
## Логики нет: значения приходят сигналами EventBus, объявления — вызовом banner().

const FUEL_WARN := 0.2                 ## доля бака, ниже которой полоса топлива мигает
const BAR_W := 60
const PANEL := Rect2(3, 3, 93, 33)
const COLOR_PANEL := Color(0.06, 0.04, 0.09, 0.62)
const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.62, 0.58, 0.66)
const COLOR_SHADOW := Color(0, 0, 0, 0.85)
const COLOR_HP := Color(0.46, 0.9, 0.4)
const COLOR_HP_LOW := Color(0.95, 0.32, 0.25)
const COLOR_FUEL := Color(1.0, 0.72, 0.2)
const COLOR_FUEL_LOW := Color(1.0, 0.22, 0.12)
const COLOR_SLOT := Color(0.3, 0.95, 0.9)
const COLOR_SLOT_EMPTY := Color(0.3, 0.3, 0.36)
const COLOR_DAMAGE := Color(1.0, 0.3, 0.25)
const POPUP_S := 1.6
const COLOR_PAD := Color(0.45, 1.0, 0.95)
const COLOR_WARN := Color(1.0, 0.6, 0.25)

var _hp := 0
var _hp_max := 1
var _fuel := 0.0
var _fuel_max := 1.0
var _slots := 0
var _slots_max := 1
var _score := 0
var _score_shown := 0.0
var _time := 0.0
var _damage_flash := 0.0
var _popups: Array[Dictionary] = []    ## {text, color, t}
var _banner := ""
var _banner_color := COLOR_TEXT
var _banner_t := 0.0
var _shuttle_state := &""
var _shuttle_left := 0.0
var _em_state := &"idle"
var _em_left := 0.0
var _flash := 0.0
var _canvas: Control
var _font: Font
var radar: Radar
var pager: Pager


func _ready() -> void:
	layer = 5
	_font = ThemeDB.fallback_font
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_hud)
	add_child(_canvas)
	radar = Radar.new()
	radar.range_tiles = Balance.rules.radar_range
	radar.anchor_left = 1.0
	radar.anchor_right = 1.0
	radar.offset_left = -2.0 * Radar.R - 5.0
	radar.offset_right = -5.0
	radar.offset_top = 4.0
	radar.offset_bottom = 4.0 + 2.0 * Radar.R
	_canvas.add_child(radar)
	pager = Pager.new()
	pager.anchor_left = 1.0
	pager.anchor_right = 1.0
	pager.offset_left = -2.0 * Radar.R - 5.0          # ровно под радаром, той же ширины
	pager.offset_right = -5.0
	pager.offset_top = 8.0 + 2.0 * Radar.R
	pager.offset_bottom = 8.0 + 2.0 * Radar.R + 34.0
	_canvas.add_child(pager)
	EventBus.screen_flash_requested.connect(func(strength: float) -> void: _flash = maxf(_flash, strength))
	EventBus.shuttle_state_changed.connect(_on_shuttle_state)
	EventBus.emergency_state_changed.connect(_on_emergency_state)
	EventBus.hp_changed.connect(_on_hp_changed)
	EventBus.fuel_changed.connect(_on_fuel_changed)
	EventBus.cargo_changed.connect(_on_cargo_changed)
	EventBus.score_changed.connect(_on_score_changed)
	EventBus.pickup_collected.connect(_on_pickup_collected)
	EventBus.vehicle_damaged.connect(_on_damaged)


## Крупное объявление по центру экрана.
func banner(text: String, color: Color = COLOR_TEXT, seconds: float = 2.5) -> void:
	_banner = text
	_banner_color = color
	_banner_t = seconds


## Короткое сообщение под счётом.
func popup(text: String, color: Color = COLOR_TEXT) -> void:
	_popups.append({"text": text, "color": color, "t": POPUP_S})
	if _popups.size() > 4:
		_popups.pop_front()


func _on_shuttle_state(state: StringName, seconds: float, _pad: Vector3) -> void:
	_shuttle_state = state
	_shuttle_left = seconds


func _on_emergency_state(state: StringName, seconds: float, _penalty: int) -> void:
	_em_state = state
	_em_left = seconds


func _on_hp_changed(cur: int, mx: int) -> void:
	_hp = cur
	_hp_max = mx


func _on_fuel_changed(cur: float, mx: float) -> void:
	_fuel = cur
	_fuel_max = mx


func _on_score_changed(total: int) -> void:
	_score = total


func _on_cargo_changed(used: int, mx: int, _value: int) -> void:
	_slots = used
	_slots_max = mx


func _on_pickup_collected(kind: StringName, value: int) -> void:
	var pk := Balance.pickup(kind)
	if pk == null:
		return
	if pk.cargo:
		popup("+%d  %s" % [value, pk.display_name], pk.color.lightened(0.3))
	elif pk.hp_restore > 0:
		popup("+%d HP  %s" % [value, pk.display_name], COLOR_HP)
	else:
		popup("+%d%% топлива  %s" % [value, pk.display_name], COLOR_FUEL)


func _on_damaged(amount: int, _source: StringName, _at: Vector3) -> void:
	_damage_flash = 0.35
	popup("−%d HP" % amount, COLOR_DAMAGE)


func _process(dt: float) -> void:
	_time += dt
	_damage_flash = maxf(_damage_flash - dt, 0.0)
	_flash = maxf(_flash - dt * 5.0, 0.0)
	_banner_t = maxf(_banner_t - dt, 0.0)
	for p in _popups:
		p["t"] -= dt
	_popups = _popups.filter(func(p: Dictionary) -> bool: return p["t"] > 0.0)
	# Счёт докручивается к новому значению, а не прыгает.
	_score_shown = move_toward(_score_shown, _score, maxf(absf(_score - _score_shown) * 4.0, 60.0) * dt)
	_canvas.queue_redraw()


func _draw_hud() -> void:
	var size := _canvas.size
	if _flash > 0.0:
		_canvas.draw_rect(Rect2(Vector2.ZERO, size), Color(0.9, 0.95, 1.0, _flash * 0.45))
	if _damage_flash > 0.0:
		var a := _damage_flash / 0.35 * 0.5
		var c := Color(COLOR_DAMAGE, a)
		_canvas.draw_rect(Rect2(0, 0, size.x, 2), c)
		_canvas.draw_rect(Rect2(0, size.y - 2, size.x, 2), c)
		_canvas.draw_rect(Rect2(0, 0, 2, size.y), c)
		_canvas.draw_rect(Rect2(size.x - 2, 0, 2, size.y), c)

	_canvas.draw_rect(PANEL, COLOR_PANEL)
	var hp_frac := float(_hp) / maxf(_hp_max, 1)
	_text(Vector2(6, 11), "HP", 8, COLOR_DIM)
	_bar(Vector2(32, 6), hp_frac, COLOR_HP if hp_frac > 0.3 else COLOR_HP_LOW, true)
	var fuel_frac := _fuel / maxf(_fuel_max, 0.001)
	var low := fuel_frac <= FUEL_WARN
	var blink_on := not low or fmod(_time, 0.5) < 0.3
	_text(Vector2(6, 21), "ТОП", 8, COLOR_FUEL_LOW if low and blink_on else COLOR_DIM)
	_bar(Vector2(32, 16), fuel_frac, COLOR_FUEL_LOW if low else COLOR_FUEL, blink_on)
	_text(Vector2(6, 31), "ГРУЗ", 8, COLOR_DIM)
	var slot_w := mini(5, (BAR_W + 1) / maxi(_slots_max, 1) - 1)
	for i in _slots_max:
		var r := Rect2(32 + i * (slot_w + 1), 26, slot_w, 5)
		_canvas.draw_rect(r, COLOR_SLOT if i < _slots else COLOR_SLOT_EMPTY)

	_text(Vector2(0, 17), "%06d" % roundi(_score_shown), 16, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var y := 30.0
	for p in _popups:
		var c: Color = p["color"]
		c.a = clampf(p["t"] / 0.4, 0.0, 1.0)
		_text(Vector2(0, y), p["text"], 8, c, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		y += 10.0

	_draw_bottom(size)

	if _banner_t > 0.0:
		var c := _banner_color
		c.a = clampf(_banner_t / 0.5, 0.0, 1.0)
		_text(Vector2(0, size.y * 0.5 - 30), _banner, 16, c, HORIZONTAL_ALIGNMENT_CENTER, size.x)


## Низ-центр: внизу — таймер основного челнока; над ним — аварийный челнок (летит, ищет место) и при
## пустом баке мигающие две строки: «НЕТ ТОПЛИВА» и вызов аварийного [F] (или что с воды вызвать нельзя).
func _draw_bottom(size: Vector2) -> void:
	var y := size.y - 8.0
	var blink := fmod(_time, 0.6) < 0.4
	match _shuttle_state:
		&"waiting":
			_text(Vector2(0, y), "ЧЕЛНОК  %s" % _clock(_shuttle_left), 8, COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
		&"announced":
			_text(Vector2(0, y), "ЧЕЛНОК  %s  — площадка на радаре" % _clock(_shuttle_left), 8, COLOR_PAD,
					HORIZONTAL_ALIGNMENT_CENTER, size.x)
		&"landed":
			var col := COLOR_PAD if _shuttle_left > 5.0 or blink else COLOR_FUEL_LOW
			_text(Vector2(0, y), "ЧЕЛНОК НА ПЛОЩАДКЕ  %s  — остановитесь в круге" % _clock(_shuttle_left), 8, col,
					HORIZONTAL_ALIGNMENT_CENTER, size.x)
	y -= 12.0
	var call_line := ""
	var call_color := COLOR_WARN
	match _em_state:
		&"inbound":
			call_line = "АВАРИЙНЫЙ ЧЕЛНОК  %s" % _clock(_em_left)
		&"no_place":
			call_line = "АВАРИЙНЫЙ ЧЕЛНОК — ищет, где сесть"
		&"water":
			call_line = "Вызов челнока на воде не возможен" if _fuel <= 0.0 else ""
		&"idle":
			call_line = "Вызов аварийного челнока [F]" if _fuel <= 0.0 else ""
	if _fuel <= 0.0:
		# Пустой бак: обе строки мигают.
		var a := 1.0 if blink else 0.35
		call_color = Color(COLOR_TEXT, a)
		if not call_line.is_empty():
			_text(Vector2(0, y), call_line, 8, call_color, HORIZONTAL_ALIGNMENT_CENTER, size.x)
			y -= 8.0
		_text(Vector2(0, y - 4.0), "НЕТ ТОПЛИВА", 16, Color(COLOR_FUEL_LOW, a), HORIZONTAL_ALIGNMENT_CENTER, size.x)
	elif not call_line.is_empty():
		_text(Vector2(0, y), call_line, 8, call_color, HORIZONTAL_ALIGNMENT_CENTER, size.x)


static func _clock(seconds: float) -> String:
	var s := ceili(maxf(seconds, 0.0))
	return "%d:%02d" % [s / 60, s % 60]


func _bar(pos: Vector2, frac: float, color: Color, filled: bool) -> void:
	_canvas.draw_rect(Rect2(pos, Vector2(BAR_W, 5)), COLOR_SLOT_EMPTY)
	if filled:
		_canvas.draw_rect(Rect2(pos, Vector2(roundf(BAR_W * clampf(frac, 0.0, 1.0)), 5)), color)


func _text(pos: Vector2, s: String, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	_canvas.draw_string(_font, pos + Vector2.ONE, s, align, width, font_size, Color(COLOR_SHADOW, color.a * 0.85))
	_canvas.draw_string(_font, pos, s, align, width, font_size, color)
