class_name DebugSnapshot
extends RefCounted
## Отладочный снимок (F12): всё, чтобы воспроизвести и разобрать проблемное место.
##   screenshot.png — кадр (рендер ×2 без сглаживания);
##   map.png        — карта 65×65 тайлов вокруг машины (легенда — MapRender), машина — крест;
##   info.txt       — seed, коммит, команда воспроизведения, состояние машины, рёбра её тайла,
##                    сетка ярусов 17×17 вокруг;
##   tiles.json     — полный дамп тайлов 17×17 вокруг машины.
## Каталог: build/debug/<дата_время>/ в папке проекта; если туда не записать — user://debug/.
## В вебе скриншот и info.txt уходят POST-запросами на /shot и /log (tools/scripts/web_server.py).

const DUMP_RADIUS := 8
const MAP_RADIUS := 32
const MAP_SCALE := 6
const DIR_NAMES := ["N (−z)", "E (+x)", "S (+z)", "W (−x)"]


## Возвращает путь к каталогу снимка (в вебе — пустую строку).
static func capture(viewport: Viewport, vehicle: Vehicle, q: TerrainQuery, run_seed: int, camera_quarter: int) -> String:
	var shot := viewport.get_texture().get_image()
	shot.resize(shot.get_width() * 2, shot.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var info := _info_text(vehicle, q, run_seed, camera_quarter)

	if OS.has_feature("web"):
		_web_post("/shot", Marshalls.raw_to_base64(shot.save_png_to_buffer()), true)
		_web_post("/log", info, false)
		return ""

	var dir := _snapshot_dir()
	shot.save_png(dir.path_join("screenshot.png"))
	var t := vehicle.state.tile
	var map := MapRender.render(q, t.x - MAP_RADIUS, t.y - MAP_RADIUS, MAP_RADIUS * 2 + 1, MAP_RADIUS * 2 + 1, MAP_SCALE)
	MapRender.mark_vehicle(map, t.x - MAP_RADIUS, t.y - MAP_RADIUS, MAP_SCALE, vehicle.state.pos, vehicle.state.heading)
	map.save_png(dir.path_join("map.png"))
	_write_text(dir.path_join("info.txt"), info)
	_write_text(dir.path_join("tiles.json"), JSON.stringify(_tiles_dump(vehicle, q, run_seed), "\t"))
	return dir


static func _info_text(vehicle: Vehicle, q: TerrainQuery, run_seed: int, camera_quarter: int) -> String:
	var s := vehicle.state
	var t := s.tile
	var lines := PackedStringArray()
	lines.append("Explorer — отладочный снимок %s" % Time.get_datetime_string_from_system(false, true))
	lines.append("Godot %s | коммит %s | seed %d" % [Engine.get_version_info().string, _git_commit(), run_seed])
	lines.append("Воспроизвести: play.cmd --seed=%d --spawn=%d,%d" % [run_seed, t.x, t.y])
	lines.append("")
	var state := "на земле"
	if s.drowning:
		state = "тонет (%.1f с)%s" % [s.drown_time, ", утонула" if s.drowned else ""]
	elif s.falling:
		state = "падает в тайл %s с яруса %.2f" % [s.fall_tile, s.fall_from_tier]
	lines.append("Машина (%s): pos (%.2f, %.2f), тайл %s, чанк %s" % [vehicle.cls.id, s.pos.x, s.pos.y, t, Grid.chunk_of_tile(t.x, t.y)])
	lines.append("  курс %.0f°, скорость %.2f / %.2f, газ %.2f, подъём подряд %d" % [
			fposmod(rad_to_deg(s.heading), 360.0), s.vel.length(), vehicle.cls.max_speed, s.throttle, s.uphill_tiles])
	lines.append("  состояние: %s" % state)
	var water := q.water_tier(t.x, t.y)
	var water_text := "нет" if water == TerrainQuery.NO_WATER else "ярус %d, глубина %.2f" % [water, q.water_depth(s.pos.x, s.pos.y)]
	lines.append("  ярус поверхности %.2f, мировая высота днища %.2f, вода: %s" % [q.surface_tier(s.pos.x, s.pos.y), s.y, water_text])
	lines.append("  углы тайла (NW, NE, SE, SW): %s" % _corners_text(q, t.x, t.y))
	lines.append("Камера: поворот %d × 90°" % camera_quarter)
	lines.append("")
	lines.append("Рёбра тайла машины — подъём в соседа у начала / середины / конца ребра, ярусов")
	lines.append("(больше %.2f — стенка, меньше −%.2f — падение; WALL — сосед не загружен):" % [
			VehicleKinematics.STEP_TOLERANCE, VehicleKinematics.STEP_TOLERANCE])
	for d in 4:
		var n := t + Grid.DIR_OFFSETS[d]
		var r0 := q.edge_rise_at(t.x, t.y, d, 0.0)
		var r1 := q.edge_rise_at(t.x, t.y, d, 0.5)
		var r2 := q.edge_rise_at(t.x, t.y, d, 1.0)
		var nw := q.water_tier(n.x, n.y)
		var nw_text := "" if nw == TerrainQuery.NO_WATER else ", вода ярус %d" % nw
		lines.append("  %s → %s: %+.2f / %+.2f / %+.2f; углы соседа %s%s" % [DIR_NAMES[d], n, r0, r1, r2, _corners_text(q, n.x, n.y), nw_text])
	lines.append("")
	lines.append("Тайлы вокруг: минимальный ярус угла (~ вода, ^ дерево, _ повалено, P площадка, [ ] — машина, x — не загружено)")
	var header := "     x:"
	for dx in range(-DUMP_RADIUS, DUMP_RADIUS + 1):
		header += "%5d" % (t.x + dx)
	lines.append(header)
	for dz in range(-DUMP_RADIUS, DUMP_RADIUS + 1):
		var tz := t.y + dz
		var row := "z %4d:" % tz
		for dx in range(-DUMP_RADIUS, DUMP_RADIUS + 1):
			row += _tile_cell(q, t.x + dx, tz, dx == 0 and dz == 0)
		lines.append(row)
	return "\n".join(lines) + "\n"


static func _tile_cell(q: TerrainQuery, tx: int, tz: int, is_vehicle: bool) -> String:
	var d := q.data.owner_of(tx, tz)
	if d == null:
		return "    x"
	var i := d.local_index(tx, tz)
	var lo := mini(mini(d.get_corner(i, 0), d.get_corner(i, 1)), mini(d.get_corner(i, 2), d.get_corner(i, 3)))
	var mark := " "
	if d.flags[i] & ChunkData.FLAG_PAD:
		mark = "P"
	elif d.get_water(i) != TerrainQuery.NO_WATER:
		mark = "~"
	elif d.trees[i] != ChunkData.TREE_NONE:
		mark = "_" if d.trees[i] & ChunkData.TREE_FELLED else "^"
	var cell := "%d%s" % [lo, mark]
	return ("[%s]" % cell).lpad(5) if is_vehicle else cell.lpad(5)


static func _corners_text(q: TerrainQuery, tx: int, tz: int) -> String:
	var d := q.data.owner_of(tx, tz)
	if d == null:
		return "не загружен"
	var i := d.local_index(tx, tz)
	return "%d, %d, %d, %d" % [d.get_corner(i, 0), d.get_corner(i, 1), d.get_corner(i, 2), d.get_corner(i, 3)]


static func _tiles_dump(vehicle: Vehicle, q: TerrainQuery, run_seed: int) -> Dictionary:
	var s := vehicle.state
	var t := s.tile
	var tiles: Array[Dictionary] = []
	for dz in range(-DUMP_RADIUS, DUMP_RADIUS + 1):
		for dx in range(-DUMP_RADIUS, DUMP_RADIUS + 1):
			var tx := t.x + dx
			var tz := t.y + dz
			var d := q.data.owner_of(tx, tz)
			if d == null:
				continue
			var i := d.local_index(tx, tz)
			tiles.append({
				"x": tx, "z": tz,
				"corners": [d.get_corner(i, 0), d.get_corner(i, 1), d.get_corner(i, 2), d.get_corner(i, 3)],
				"water": d.get_water(i), "material": d.material[i], "biome": d.biome[i],
				"tree": d.trees[i], "flags": d.flags[i],
				"in_diff": not q.data.diffs.get_record(tx, tz).is_empty(),
			})
	return {
		"seed": run_seed, "commit": _git_commit(),
		"vehicle": {
			"class": String(vehicle.cls.id), "pos": [s.pos.x, s.pos.y], "y": s.y, "tile": [t.x, t.y],
			"heading_deg": rad_to_deg(s.heading), "vel": [s.vel.x, s.vel.y], "throttle": s.throttle,
			"falling": s.falling, "fall_tile": [s.fall_tile.x, s.fall_tile.y], "drowning": s.drowning,
			"uphill_tiles": s.uphill_tiles,
		},
		"tiles": tiles,
	}


## build/debug/<дата_время>/ в папке проекта; если туда не записать — user://debug/<дата_время>/.
static func _snapshot_dir() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	for base in [ProjectSettings.globalize_path("res://build/debug"), ProjectSettings.globalize_path("user://debug")]:
		var dir: String = (base as String).path_join(stamp)
		if DirAccess.make_dir_recursive_absolute(dir) == OK:
			return dir
	return ProjectSettings.globalize_path("user://")


static func _git_commit() -> String:
	var head := FileAccess.get_file_as_string("res://.git/HEAD").strip_edges()
	if head.begins_with("ref: "):
		var sha := FileAccess.get_file_as_string("res://.git/" + head.trim_prefix("ref: ")).strip_edges()
		return sha.left(8) if not sha.is_empty() else "?"
	return head.left(8) if not head.is_empty() else "?"


static func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(text)


static func _web_post(path: String, payload: String, base64: bool) -> void:
	var body := "Uint8Array.from(atob('%s'), c => c.charCodeAt(0))" % payload if base64 else JSON.stringify(payload)
	JavaScriptBridge.eval("fetch('%s', {method: 'POST', body: %s})" % [path, body])
