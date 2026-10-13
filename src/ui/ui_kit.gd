class_name UiKit
extends RefCounted
## Общие элементы интерфейса: кнопки с хоткеем (нажимаются и мышью, и тапом — веб на телефоне),
## текст с тенью, значки характеристик техники и шкала «N из 5».
##
## Шрифт — пиксельный Ark Pixel 10px (assets/fonts, OFL; урезан до латиницы, кириллицы и знаков): без
## сглаживания и хинтинга, по целым пикселям. Кегли — только кратные его 10 px (TEXT, TITLE), иначе буквы
## не ложатся в пиксели рендера 480×320. Знака минус U+2212 в нём нет — в тексте на экране дефис.

const COLOR_TEXT := Color(0.95, 0.92, 0.85)
const COLOR_DIM := Color(0.62, 0.58, 0.66)
const COLOR_MARK := Color(1.0, 0.8, 0.3)
const COLOR_PANEL := Color(0.06, 0.04, 0.1, 0.82)
const COLOR_BUTTON := Color(0.16, 0.12, 0.22, 0.92)
const COLOR_BUTTON_HOVER := Color(0.26, 0.2, 0.34, 0.95)
const COLOR_EDGE := Color(1.0, 0.8, 0.3, 0.7)
const COLOR_PIP_EMPTY := Color(0.3, 0.28, 0.36)

enum Stat { FUEL, ARMOR, HANDLING, CARGO }
const STAT_NAMES := ["ТОПЛИВО", "БРОНЯ", "МАНЁВР", "ГРУЗ"]
const STAT_COLORS := [Color(1.0, 0.72, 0.2), Color(0.46, 0.9, 0.4), Color(0.45, 0.85, 1.0), Color(0.3, 0.95, 0.9)]
const PIPS := 5
const FONT: Font = preload("res://assets/fonts/ark-pixel-10px.ttf")
const TEXT := 10                         ## кегль текста — родной размер шрифта
const TITLE := 20                        ## заголовки, счёт — вдвое


## Кнопка «ТЕКСТ  [клавиша]»: плоская панель, рамка при наведении и фокусе.
static func button(text: String, hotkey: String, font_size: int = TEXT) -> Button:
	var b := Button.new()
	b.text = "%s   [%s]" % [text, hotkey] if not hotkey.is_empty() else text
	b.focus_mode = Control.FOCUS_NONE           # клавиатура — хоткеями, без фокуса
	b.add_theme_font_size_override(&"font_size", font_size)
	b.add_theme_color_override(&"font_color", COLOR_TEXT)
	b.add_theme_color_override(&"font_hover_color", COLOR_MARK)
	b.add_theme_color_override(&"font_pressed_color", COLOR_MARK)
	b.add_theme_stylebox_override(&"normal", _box(COLOR_BUTTON, Color(0, 0, 0, 0)))
	b.add_theme_stylebox_override(&"hover", _box(COLOR_BUTTON_HOVER, COLOR_EDGE))
	b.add_theme_stylebox_override(&"pressed", _box(COLOR_BUTTON_HOVER, COLOR_MARK))
	b.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	return b


static func _box(fill: Color, edge: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = edge
	s.set_border_width_all(1)
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 3
	s.content_margin_bottom = 3
	return s


## Текст с тенью в 1 пиксель.
static func text(canvas: CanvasItem, pos: Vector2, s: String, font_size: int, color: Color,
		align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT, width: float = -1.0) -> void:
	canvas.draw_string(FONT, pos + Vector2.ONE, s, align, width, font_size, Color(0, 0, 0, 0.85))
	canvas.draw_string(FONT, pos, s, align, width, font_size, color)


## Строка характеристики: значок, название, шкала из PIPS делений. pos — левый верхний угол строки; шкалы
## всех строк — на одной вертикали: за самым длинным названием.
static func stat_row(canvas: CanvasItem, pos: Vector2, stat: Stat, value: int) -> void:
	var color: Color = STAT_COLORS[stat]
	stat_icon(canvas, pos, stat, color)
	text(canvas, pos + Vector2(12, 8), STAT_NAMES[stat], TEXT, COLOR_DIM)
	var x := pos.x + 12.0 + stat_name_width()
	for i in PIPS:
		var r := Rect2(x + i * 8.0, pos.y + 1.0, 6.0, 7.0)
		if i < value:
			canvas.draw_rect(r, color)
		else:
			canvas.draw_rect(r, COLOR_PIP_EMPTY, false, 1.0)


## Ширина колонки названий характеристик: самое длинное название и зазор.
static func stat_name_width() -> float:
	var w := 0.0
	for s: String in STAT_NAMES:
		w = maxf(w, FONT.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT).x)
	return ceilf(w) + 5.0


## Значки 9×9 пикселей: канистра, щит, поворотная стрелка, ящик.
static func stat_icon(canvas: CanvasItem, pos: Vector2, stat: Stat, color: Color) -> void:
	var o := pos.floor()
	match stat:
		Stat.FUEL:
			canvas.draw_rect(Rect2(o + Vector2(1, 2), Vector2(7, 7)), color)
			canvas.draw_rect(Rect2(o + Vector2(5, 0), Vector2(3, 2)), color)
			canvas.draw_line(o + Vector2(2.5, 4.5), o + Vector2(6.5, 8), Color(0, 0, 0, 0.5), 1.0)
		Stat.ARMOR:
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(0.5, 0.5), o + Vector2(8.5, 0.5),
					o + Vector2(8.5, 4.5), o + Vector2(4.5, 9), o + Vector2(0.5, 4.5)]), color)
			canvas.draw_line(o + Vector2(4.5, 1.5), o + Vector2(4.5, 7.5), Color(0, 0, 0, 0.4), 1.0)
		Stat.HANDLING:
			canvas.draw_arc(o + Vector2(4.5, 5.0), 3.5, PI * 0.6, PI * 2.0, 8, color, 1.5)
			canvas.draw_colored_polygon(PackedVector2Array([o + Vector2(6.5, 2.0), o + Vector2(9, 5.5),
					o + Vector2(5, 5.5)]), color)
		Stat.CARGO:
			canvas.draw_rect(Rect2(o + Vector2(0, 2), Vector2(9, 7)), color)
			canvas.draw_rect(Rect2(o + Vector2(1, 0), Vector2(7, 2)), color.darkened(0.3))
			canvas.draw_line(o + Vector2(0, 5.5), o + Vector2(9, 5.5), Color(0, 0, 0, 0.45), 1.0)


## Значения характеристик класса по порядку Stat.
static func stats_of(cls: VehicleClass) -> PackedInt32Array:
	return PackedInt32Array([cls.stat_fuel, cls.stat_armor, cls.stat_handling, cls.stat_cargo])


## Нажатие мыши или касание (касание приходит и как эмуляция мыши — берём только мышь).
static func is_click(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
