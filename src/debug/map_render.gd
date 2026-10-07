class_name MapRender
extends RefCounted
## Карта рельефа сверху для отладки (по умолчанию 3 пикселя на тайл): цвет материала × высота;
## синий — вода; тёмно-зелёный — дерево; пурпурный — площадка челнока; чёрная линия — стенка
## ≥ 2 яруса, оранжевая — уступ в 1 ярус; красный — тайл без выхода; тёмно-серый — не загружено.
## Общая для предпросмотра генератора (map_preview.gd) и отладочного снимка (F12).

const MATERIAL_COLORS: Array[Color] = [
	Color(0.62, 0.38, 0.27),   # грунт
	Color(0.74, 0.66, 0.78),   # песок
	Color(0.36, 0.42, 0.52),   # камень
	Color(0.30, 0.85, 0.80),   # кристалл
]
const UNLOADED_COLOR := Color(0.15, 0.15, 0.17)
const LEDGE_COLOR := Color(0.95, 0.55, 0.1)
const CLIFF_COLOR := Color(0, 0, 0)


## trapped — необязательная маска w×h (0 — тайл без выхода, красим красным).
static func render(q: TerrainQuery, x0: int, z0: int, w: int, h: int, scale: int = 3,
		trapped := PackedByteArray()) -> Image:
	var img := Image.create(w * scale, h * scale, false, Image.FORMAT_RGB8)
	for lz in h:
		for lx in w:
			var tx := x0 + lx
			var tz := z0 + lz
			var d := q.data.owner_of(tx, tz)
			if d == null:
				img.fill_rect(Rect2i(lx * scale, lz * scale, scale, scale), UNLOADED_COLOR)
				continue
			var i := d.local_index(tx, tz)
			var c0 := d.get_corner(i, 0)
			var c1 := d.get_corner(i, 1)
			var c2 := d.get_corner(i, 2)
			var c3 := d.get_corner(i, 3)
			var avg := (c0 + c1 + c2 + c3) / 4.0
			var col: Color = MATERIAL_COLORS[d.material[i]]
			col = col * clampf(0.45 + avg * 0.045, 0.3, 1.25)
			var gx := (c1 + c2 - c0 - c3) * 0.5
			var gz := (c2 + c3 - c0 - c1) * 0.5
			col = col * clampf(1.0 - 0.18 * (gx + gz), 0.6, 1.4)
			var water := d.get_water(i)
			if water != TerrainQuery.NO_WATER:
				col = col.lerp(Color(0.08, 0.42, 0.45), clampf(0.55 + (water - avg) * 0.12, 0.5, 0.95))
			if d.flags[i] & ChunkData.FLAG_PAD:
				col = Color(0.9, 0.2, 0.85)
			if not trapped.is_empty() and trapped[lz * w + lx] == 0:
				col = Color(1, 0, 0)
			img.fill_rect(Rect2i(lx * scale, lz * scale, scale, scale), col)
			if d.trees[i] != ChunkData.TREE_NONE and scale >= 3:
				var tree_col := Color(0.35, 0.3, 0.2) if d.trees[i] & ChunkData.TREE_FELLED else Color(0.1, 0.3, 0.15)
				img.set_pixel(lx * scale + scale / 2, lz * scale + scale / 2, tree_col)
			# Стенки на восточном и южном рёбрах (каждое ребро рисуется один раз).
			for dir in [Grid.DIR_E, Grid.DIR_S]:
				var step := maxi(q.edge_rise(tx, tz, dir), q.edge_drop(tx, tz, dir))
				if step <= 0 or step >= TerrainQuery.WALL:
					continue
				var wall_col := LEDGE_COLOR if step == 1 else CLIFF_COLOR
				if dir == Grid.DIR_E:
					img.fill_rect(Rect2i(lx * scale + scale - 1, lz * scale, 1, scale), wall_col)
				else:
					img.fill_rect(Rect2i(lx * scale, lz * scale + scale - 1, scale, 1), wall_col)
	return img


## Метка машины: белый крест и линия курса.
static func mark_vehicle(img: Image, x0: int, z0: int, scale: int, pos: Vector2, heading: float) -> void:
	var c := Vector2((pos.x - x0) * scale, (pos.y - z0) * scale)
	for k in range(-scale * 2, scale * 2 + 1):
		_plot(img, c + Vector2(k, 0), Color.WHITE)
		_plot(img, c + Vector2(0, k), Color.WHITE)
	var dir := Vector2.from_angle(heading)
	for k in scale * 5:
		_plot(img, c + dir * k, Color(1, 1, 0))


static func _plot(img: Image, p: Vector2, col: Color) -> void:
	var x := roundi(p.x)
	var y := roundi(p.y)
	if x >= 0 and y >= 0 and x < img.get_width() and y < img.get_height():
		img.set_pixel(x, y, col)
