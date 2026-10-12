extends SceneTree
## Генератор пиксельных текстур верха рельефа (GDD §11, M5): атлас assets/textures/terrain_tops.png —
## 6 строк по 64×64 текселя; клетка накрывает 4×4 тайла (16 текселей на тайл) и бесшовна — узор идёт
## сквозь тайлы без швов и повторяется только через 4 тайла. Шейдер берёт её по мировым XZ.
## Строки: 0 — грунт (мягкие комья и пятна почвы), 1 — песок (сплошные гребни ряби), 2 — камень (плиты
## с трещинами), 3 — кристаллическая порода (гранёные плиты со светлыми жилами), 4 — неровный грунт
## (почва с мелким щебнем; крупные камни — спрайты), 5 — зыбучий грунт (влажные разводы; рябь — шейдер).
## Как прежде, значение v = множитель / GAIN: шейдер умножает цвет материала — палитра и погода прежние.
## Уровни квантуются (пиксель-арт), шум и ячейки — периодические (бесшовность). Детерминирован.
## Запуск: godot --headless --path . --script res://tools/textures/gen_terrain_tops.gd

const S := 64
const ROWS := 6
const GAIN := 1.5
const OUT := "res://assets/textures/terrain_tops.png"

var _img: Image
var _oy := 0
var _seed := 0


func _initialize() -> void:
	_img = Image.create(S, S * ROWS, false, Image.FORMAT_RGB8)
	var painters: Array[Callable] = [_ground, _sand, _rock, _crystal, _rough, _mire]
	for row in ROWS:
		_oy = row * S
		_seed = 9100 + row * 37
		painters[row].call()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	var err := _img.save_png(OUT)
	print("terrain tops: %s (%d×%d), error %d" % [OUT, _img.get_width(), _img.get_height(), err])
	quit()


# --- Поверхности ----------------------------------------------------------------------------------


## Грунт: периодический шум в четыре уровня — мягкие пятна почвы; редкие тёмные комочки.
func _ground() -> void:
	for y in S:
		for x in S:
			var n := _fbm(x, y, [4, 8, 16], [0.55, 0.3, 0.15])
			_px(x, y, _quant(n, [0.9, 0.96, 1.02, 1.07]))
	for i in 40:
		_px(_ih(i, 1) % S, _ih(i, 2) % S, 0.84)


## Песок: сплошные гребни ряби, идущие сквозь тайлы: светлый гребень, тёмная ложбинка; шаг ~5 текселей,
## гребни изгибаются по шуму.
func _sand() -> void:
	for y in S:
		for x in S:
			var warp := _fbm(x, y, [4, 8], [0.7, 0.3]) * 2.0
			var ph := fposmod((x * 0.5 + y) / 5.33 + warp, 1.0)      # 12 гребней на клетку — бесшовно
			var level := 1.0
			if ph < 0.18:
				level = 1.08
			elif ph < 0.34:
				level = 0.93
			_px(x, y, level)


## Камень: крупные плиты (ячейки Вороного, ~тайл), каждая своей яркости, с пятнами; тонкие трещины по
## границам — тень со светлым краем.
func _rock() -> void:
	var cells := _cells(4)
	for y in S:
		for x in S:
			var v := _voronoi(cells, x, y)
			var mottle := _fbm(x, y, [8, 16], [0.6, 0.4])
			var level: float = [0.94, 0.98, 1.0, 1.03][int(v.z) % 4] + (0.04 if mottle > 0.62 else (-0.04 if mottle < 0.38 else 0.0))
			if v.y - v.x < 1.0:
				level = 0.8                           # трещина между плитами
			elif v.y - v.x < 1.9:
				level = 1.05                          # светлый край у трещины
			_px(x, y, level)


