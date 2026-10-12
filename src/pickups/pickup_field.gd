class_name PickupField
extends Node3D
## Находки в мире (GDD §6): появляются вместе с чанками, рисуются MultiMesh'ами по видам,
## подбираются машиной. Собранные запоминаются по тайлу и после выгрузки чанка не возвращаются.
## Вытесненное из трюма выпадает на землю рядом с машиной и тоже запоминается.
## Канистры: при первой загрузке чанка с вероятностью D(t) = D0 × max(floor, 1 − t / fade).

const NONE_TILE := Vector2i(-999999, -999999)
const HOVER_Y := 0.35                 ## находка парит над поверхностью

var terrain: TerrainData
var query: TerrainQuery
var run_seed: int
var rules: BalanceRules
var run_time := 0.0                             ## время забега для плотности канистр

var _active: Dictionary[int, StringName] = {}               ## ключ тайла → вид
var _by_chunk: Dictionary[Vector2i, PackedInt64Array] = {}  ## чанк → ключи его активных находок
var _taken: Dictionary[int, bool] = {}                      ## собранные статичные находки
var _dropped: Dictionary[int, StringName] = {}              ## выпавшие из трюма
var _canisters: Dictionary[Vector2i, Vector2i] = {}         ## чанк → тайл канистры (или NONE_TILE)
var _nodes: Dictionary[Vector2i, Node3D] = {}
var _meshes: Dictionary[StringName, Mesh] = {}


func _init(t: TerrainData, q: TerrainQuery, seed_value: int, balance: BalanceRules) -> void:
	terrain = t
	query = q
	run_seed = seed_value
	rules = balance
	name = "PickupField"
	var shader: Shader = load("res://src/render/shaders/pickup.gdshader")
	var outline := ShaderMaterial.new()
	outline.shader = load("res://src/render/shaders/pickup_outline.gdshader")
	for id in Balance.pickup_ids():
		_meshes[id] = _make_mesh(Balance.pickup(id), shader, outline)


## Меши всех видов находок (прогрев шейдеров).
func meshes() -> Array[Mesh]:
	var out: Array[Mesh] = []
	out.assign(_meshes.values())
	return out


## Чанк собран (впервые или пересобран после правки рельефа): находки и их высоты.
func on_chunk_built(coord: Vector2i) -> void:
	if not _by_chunk.has(coord):
		_populate(coord)
	_rebuild(coord)


func on_chunk_removed(coord: Vector2i) -> void:
	for key in _by_chunk.get(coord, PackedInt64Array()):
		_active.erase(key)
	_by_chunk.erase(coord)
	var node: Node3D = _nodes.get(coord)
	if node != null:
		node.queue_free()
		_nodes.erase(coord)


