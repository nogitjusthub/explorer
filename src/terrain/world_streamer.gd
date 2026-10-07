class_name WorldStreamer
extends Node
## Загрузка и выгрузка чанков вокруг машины (ARCHITECTURE §5.3).
## Чанк проходит этапы: генерация → (заливка ям) → сборка мешей → готов.
## Вся работа — задачами JobScheduler под бюджет кадра; узлы чанков переиспользуются из пула.

const R_LOAD := 49.0          ## тайлов: чанк нужен, если его прямоугольник ближе
const R_UNLOAD := 81.0        ## тайлов: чанк выгружается, если дальше (гистерезис)
const LOOKAHEAD_S := 2.0      ## центр загрузки смещён по скорости машины
const REFRESH_DIST := 2.0     ## пересчёт набора чанков после такого смещения центра
const PART_TREES := 5
const PART_WATER := 4
const ALL_PARTS := 0x3F

enum State { GENERATING, BUILDING, READY }

signal chunk_ready(coord: Vector2i)

var terrain: TerrainData
var generator: TerrainGenerator
var query: TerrainQuery
var scheduler: JobScheduler
var materials: TerrainMaterials
var run_seed: int

var _entries: Dictionary[Vector2i, Entry] = {}
var _pool: Array[ChunkNode] = []
var _focus := Vector2.ZERO
var _refreshed_at := Vector2(INF, INF)
var _pit_job: TerrainRepair.PitFillJob = null
var _pit_passes := 0
var _pits_needed := false


class Entry:
	extends RefCounted
	var coord: Vector2i
	var state: int = State.GENERATING
	var node: ChunkNode
	var job: Job


class GenChunkJob:
	extends Job
	var streamer: WorldStreamer
	var entry: Entry
	var gen: TerrainGenerator.GenJob

	func step(deadline_usec: int) -> bool:
		return streamer.generator.step(gen, deadline_usec)

	func on_done() -> void:
		streamer._on_generated(entry, gen.data)


class BuildChunkJob:
	extends Job
	var streamer: WorldStreamer
	var entry: Entry
	var data: ChunkData
	var parts := PackedInt32Array()
	var _k := 0

	func step(deadline_usec: int) -> bool:
		while _k < parts.size():
			streamer._build_part(entry.node, data, parts[_k])
			_k += 1
			if Time.get_ticks_usec() >= deadline_usec:
				break
		return _k >= parts.size()

	func on_done() -> void:
		streamer._on_built(entry)


class PitJob:
	extends Job
	var streamer: WorldStreamer
	var fill: TerrainRepair.PitFillJob

	func step(deadline_usec: int) -> bool:
		return fill.step(deadline_usec)

	func on_done() -> void:
		streamer._on_pits_filled(fill.changed)


func _init(t: TerrainData, gen: TerrainGenerator, q: TerrainQuery, jobs: JobScheduler, mats: TerrainMaterials) -> void:
	terrain = t
	generator = gen
	query = q
	scheduler = jobs
	materials = mats
	run_seed = gen.seed
	name = "WorldStreamer"


## Позиция и скорость машины (x, z). Вызывается каждый физический кадр.
func update_focus(pos: Vector2, vel: Vector2) -> void:
	_focus = pos + vel * LOOKAHEAD_S
	if _focus.distance_to(_refreshed_at) >= REFRESH_DIST:
		_refresh()


## Синхронная загрузка вокруг точки (экран загрузки, тесты).
func preload_around(pos: Vector2) -> void:
	_focus = pos
	_refresh()
	for _i in 8:
		scheduler.run_all()
		_maintain()
		if scheduler.pending() == 0 and _pit_job == null and not _pits_needed:
			break


func loaded_count() -> int:
	return _entries.size()


func generating_count() -> int:
	var n := 0
	for e: Entry in _entries.values():
		if e.state == State.GENERATING:
			n += 1
	return n


func is_ready(coord: Vector2i) -> bool:
	var e: Entry = _entries.get(coord)
	return e != null and e.state == State.READY


func _process(_delta: float) -> void:
	_maintain()


func _refresh() -> void:
	_refreshed_at = _focus
	var c0 := Grid.chunk_of_world(_focus.x - R_LOAD, _focus.y - R_LOAD)
	var c1 := Grid.chunk_of_world(_focus.x + R_LOAD, _focus.y + R_LOAD)
	for cz in range(c0.y, c1.y + 1):
		for cx in range(c0.x, c1.x + 1):
			var coord := Vector2i(cx, cz)
			if not _entries.has(coord) and _chunk_distance(coord) <= R_LOAD:
				_load(coord)
	for coord: Vector2i in _entries.keys():
		var e: Entry = _entries[coord]
		var dist := _chunk_distance(coord)
		if dist > R_UNLOAD:
			_unload(coord)
		elif e.job != null:
			e.job.priority = dist if e.state == State.GENERATING else dist - Grid.CHUNK
	scheduler.resort()


