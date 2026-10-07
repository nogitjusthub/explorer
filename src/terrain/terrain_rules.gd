class_name TerrainRules
extends RefCounted
## Правила тайла с угловыми высотами: выбор диагонали и высота в точке тайла.
## Мешер и TerrainQuery обязаны использовать одни и те же правила, иначе машина «провалится» в меш.


## true — диагональ NW–SE (углы 0–2), false — NE–SW (углы 1–3).
## Сгиб идёт через пару равных углов, чтобы угловой склон выглядел как поднятый/опущенный угол.
static func diagonal_02(c0: int, c1: int, c2: int, c3: int) -> bool:
	if c1 == c3 and c0 != c2:
		return false
	return true


## Высота (в ярусах) внутри тайла; u, v ∈ [0, 1] — доли по x и z от угла NW.
static func height_in_tile(c0: int, c1: int, c2: int, c3: int, u: float, v: float) -> float:
	if diagonal_02(c0, c1, c2, c3):
		if u >= v:
			return c0 + (c1 - c0) * u + (c2 - c1) * v
		return c0 + (c2 - c3) * u + (c3 - c0) * v
	if u + v <= 1.0:
		return c0 + (c1 - c0) * u + (c3 - c0) * v
	return c2 + (c3 - c2) * (1.0 - u) + (c1 - c2) * (1.0 - v)
