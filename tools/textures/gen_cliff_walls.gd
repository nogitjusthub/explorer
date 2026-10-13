extends SceneTree
## Генератор пиксельных текстур стенок обрывов (GDD §11, M5): атлас assets/textures/cliff_walls.png —
## 4 варианта (столбцы) по 16×9 текселей: 16 — вдоль стенки на тайл, 9 — на высоту яруса (ярус
## 0,5625 тайла — тексели квадратные, ровно пиксель мира). Строка 0 — верх яруса.
## Пласт: светлая кромка сверху и тень у основания (каждый ярус читается отдельной полосой), тонкие
## прослойки осадка с разрывами, трещины сверху вниз со светлым краем, камешки с тенью, пятна.
## Как и у верха (gen_terrain_tops.gd), значение v = множитель / GAIN: шейдер умножает цвет пласта
## (по абсолютному ярусу) — палитра и погода прежние. Детерминирован.
## Запуск: godot --headless --path . --script res://tools/textures/gen_cliff_walls.gd

const W := 16
const H := 9
const VARIANTS := 4
const GAIN := 1.5
const OUT := "res://assets/textures/cliff_walls.png"

var _img: Image
var _ox := 0
var _rng := RandomNumberGenerator.new()


func _initialize() -> void:
	_img = Image.create(W * VARIANTS, H, false, Image.FORMAT_RGB8)
	for v in VARIANTS:
		_ox = v * W
		_rng.seed = 7700 + v
		_paint()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := _img.save_png(OUT)
	print("cliff walls: %s (%d×%d), error %d" % [OUT, _img.get_width(), _img.get_height(), err])
	quit()


func _paint() -> void:
	for y in H:
		for x in W:
			_px(x, y, 1.0)
	# Пятна потемнее.
	for _i in 2:
		var x := _rng.randi_range(0, W - 1)
		var y := _rng.randi_range(2, H - 3)
		for _j in 6:
			_px(x, y, 0.92)
			x += _rng.randi_range(-1, 1)
			y = clampi(y + _rng.randi_range(-1, 1), 1, H - 2)
	# Прослойки осадка: горизонтальные линии с разрывами.
	for _i in _rng.randi_range(1, 2):
		var y := _rng.randi_range(3, H - 4)
		for x in W:
			if _rng.randf() < 0.75:
				_px(x, y, 0.88)
	# Камешки: светлый пиксель с тенью снизу-справа.
	for _i in _rng.randi_range(2, 3):
		var x := _rng.randi_range(0, W - 2)
		var y := _rng.randi_range(2, H - 3)
		_px(x, y, 1.14)
		_px(x + 1, y + 1, 0.78)
	# Трещины: от кромки вниз, ломаные, со светлым правым краем.
	for _i in _rng.randi_range(1, 2):
		var x := _rng.randi_range(1, W - 2)
		for y in range(1, _rng.randi_range(4, H - 1)):
			_px(x, y, 0.7)
			_px(x + 1, y, 1.06)
			if _rng.randf() < 0.35:
				x = clampi(x + (1 if _rng.randf() < 0.5 else -1), 0, W - 2)
	# Кромка пласта сверху и тень у основания.
	for x in W:
		_px(x, 0, 1.14 if _rng.randf() < 0.85 else 1.0)
		_px(x, H - 1, 0.82)


func _px(x: int, y: int, level: float) -> void:
	var g := level / GAIN
	_img.set_pixel(_ox + posmod(x, W), clampi(y, 0, H - 1), Color(g, g, g))
