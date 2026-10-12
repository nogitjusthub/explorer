extends SceneTree
## Генератор пиксельных текстур верха рельефа (GDD §11, M5): атлас assets/textures/terrain_tops.png —
## 4 варианта (столбцы) × 6 видов поверхности (строки) по 16×16 текселей на тайл.
## Строки: 0 — грунт, 1 — песок, 2 — камень, 3 — кристалл (как ChunkData.Mat), 4 — неровный грунт
## (камни), 5 — зыбучий грунт (влажные пятна; рябь рисует шейдер).
## Текстура — множитель цвета материала в оттенках серого: значение v = множитель / GAIN, поэтому
## палитра планеты и погода остаются за шейдером. Уровни — пиксель-арт: тень, тёмный, основа,
## светлый, блик. Детерминирована (свой seed на клетку) — повторный запуск даёт тот же файл.
## Запуск: godot --headless --path . --script res://tools/textures/gen_terrain_tops.gd

const S := 16
const VARIANTS := 4
const ROWS := 6
const GAIN := 1.5                       ## шейдер умножает цвет на v × GAIN
const OUT := "res://assets/textures/terrain_tops.png"

const SHADOW := 0.62
const DARK := 0.82
const BASE := 1.0
const LIGHT := 1.14
const GLINT := 1.32

var _img: Image
var _ox := 0
var _oy := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_img = Image.create(S * VARIANTS, S * ROWS, false, Image.FORMAT_RGB8)
	var painters: Array[Callable] = [_ground, _sand, _rock, _crystal, _rough, _mire]
	for row in ROWS:
		for v in VARIANTS:
			_ox = v * S
			_oy = row * S
			_rng.seed = 9000 + row * 100 + v
			_fill(BASE)
			painters[row].call(v)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := _img.save_png(OUT)
	print("terrain tops: %s (%d×%d), error %d" % [OUT, _img.get_width(), _img.get_height(), err])
	quit()


# --- Поверхности ----------------------------------------------------------------------------------


## Грунт: пятна потемнее, мелкие тёмные крапинки, светлые комочки с тенью; в двух вариантах — кустик.
func _ground(v: int) -> void:
	for _i in 2:
		_blob(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), 7, DARK)
	for _i in 8:
		_px(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), SHADOW)
	for _i in 4:
		_pebble(_rng.randi_range(1, S - 2), _rng.randi_range(1, S - 2))
	if v >= 2:
		_tuft(_rng.randi_range(4, S - 5), _rng.randi_range(5, S - 3))


## Песок: три волнистых гребня ряби с разрывами — светлый гребень и тёмная ложбинка под ним, мягкий
## контраст; редкие тёмные зёрна.
func _sand(v: int) -> void:
	var phase := _rng.randf() * TAU
	for k in 3:
		var y0 := k * 5 + v
		for x in S:
			if _rng.randf() < 0.18:
				continue                              # разрыв гребня
			var y := posmod(y0 + roundi(1.3 * sin(x * 0.45 + phase + k * 2.0)), S)
			_px(x, y, 1.08)
			if _rng.randf() < 0.6:
				_px(x, (y + 1) % S, 0.92)
	for _i in 3:
		_px(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), DARK)


## Камень: пятнистая плита и одна-две длинные извилистые трещины (тёмные, со светлым скосом над
## ними), мягкий контраст.
func _rock(_v: int) -> void:
	for _i in 3:
		_blob(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), 10, 0.9)
	for _i in _rng.randi_range(1, 2):
		var p := Vector2(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1))
		var a := _rng.randf() * TAU
		for _j in _rng.randi_range(8, 14):
			var x := roundi(p.x)
			var y := roundi(p.y)
			_px(x, y, 0.72)
			_px(x, y - 1, 1.08)
			a += _rng.randf_range(-0.7, 0.7)          # трещина петляет
			p += Vector2.from_angle(a)


## Кристаллическая порода: основа чуть темнее, 2–4 осколка-ромба — светлые, с бликом сверху-слева и
## тенью снизу-справа.
func _crystal(_v: int) -> void:
	_fill(DARK)
	for _i in 6:
		_px(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), SHADOW)
	for _i in _rng.randi_range(2, 4):
		var cx := _rng.randi_range(2, S - 3)
		var cy := _rng.randi_range(2, S - 3)
		for dy in range(-2, 3):
			for dx in range(-2, 3):
				if absi(dx) + absi(dy) <= 2:
					_px(cx + dx, cy + dy, LIGHT)
		_px(cx - 1, cy - 1, GLINT)
		_px(cx, cy - 2, GLINT)
		_px(cx + 1, cy + 1, SHADOW)
		_px(cx + 2, cy, SHADOW)


## Неровный грунт: 4–6 камней (светлые кружки с тенью снизу-справа) и мелкий тёмный щебень.
func _rough(_v: int) -> void:
	for _i in 10:
		_px(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), DARK)
	for _i in _rng.randi_range(4, 6):
		var cx := _rng.randi_range(2, S - 3)
		var cy := _rng.randi_range(2, S - 3)
		var r := _rng.randf_range(1.2, 2.3)
		for dy in range(-3, 4):
			for dx in range(-3, 4):
				var d := Vector2(dx, dy).length()
				if d <= r:
					_px(cx + dx, cy + dy, LIGHT)
				elif Vector2(dx - 1, dy - 1).length() <= r:
					_px(cx + dx, cy + dy, SHADOW)
		_px(cx - 1, cy - 1, GLINT)


## Зыбучий грунт: влажный, ровный, с тёмными расплывчатыми пятнами (рябь поверх рисует шейдер).
func _mire(_v: int) -> void:
	_fill(DARK)
	for _i in 3:
		_blob(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), 8, SHADOW)
	for _i in 4:
		_px(_rng.randi_range(0, S - 1), _rng.randi_range(0, S - 1), BASE)


# --- Мазки ----------------------------------------------------------------------------------------


## Пятно: случайное блуждание на steps пикселей.
func _blob(x: int, y: int, steps: int, level: float) -> void:
	for _i in steps:
		_px(x, y, level)
		x += _rng.randi_range(-1, 1)
		y += _rng.randi_range(-1, 1)


## Комочек: светлый пиксель с тенью снизу-справа.
func _pebble(x: int, y: int) -> void:
	_px(x, y, LIGHT)
	_px(x + 1, y + 1, SHADOW)


## Кустик: «V» из тёмных пикселей с тенью у основания.
func _tuft(x: int, y: int) -> void:
	for d in 3:
		_px(x - d, y - d, DARK)
		_px(x + d, y - d, DARK)
	_px(x, y, SHADOW)
	_px(x, y + 1, SHADOW)


func _fill(level: float) -> void:
	for y in S:
		for x in S:
			_px(x, y, level)


## Пиксель клетки: координаты заворачиваются внутрь тайла (узор бесшовный в пределах клетки).
func _px(x: int, y: int, level: float) -> void:
	var g := level / GAIN
	_img.set_pixel(_ox + posmod(x, S), _oy + posmod(y, S), Color(g, g, g))