## Кристаллическая порода: гранёные плиты — светлее с одной стороны ячейки, темнее с другой; по границам —
## светлые жилы.
func _crystal() -> void:
	var cells := _cells(5)
	for y in S:
		for x in S:
			var v := _voronoi(cells, x, y)
			var level := 1.0
			if v.y - v.x < 1.4:
				level = 1.16                          # жила
			else:
				var d := _wrap_delta(Vector2(x + 0.5, y + 0.5), cells[int(v.z)])
				level = 1.06 if d.x + d.y < 0.0 else 0.9   # грань к свету / от света
			_px(x, y, level)


## Неровный грунт: почва, как у грунта, с частым мелким щебнем (тёмные и светлые точки).
func _rough() -> void:
	_ground()
	for i in 220:
		_px(_ih(i, 3) % S, _ih(i, 4) % S, 1.12 if i % 3 == 0 else 0.8)


## Зыбучий грунт: влажные разводы — шум в три уровня, темнее обычного.
func _mire() -> void:
	for y in S:
		for x in S:
			var n := _fbm(x, y, [8, 16], [0.6, 0.4])
			_px(x, y, _quant(n, [0.78, 0.86, 0.94]))


# --- Периодический шум и ячейки -------------------------------------------------------------------


## Целочисленный хэш (детерминирован, зависит от строки атласа).
func _ih(a: int, b: int) -> int:
	var h := (a * 374761393 + b * 668265263 + _seed * 1013904223) & 0x7FFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0x7FFFFFFF
	return h ^ (h >> 16)


func _hf(a: int, b: int) -> float:
	return float(_ih(a, b) & 0xFFFF) / 65535.0


## Значение шума на решётке с периодом n ячеек на клетку (бесшовно по обеим осям).
func _lattice(x: int, y: int, n: int) -> float:
	var cell := float(S) / n
	var fx := x / cell
	var fy := y / cell
	var ix := floori(fx)
	var iy := floori(fy)
	var tx := smoothstep(0.0, 1.0, fx - ix)
	var ty := smoothstep(0.0, 1.0, fy - iy)
	var a := _hf(posmod(ix, n) + n * 100, posmod(iy, n))
	var b := _hf(posmod(ix + 1, n) + n * 100, posmod(iy, n))
	var c := _hf(posmod(ix, n) + n * 100, posmod(iy + 1, n))
	var d := _hf(posmod(ix + 1, n) + n * 100, posmod(iy + 1, n))
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _fbm(x: int, y: int, periods: Array, weights: Array) -> float:
	var v := 0.0
	for i in periods.size():
		v += _lattice(x, y, periods[i]) * float(weights[i])
	return v


## Уровень из списка по значению 0…1 (равные доли).
func _quant(v: float, levels: Array) -> float:
	return levels[clampi(floori(v * levels.size()), 0, levels.size() - 1)]


## Точки ячеек: по одной в каждой клетке решётки n×n (со сдвигом).
func _cells(n: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	var cell := float(S) / n
	for j in n:
		for i in n:
			pts.append(Vector2((i + 0.15 + 0.7 * _hf(i, j + 50)) * cell, (j + 0.15 + 0.7 * _hf(i + 50, j)) * cell))
	return pts


## Расстояния до точек ячеек с заворотом: x — до ближайшей, y — до второй, z — индекс ближайшей.
func _voronoi(pts: Array[Vector2], x: int, y: int) -> Vector3:
	var p := Vector2(x + 0.5, y + 0.5)
	var d1 := INF
	var d2 := INF
	var best := 0
	for i in pts.size():
		var d := _wrap_delta(p, pts[i]).length()
		if d < d1:
			d2 = d1
			d1 = d
			best = i
		elif d < d2:
			d2 = d
	return Vector3(d1, d2, best)


## Разность с заворотом по периоду клетки.
func _wrap_delta(a: Vector2, b: Vector2) -> Vector2:
	var d := a - b
	d.x -= roundf(d.x / S) * S
	d.y -= roundf(d.y / S) * S
	return d


func _px(x: int, y: int, level: float) -> void:
	var g := level / GAIN
	_img.set_pixel(posmod(x, S), _oy + posmod(y, S), Color(g, g, g))