func _load(coord: Vector2i) -> void:
	var e := Entry.new()
	e.coord = coord
	var job := GenChunkJob.new()
	job.streamer = self
	job.entry = e
	job.gen = generator.begin(coord)
	e.job = job
	_entries[coord] = e
	scheduler.enqueue(job, _chunk_distance(coord))


func _unload(coord: Vector2i) -> void:
	var e: Entry = _entries[coord]
	if e.job != null:
		e.job.cancelled = true
		e.job = null   # разрываем цикл ссылок «запись ↔ задача», иначе память не освободится
	if e.node != null:
		e.node.clear()
		e.node.visible = false
		_pool.append(e.node)
	terrain.remove_chunk(coord)
	_entries.erase(coord)


func _on_generated(e: Entry, data: ChunkData) -> void:
	terrain.add_chunk(data)
	e.state = State.BUILDING
	e.node = _take_node()
	e.node.position = Vector3(e.coord.x * Grid.CHUNK, 0.0, e.coord.y * Grid.CHUNK)
	e.node.visible = true
	data.dirty_sections = 0
	_start_build(e, data, ALL_PARTS, _chunk_distance(e.coord) - Grid.CHUNK)
	_pits_needed = true
	_pit_passes = 0


func _on_built(e: Entry) -> void:
	e.job = null
	if e.state != State.READY:
		e.state = State.READY
		chunk_ready.emit(e.coord)


func _on_pits_filled(changed: int) -> void:
	_pit_job = null
	_pit_passes += 1
	# Заливка может открыть ещё одну яму; несколько проходов, пока есть изменения.
	_pits_needed = changed > 0 and _pit_passes < 4


func _start_build(e: Entry, data: ChunkData, mask: int, priority: float) -> void:
	var job := BuildChunkJob.new()
	job.streamer = self
	job.entry = e
	job.data = data
	for part in 6:
		if mask & (1 << part):
			job.parts.append(part)
	e.job = job
	scheduler.enqueue(job, priority)


func _build_part(node: ChunkNode, data: ChunkData, part: int) -> void:
	if part < 4:
		node.set_section(part, ChunkMesher.build_section(data, part, run_seed))
	elif part == PART_WATER:
		node.set_water(ChunkMesher.build_water(data))
	else:
		TreeField.build(node, data, query, run_seed)


## Пересборка изменённых частей и запуск заливки ям, когда генерация вокруг закончилась.
func _maintain() -> void:
	var generating := false
	for e: Entry in _entries.values():
		if e.state == State.GENERATING:
			generating = true
			continue
		if e.job != null:
			continue
		var data := terrain.chunks.get(e.coord) as ChunkData
		if data != null and data.dirty_sections != 0:
			var mask := data.dirty_sections
			data.dirty_sections = 0
			_start_build(e, data, mask, -1.0)
	if _pits_needed and not generating and _pit_job == null:
		_pits_needed = false
		var c0 := Grid.chunk_of_world(_focus.x - R_LOAD, _focus.y - R_LOAD)
		var c1 := Grid.chunk_of_world(_focus.x + R_LOAD, _focus.y + R_LOAD)
		var origin := Grid.chunk_origin(c0)
		var size := (c1 - c0 + Vector2i.ONE) * Grid.CHUNK
		_pit_job = TerrainRepair.PitFillJob.new(terrain, origin.x, origin.y, size.x, size.y)
		var job := PitJob.new()
		job.streamer = self
		job.fill = _pit_job
		scheduler.enqueue(job, -2.0)


func _take_node() -> ChunkNode:
	if not _pool.is_empty():
		return _pool.pop_back()
	var node := ChunkNode.new(materials)
	add_child(node)
	return node


## Расстояние от центра загрузки до прямоугольника чанка, в тайлах.
func _chunk_distance(coord: Vector2i) -> float:
	var x0 := float(coord.x * Grid.CHUNK)
	var z0 := float(coord.y * Grid.CHUNK)
	var dx := maxf(maxf(x0 - _focus.x, _focus.x - (x0 + Grid.CHUNK)), 0.0)
	var dz := maxf(maxf(z0 - _focus.y, _focus.y - (z0 + Grid.CHUNK)), 0.0)
	return sqrt(dx * dx + dz * dz)
