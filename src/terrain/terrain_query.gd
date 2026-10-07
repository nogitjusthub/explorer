class_name TerrainQuery
extends RefCounted
## Запросы к рельефу для движения и объектов: высота, нормаль, стенки, вода, деревья.
## Высоты — в ярусах, если не сказано иное; координаты x, z — мировые.

const UNLOADED := -10000
const WALL := 1000            ## подъём ребра, если сосед не загружен — непроходимо
const NO_WATER := -1000
const TREE_RADIUS := 0.35

var data: TerrainData


func _init(terrain: TerrainData) -> void:
	data = terrain


func is_loaded(tx: int, tz: int) -> bool:
	return data.is_loaded(tx, tz)


## Высота поверхности в ярусах (плоскость треугольника тайла).
func surface_tier(x: float, z: float) -> float:
	var tx := floori(x)
	var tz := floori(z)
	var d := data.owner_of(tx, tz)
	if d == null:
		return UNLOADED
	var i := d.local_index(tx, tz)
	return TerrainRules.height_in_tile(d.get_corner(i, 0), d.get_corner(i, 1), d.get_corner(i, 2),
			d.get_corner(i, 3), x - tx, z - tz)


func surface_y(x: float, z: float) -> float:
	return surface_tier(x, z) * Grid.TIER_H


## Нормаль поверхности в мировых единицах (по конечным разностям).
func normal_at(x: float, z: float) -> Vector3:
	const E := 0.1
	var dx := (surface_tier(x + E, z) - surface_tier(x - E, z)) * Grid.TIER_H
	var dz := (surface_tier(x, z + E) - surface_tier(x, z - E)) * Grid.TIER_H
	return Vector3(-dx, 2.0 * E, -dz).normalized()


func corner(tx: int, tz: int, c: int) -> int:
	var d := data.owner_of(tx, tz)
	if d == null:
		return UNLOADED
	return d.get_corner(d.local_index(tx, tz), c)


## Подъём ребра при переходе из тайла (tx, tz) в соседа по направлению dir (Grid.DIR_*):
## максимум разности «угол соседа − свой угол» по двум углам ребра. > 0 — стенка вверх.
func edge_rise(tx: int, tz: int, dir: int) -> int:
	var o := Grid.DIR_OFFSETS[dir]
	var da := data.owner_of(tx, tz)
	var db := data.owner_of(tx + o.x, tz + o.y)
	if da == null or db == null:
		return WALL
	var ia := da.local_index(tx, tz)
	var ib := db.local_index(tx + o.x, tz + o.y)
	var own := Grid.EDGE_OWN[dir]
	var nb := Grid.EDGE_NEIGHBOR[dir]
	return maxi(db.get_corner(ib, nb.x) - da.get_corner(ia, own.x), db.get_corner(ib, nb.y) - da.get_corner(ia, own.y))


## Высота обрыва вниз при переходе в соседа: максимум «свой угол − угол соседа».
func edge_drop(tx: int, tz: int, dir: int) -> int:
	var o := Grid.DIR_OFFSETS[dir]
	var da := data.owner_of(tx, tz)
	var db := data.owner_of(tx + o.x, tz + o.y)
	if da == null or db == null:
		return 0
	var ia := da.local_index(tx, tz)
	var ib := db.local_index(tx + o.x, tz + o.y)
	var own := Grid.EDGE_OWN[dir]
	var nb := Grid.EDGE_NEIGHBOR[dir]
	return maxi(da.get_corner(ia, own.x) - db.get_corner(ib, nb.x), da.get_corner(ia, own.y) - db.get_corner(ib, nb.y))


## Ярус зеркала воды на тайле или NO_WATER.
func water_tier(tx: int, tz: int) -> int:
	var d := data.owner_of(tx, tz)
	if d == null:
		return NO_WATER
	return d.get_water(d.local_index(tx, tz))


## Глубина воды в точке, ярусы (≤ 0 — сухо).
func water_depth(x: float, z: float) -> float:
	var w := water_tier(floori(x), floori(z))
	if w == NO_WATER:
		return 0.0
	return w - surface_tier(x, z)


func material(tx: int, tz: int) -> int:
	var d := data.owner_of(tx, tz)
	if d == null:
		return ChunkData.Mat.ROCK
	return d.material[d.local_index(tx, tz)]


## Стоящее (не поваленное) дерево на тайле.
func has_standing_tree(tx: int, tz: int) -> bool:
	var d := data.owner_of(tx, tz)
	if d == null:
		return false
	var t := d.trees[d.local_index(tx, tz)]
	return t != ChunkData.TREE_NONE and (t & ChunkData.TREE_FELLED) == 0


## Мировая позиция (x, z) дерева тайла.
func tree_position(tx: int, tz: int) -> Vector2:
	var d := data.owner_of(tx, tz)
	if d == null:
		return Vector2(tx + 0.5, tz + 0.5)
	var off := d.tree_offset[d.local_index(tx, tz)]
	return Vector2(tx + 0.25 + (off >> 4) / 30.0, tz + 0.25 + (off & 0xF) / 30.0)


## Валит дерево: запись в окна чанков и DiffStore, пересборка деревьев владельца.
func fell_tree(tx: int, tz: int) -> void:
	var d := data.owner_of(tx, tz)
	if d == null:
		return
	var record := d.read_record(d.local_index(tx, tz))
	record[6] = record[6] | ChunkData.TREE_FELLED
	data.write_tile(tx, tz, record, false, true)
