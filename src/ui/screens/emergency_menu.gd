class_name EmergencyMenu
extends CanvasLayer
## Вызов аварийного челнока (GDD §2.3): F открывает окно поверх игры, без паузы. «Вызвать челнок?»,
## «что привезти?» и ползунок «топливо [A] <<—|—>> [D] запчасти» — всего supply единиц, шаг step,
## под концами — сколько чего; ниже — цена вызова. F / Enter или кнопка — вызвать, Esc — отмена.
## Тап по ползунку ставит деление, по подписи — шаг к ней. Пока окно открыто, машина без управления
## (A / D двигают ползунок).

signal confirmed(fuel: int, parts: int)
signal closed

const PANEL := Rect2(120, 160, 240, 108)
const TRACK_W := 80.0
const SLIDER_Y := 202.0                ## середина ползунка по высоте
const INPUT_DELAY_S := 0.15

var supply := 30
var step := 5
var fuel := 15                         ## единиц топлива; остальное до supply — запчасти
var penalty := 0                       ## штраф за этот вызов, очков

var _age := 0.0
var _canvas: Control


func _ready() -> void:
	layer = 12
	name = "EmergencyMenu"
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.draw.connect(_draw_menu)
	add_child(_canvas)
	var mid := PANEL.get_center().x
	_button("ВЫЗВАТЬ", "F", _confirm, Vector2(mid - 4, PANEL.end.y - 12), true)
	_button("ОТМЕНА", "Esc", closed.emit, Vector2(mid + 4, PANEL.end.y - 12), false)


func parts() -> int:
	return supply - fuel


func _button(text: String, hotkey: String, action: Callable, at: Vector2, from_right: bool) -> void:
	var b := UiKit.button(text, hotkey)
	b.pressed.connect(func() -> void:
		if _age >= INPUT_DELAY_S:
			action.call())
	add_child(b)
	b.reset_size()
	b.position = Vector2(at.x - b.size.x if from_right else at.x, at.y - b.size.y * 0.5)


func _track() -> Rect2:
	return Rect2(PANEL.get_center().x - TRACK_W * 0.5, SLIDER_Y - 2.0, TRACK_W, 5.0)


func _process(dt: float) -> void:
	_age += dt
	# Ползунок — опросом: стик шлёт поток событий, а нужен один шаг на нажатие.
	if _age >= INPUT_DELAY_S and not HelpScreen.shown(get_tree()):
		if Input.is_action_just_pressed(&"move_left") or Input.is_action_just_pressed(&"ui_left"):
			fuel = mini(fuel + step, supply)
		elif Input.is_action_just_pressed(&"move_right") or Input.is_action_just_pressed(&"ui_right"):
			fuel = maxi(fuel - step, 0)
	_canvas.queue_redraw()


func _input(event: InputEvent) -> void:
	if _age < INPUT_DELAY_S or HelpScreen.shown(get_tree()):
		return
	if UiKit.is_click(event):
		var p := (event as InputEventMouseButton).position
		var tr := _track()
		if absf(p.y - SLIDER_Y) <= 8.0 and p.x >= PANEL.position.x and p.x <= PANEL.end.x:
			if p.x < tr.position.x:
				fuel = mini(fuel + step, supply)
			elif p.x > tr.end.x:
				fuel = maxi(fuel - step, 0)
			else:
				var k := (p.x - tr.position.x) / tr.size.x
				fuel = clampi(roundi((1.0 - k) * supply / step) * step, 0, supply)
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"radio") or event.is_action_pressed(&"ui_accept"):
		_confirm()
	elif event.is_action_pressed(&"pause") or event.is_action_pressed(&"ui_cancel"):
		closed.emit()
	else:
		return
	get_viewport().set_input_as_handled()


func _confirm() -> void:
	confirmed.emit(fuel, parts())


func _draw_menu() -> void:
	_canvas.draw_rect(PANEL, UiKit.COLOR_PANEL)
	var x := PANEL.position.x
	var w := PANEL.size.x
	UiKit.text(_canvas, Vector2(x, PANEL.position.y + 13), "ВЫЗВАТЬ ЧЕЛНОК?", UiKit.TEXT, UiKit.COLOR_MARK,
			HORIZONTAL_ALIGNMENT_CENTER, w)
	UiKit.text(_canvas, Vector2(x, PANEL.position.y + 27), "что привезти?", UiKit.TEXT, UiKit.COLOR_DIM,
			HORIZONTAL_ALIGNMENT_CENTER, w)
	var tr := _track()
	var fuel_c: Color = UiKit.STAT_COLORS[UiKit.Stat.FUEL]
	var parts_c: Color = UiKit.STAT_COLORS[UiKit.Stat.ARMOR]
	# Подписи по краям: «топливо [A]» слева, «[D] запчасти» справа; под ними — сколько чего.
	var lw := 60.0
	UiKit.text(_canvas, Vector2(tr.position.x - lw - 14, SLIDER_Y + 3), "топливо [A]", UiKit.TEXT, fuel_c,
			HORIZONTAL_ALIGNMENT_RIGHT, lw)
	UiKit.text(_canvas, Vector2(tr.end.x + 14, SLIDER_Y + 3), "[D] запчасти", UiKit.TEXT, parts_c)
	UiKit.text(_canvas, Vector2(tr.position.x - lw - 14, SLIDER_Y + 15), str(fuel), UiKit.TEXT, UiKit.COLOR_TEXT,
			HORIZONTAL_ALIGNMENT_RIGHT, lw)
	UiKit.text(_canvas, Vector2(tr.end.x + 14, SLIDER_Y + 15), str(parts()), UiKit.TEXT, UiKit.COLOR_TEXT)
	# Ползунок-«весы»: левая половина — цвет топлива, правая — запчастей; чем ближе ручка к подписи,
	# тем больше этого груза (всё топливо — ручка у левого края). Стрелки «<<» и «>>» на концах.
	var split := tr.position.x + tr.size.x * float(parts()) / supply
	var half := tr.size.x * 0.5
	_canvas.draw_rect(Rect2(tr.position, Vector2(half, tr.size.y)), fuel_c.darkened(0.35))
	_canvas.draw_rect(Rect2(tr.position + Vector2(half, 0), Vector2(half, tr.size.y)), parts_c.darkened(0.35))
	for i in range(0, supply + 1, step):
		var tx := roundf(tr.position.x + tr.size.x * float(i) / supply)
		_canvas.draw_rect(Rect2(tx, tr.end.y + 1, 1, 2), UiKit.COLOR_DIM)
	_canvas.draw_rect(Rect2(roundf(split) - 1, tr.position.y - 3, 3, tr.size.y + 6), UiKit.COLOR_TEXT)
	for side: float in [-1.0, 1.0]:
		var ax := tr.position.x - 4.0 if side < 0.0 else tr.end.x + 4.0
		for j in 2:
			var o := ax + side * j * 3.0
			_canvas.draw_colored_polygon(PackedVector2Array([Vector2(o, SLIDER_Y - 2.5),
					Vector2(o + side * 3.0, SLIDER_Y + 0.5), Vector2(o, SLIDER_Y + 3.5)]), UiKit.COLOR_DIM)
	UiKit.text(_canvas, Vector2(x, SLIDER_Y + 30), "-%d очков, груз в трюме — за полцены" % penalty, UiKit.TEXT,
			UiKit.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, w)