## Находки в радиусе от точки (x, z): [{key, kind, pos}, ...].
func near(pos: Vector2, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var t0 := Vector2i(floori(pos.x - radius), floori(pos.y - radius))
	var t1 := Vector2i(floori(pos.x + radius), floori(pos.y + radius))
	for tz in range(t0.y, t1.y + 1):
		for tx in range(t0.x, t1.x + 1):
			var key := DiffStore.key(tx, tz)
			if not _active.has(key):
				continue
			var p := Vector2(tx + 0.5, tz + 0.5)
			if p.distance_to(pos) <= radius:
				result.append({"key": key, "kind": _active[key], "pos": p})
	return result


## Все активные находки в радиусе (для радара): [{key, kind, pos}, ...].
func within(pos: Vector2, radius: float) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var r2 := radius * radius
	for key in _active:
		var t := DiffStore.key_tile(key)
		var p := Vector2(t.x + 0.5, t.y + 0.5)
		if p.distance_squared_to(pos) <= r2:
			result.append({"key": key, "kind": _active[key], "pos": p})
	return result


## Забрать находку: исчезает навсегда (до конца забега).
func take(key: int) -> void:
	if not _active.has(key):
		return
	_active.erase(key)
	if _dropped.has(key):
		_dropped.erase(key)
	else:
		_taken[key] = true
	var t := DiffStore.key_tile(key)
	var coord := Grid.chunk_of_tile(t.x, t.y)
	var keys: PackedInt64Array = _by_chunk.get(coord, PackedInt64Array())
	var idx := keys.find(key)
	if idx >= 0:
		keys.remove_at(idx)
		_by_chunk[coord] = keys
	_rebuild(coord)


## Положить предмет на землю рядом с точкой (вытесненное из трюма), не ближе min_dist — чтобы
## машина не подобрала его тут же. false — некуда.
func drop(kind: StringName, near_pos: Vector2, min_dist: float = 0.0) -> bool:
	var center := Vector2i(floori(near_pos.x), floori(near_pos.y))
	for r in range(1, 4):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var t := center + Vector2i(dx, dz)
				var key := DiffStore.key(t.x, t.y)
				if _active.has(key) or not _tile_free(t) 						or Vector2(t.x + 0.5, t.y + 0.5).distance_to(near_pos) < min_dist:
					continue
				_dropped[key] = kind
				_add(key, kind, Grid.chunk_of_tile(t.x, t.y))
				_rebuild(Grid.chunk_of_tile(t.x, t.y))
				return true
	return false


## Сколько топлива даст канистра на тайле (детерминированно в диапазоне вида), доля бака.
func canister_fraction(key: int, kind: PickupKind) -> float:
	var t := DiffStore.key_tile(key)
	return lerpf(kind.fuel_restore_min, kind.fuel_restore_max, DetRng.unit(run_seed, t.x, t.y, 630))


func active_count() -> int:
	return _active.size()


func _populate(coord: Vector2i) -> void:
	_by_chunk[coord] = PackedInt64Array()
	var data: ChunkData = terrain.chunks.get(coord)
	if data == null:
		return
	for p in PickupGenerator.for_chunk(data, run_seed, rules):
		var tile: Vector2i = p["tile"]
		var key := DiffStore.key(tile.x, tile.y)
		if not _taken.has(key):
			_add(key, p["kind"], coord)
	if not _canisters.has(coord):
		_canisters[coord] = _decide_canister(data)
	var can_tile: Vector2i = _canisters[coord]
	if can_tile != NONE_TILE:
		var key := DiffStore.key(can_tile.x, can_tile.y)
		if not _taken.has(key) and not _active.has(key):
			_add(key, &"canister", coord)
	for key in _dropped:
		var t := DiffStore.key_tile(key)
		if Grid.chunk_of_tile(t.x, t.y) == coord and not _active.has(key):
			_add(key, _dropped[key], coord)


## Канистра в чанке — решается один раз, при первой загрузке, по текущей плотности D(t).
func _decide_canister(data: ChunkData) -> Vector2i:
	var density := rules.canister_d0 * maxf(rules.canister_floor, 1.0 - run_time / rules.canister_fade_s)
	if DetRng.unit(run_seed, data.coord.x, data.coord.y, 620) >= density:
		return NONE_TILE
	var tile := PickupGenerator.random_free_tile(data, run_seed, 621)
	return NONE_TILE if tile.x == -999999 else tile


func _add(key: int, kind: StringName, coord: Vector2i) -> void:
	_active[key] = kind
	var keys: PackedInt64Array = _by_chunk.get(coord, PackedInt64Array())
	keys.append(key)
	_by_chunk[coord] = keys


func _tile_free(t: Vector2i) -> bool:
	var d := terrain.owner_of(t.x, t.y)
	if d == null:
		return false
	return PickupGenerator.free_tile(d, d.local_index(t.x, t.y))


## Пересборка визуала чанка: по MultiMesh на вид, высота — по поверхности.
func _rebuild(coord: Vector2i) -> void:
	var node: Node3D = _nodes.get(coord)
	if node == null:
		node = Node3D.new()
		node.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		add_child(node)
		_nodes[coord] = node
	for child in node.get_children():
		child.queue_free()
	var per_kind: Dictionary[StringName, Array] = {}
	for key in _by_chunk.get(coord, PackedInt64Array()):
		var kind: StringName = _active[key]
		if not per_kind.has(kind):
			per_kind[kind] = []
		var t := DiffStore.key_tile(key)
		var y := query.surface_y(t.x + 0.5, t.y + 0.5)
		per_kind[kind].append(Vector3(t.x + 0.5, y + HOVER_Y, t.y + 0.5))
	for kind in per_kind:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _meshes[kind]
		var positions: Array = per_kind[kind]
		mm.instance_count = positions.size()
		for i in positions.size():
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, positions[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(mmi)


## Пиксельный узор находки по форме (pickup.gdshader, pattern).
const PATTERNS := {
	PickupKind.Shape.CRYSTAL: 1, PickupKind.Shape.CAPSULE: 2, PickupKind.Shape.ORB: 3,
	PickupKind.Shape.GEAR: 4, PickupKind.Shape.JERRYCAN: 5,
}


static func _make_mesh(kind: PickupKind, shader: Shader, outline: Material) -> Mesh:
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("base_color", kind.color)
	mat.set_shader_parameter("glow", kind.glow)
	mat.set_shader_parameter("size", kind.size)
	mat.set_shader_parameter("pattern", PATTERNS.get(kind.shape, 0))
	mat.next_pass = outline
	var s := kind.size
	var mesh: Mesh
	match kind.shape:
		PickupKind.Shape.CRYSTAL:
			var m := SphereMesh.new()      # 4 сегмента × 2 кольца — октаэдр
			m.radius = s * 0.6
			m.height = s * 1.8
			m.radial_segments = 4
			m.rings = 2
			mesh = m
		PickupKind.Shape.CAPSULE:
			var m := CapsuleMesh.new()
			m.radius = s * 0.4
			m.height = s * 1.4
			m.radial_segments = 6
			m.rings = 1
			mesh = m
		PickupKind.Shape.ORB:
			var m := SphereMesh.new()
			m.radius = s * 0.6
			m.height = s * 1.2
			m.radial_segments = 8
			m.rings = 4
			mesh = m
		PickupKind.Shape.BOX:
			var m := BoxMesh.new()
			m.size = Vector3(s, s * 0.7, s)
			mesh = m
		PickupKind.Shape.GEAR:
			mesh = _gear_mesh(s)
		PickupKind.Shape.JERRYCAN:
			mesh = _jerrycan_mesh(s)
		_:
			var m := CylinderMesh.new()
			m.top_radius = s * 0.4
			m.bottom_radius = s * 0.4
			m.height = s * 1.3
			m.radial_segments = 8
			m.rings = 0
			mesh = m
	if mesh is PrimitiveMesh:
		(mesh as PrimitiveMesh).material = mat
	else:
		mesh.surface_set_material(0, mat)
	return mesh


## Шестерёнка ремкомплекта: плоская, лежит; 6 крупных зубьев, отверстие ступицы. Вращение находки вокруг Y
## (шейдер) — шестерня крутится, как в механизме. Верх и низ — кольцо между контуром зубьев и
## отверстием (точки отверстия — на тех же углах, что и контура), стенки снаружи и внутри.
static func _gear_mesh(s: float) -> ArrayMesh:
	const TEETH := 6
	var r_tip := s * 0.62
	var r_root := s * 0.4
	var r_hole := s * 0.15
	var h := s * 0.26
	var outer: Array[Vector2] = []
	var angles: Array[float] = []
	var step := TAU / TEETH
	for i in TEETH:
		var a := i * step
		# Зуб занимает середину шага: основание, вершина, вершина, основание.
		for k: Array in [[0.1, r_root], [0.28, r_tip], [0.62, r_tip], [0.8, r_root]]:
			var ang: float = a + step * float(k[0])
			angles.append(ang)
			outer.append(Vector2.from_angle(ang) * float(k[1]))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := outer.size()
	for i in n:
		var j := (i + 1) % n
		var o0 := outer[i]
		var o1 := outer[j]
		var i0 := Vector2.from_angle(angles[i]) * r_hole
		var i1 := Vector2.from_angle(angles[j]) * r_hole
		for y: float in [h * 0.5, -h * 0.5]:
			var nrm := Vector3.UP if y > 0.0 else Vector3.DOWN
			MeshKit.tri(st, Vector3(o0.x, y, o0.y), Vector3(o1.x, y, o1.y), Vector3(i0.x, y, i0.y), nrm)
			MeshKit.tri(st, Vector3(o1.x, y, o1.y), Vector3(i1.x, y, i1.y), Vector3(i0.x, y, i0.y), nrm)
		var e := o1 - o0
		var side := Vector3(e.y, 0.0, -e.x).normalized()
		if side.dot(Vector3(o0.x + o1.x, 0.0, o0.y + o1.y)) < 0.0:
			side = -side
		var a0 := Vector3(o0.x, -h * 0.5, o0.y)
		var a1 := Vector3(o1.x, -h * 0.5, o1.y)
		MeshKit.tri(st, a0, a1, a1 + Vector3(0, h, 0), side)
		MeshKit.tri(st, a0, a1 + Vector3(0, h, 0), a0 + Vector3(0, h, 0), side)
		var b0 := Vector3(i0.x, -h * 0.5, i0.y)
		var b1 := Vector3(i1.x, -h * 0.5, i1.y)
		var inward := -Vector3(i0.x + i1.x, 0.0, i0.y + i1.y).normalized()
		MeshKit.tri(st, b0, b1, b1 + Vector3(0, h, 0), inward)
		MeshKit.tri(st, b0, b1 + Vector3(0, h, 0), b0 + Vector3(0, h, 0), inward)
	return st.commit()


## Канистра топлива: высокий плоский бак с фаской, сверху ручка из трёх перемычек, на углу — горлышко
## с крышкой. Стоит; вращение находки показывает её то плашмя, то боком.
static func _jerrycan_mesh(s: float) -> ArrayMesh:
	var w := s * 0.72
	var d := s * 0.34
	var hgt := s * 0.9
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := BoxMesh.new()
	body.size = Vector3(w, hgt, d)
	st.append_from(body, 0, Transform3D(Basis.IDENTITY, Vector3(0, 0, 0)))
	# Ручка: две стойки и перекладина над баком, ближе к одному краю.
	var top := hgt * 0.5
	for x: float in [-w * 0.32, w * 0.02]:
		var post := BoxMesh.new()
		post.size = Vector3(s * 0.06, s * 0.12, d * 0.4)
		st.append_from(post, 0, Transform3D(Basis.IDENTITY, Vector3(x, top + s * 0.06, 0)))
	var bar := BoxMesh.new()
	bar.size = Vector3(w * 0.42, s * 0.05, d * 0.4)
	st.append_from(bar, 0, Transform3D(Basis.IDENTITY, Vector3(-w * 0.15, top + s * 0.13, 0)))
	# Горлышко с крышкой — на другом углу, наклонено наружу.
	var neck := CylinderMesh.new()
	neck.top_radius = s * 0.06
	neck.bottom_radius = s * 0.07
	neck.height = s * 0.14
	neck.radial_segments = 6
	neck.rings = 0
	st.append_from(neck, 0, Transform3D(Basis(Vector3.BACK, -0.45), Vector3(w * 0.33, top + s * 0.05, 0)))
	return st.commit()
