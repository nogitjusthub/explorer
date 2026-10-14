class_name LoadingScreen
extends CanvasLayer
## Экран загрузки перед трюмом (и после «Заново»): пока под ним догружается мир, прогреваются шейдеры и
## синтезируются звуки, игрок видит честный прогресс, а не рваный трюм. Полоса пиксельная, этап — словами;
## прогресс не идёт назад. В браузере то же уходит в HTML-оболочку (assets/web/shell.html,
## window.explorerBoot): при первой загрузке она лежит поверх холста — её анимация живёт и тогда, когда поток
## страницы стоит на компиляции шейдера; done() её убирает. Под экраном — всё прочее: трюм с заблокированным
## вводом, игровой мир, камера прогрева. На экране разом рисуются все знаки шрифта (кегли 10 и 20) —
## растеризуются заранее, а не при первом баннере в игре.

const BG := Color(0.03, 0.025, 0.06)
const BAR_W := 200.0
const BAR_H := 6.0
const FADE_S := 0.25
## Все знаки, что встречаются в интерфейсе: латиница, кириллица, цифры, знаки — растеризуются заранее.
const GLYPHS := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzАБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯабвгдеёжзийклмнопрстуфхцчшщъыьэюя0123456789 .,:;!?-—–+×%()[]«»/\"'·…↑↓←→№"

var _shown := 0.0                        ## показанный прогресс (не убывает)
var _text := ""
var _fading := -1.0
var _canvas: Control
var _web_sent := -1.0


func _ready() -> void:
	name = "LoadingScreen"
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_STOP     # ввод под экраном не проходит
	_canvas.draw.connect(_draw_screen)
	add_child(_canvas)


## Прогресс 0…1 и этап словами (дробный прогресс не убывает).
func set_progress(p: float, text: String) -> void:
	_shown = maxf(_shown, clampf(p, 0.0, 1.0))
	_text = text
	_canvas.queue_redraw()
	if OS.has_feature("web") and (absf(_shown - _web_sent) >= 0.005 or _web_sent < 0.0):
		_web_sent = _shown
		JavaScriptBridge.eval("window.explorerBoot && window.explorerBoot.progress(%.3f, %s)" % [_shown, JSON.stringify(text)])


## Убрать оболочку страницы без экрана загрузки (отладочные старты в браузере).
static func web_done() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.explorerBoot && window.explorerBoot.done()")


## Загрузка закончена: оболочка в браузере убирается, экран гаснет и уходит.
func finish() -> void:
	if _fading >= 0.0:
		return
	_shown = 1.0
	_fading = FADE_S
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.explorerBoot && window.explorerBoot.done()")


func _process(dt: float) -> void:
	if _fading < 0.0:
		return
	_fading -= dt
	_canvas.modulate.a = clampf(_fading / FADE_S, 0.0, 1.0)
	if _fading <= 0.0:
		queue_free()


func _draw_screen() -> void:
	var size := _canvas.size
	_canvas.draw_rect(Rect2(Vector2.ZERO, size), BG)
	var c := size * 0.5
	UiKit.text(_canvas, Vector2(0, c.y - 46), "EXPLORER", UiKit.TITLE, UiKit.COLOR_MARK, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	var bar := Rect2(roundf(c.x - BAR_W * 0.5), roundf(c.y - BAR_H * 0.5), BAR_W, BAR_H)
	_canvas.draw_rect(bar.grow(1.0), UiKit.COLOR_DIM, false, 1.0)
	_canvas.draw_rect(Rect2(bar.position, Vector2(floorf(BAR_W * _shown), BAR_H)), UiKit.COLOR_MARK)
	UiKit.text(_canvas, Vector2(0, c.y + 10), _text, UiKit.TEXT, UiKit.COLOR_TEXT, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	UiKit.text(_canvas, Vector2(0, c.y + 24), "%d %%" % roundi(_shown * 100.0), UiKit.TEXT, UiKit.COLOR_DIM, HORIZONTAL_ALIGNMENT_CENTER, size.x)
	# Все знаки шрифта — внутри кадра, но цветом фона (не видно): растеризуются сейчас, а не в игре.
	for fs in [UiKit.TEXT, UiKit.TITLE]:
		_canvas.draw_string(UiKit.FONT, Vector2(2, size.y - 3), GLYPHS, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, BG)
